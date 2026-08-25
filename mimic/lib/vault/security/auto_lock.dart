// lib/vault/security/auto_lock.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../crypto/vault_crypto.dart';
import '../services/media_stream_server.dart';
import '../services/video_vault_service.dart';
import '../../core/services/platform_service.dart';
import '../../core/router/app_router.dart' as router;

class AutoLock with WidgetsBindingObserver {
  static final AutoLock _instance = AutoLock._internal();
  factory AutoLock() => _instance;
  AutoLock._internal();

  static GlobalKey<NavigatorState> get navigatorKey => router.navigatorKey;

  Timer? _timer;
  Timer? _suspendTimer;
  BuildContext? _context;
  WidgetRef? _ref;
  ProviderContainer? _container;
  // M20: three different clocks, for three different situations.
  //   foreground idle   5 minutes  — long enough to read a screen, short enough that an
  //                                  abandoned unlocked phone does not stay open.
  //   background grace  1 minute   — the app is unattended and out of sight; lock fast. This
  //                                  applies even when a screen has paused the idle clock.
  //   suspendCeiling    30 minutes — final backstop for read-only screens (decision D13).
  static const Duration _timeout = Duration(minutes: 5);
  static const Duration _backgroundGrace = Duration(minutes: 1);
  static const Duration suspendCeiling = Duration(minutes: 30);
  bool _observerRegistered = false;
  DateTime? _backgroundedAt;
  // M22: Android delivers the picker result and the "back in foreground" event
  // independently, and the order is not guaranteed. Cancelling the picker releases the
  // protected-operation claim instantly, so by the time the foreground event arrives
  // the counter is already zero and the 1-minute background rule locks the vault -
  // confirmed on device 2026-08-20. Recording whether a claim was held AT THE MOMENT
  // WE LEFT the foreground removes the race, because that answer cannot change while
  // the app is away. The 30-minute ceiling still applies to the trip.
  bool _protectedOpAtPause = false;
  // M18: six screens share this one pause. A boolean let whichever screen resumed first
  // un-pause the vault for the others. The counter means the idle timer only restarts when
  // the LAST caller has resumed. The 30-minute ceiling (decision D13) is armed by the first
  // caller and is not extended by later ones.
  int _suspendCount = 0;

  // M21: a protected operation is an encrypt or decrypt that is actively writing a file.
  // Locking mid-write clears the keys and deletes the transient plaintext while a blob is
  // half-written, which corrupts it. This is the ONLY exemption from the 1-minute background
  // rule, and it exists to prevent data loss, not for convenience.
  int _protectedOpCount = 0;

  @visibleForTesting
  bool get isSuspended => _suspendCount > 0;

  @visibleForTesting
  int get suspendCount => _suspendCount;

  @visibleForTesting
  bool get isProtectedOperationInFlight => _protectedOpCount > 0;

  @visibleForTesting
  int get protectedOperationCount => _protectedOpCount;

  @visibleForTesting
  void setBackgroundedAtForTesting(DateTime? dt) {
    _backgroundedAt = dt;
  }

  /// Initializes the inactivity timer. Called when vault is unlocked.
  void init(BuildContext context, WidgetRef ref) {
    _context = context;
    _ref = ref;
    _container = ProviderScope.containerOf(context, listen: false);

    final videoVaultService = ref.read(videoVaultServiceProvider);
    final platformService = ref.read(platformServiceProvider);
    MediaStreamServer.instance.init(
      videoVaultService: videoVaultService,
      resolveVaultFile: platformService.resolveVaultFile,
      decryptRange: (f, o, l) => VaultCrypto.instance.decryptRangeSystem(f, o, l),
    );

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    // M19: a suspend that never got its matching resume would leave the counter above zero,
    // and resetTimer() would then never arm the idle timer again for the rest of the session.
    // Unlocking is a clean slate: nobody can legitimately be holding a pause at this moment.
    _suspendCount = 0;
    _protectedOpCount = 0;
    _protectedOpAtPause = false;

    resetTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_backgroundedAt == null) {
          _backgroundedAt = DateTime.now();
          _protectedOpAtPause = _protectedOpCount > 0;
        }
        _timer?.cancel();                   // foreground idle timer is meaningless in background
        break;
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        final bool protectedTrip = _protectedOpCount > 0 || _protectedOpAtPause;
        _protectedOpAtPause = false;
        if (protectedTrip) {
          if (since != null && DateTime.now().difference(since) >= suspendCeiling) {
            _lockVault();
          }
        } else if (since != null && DateTime.now().difference(since) >= _backgroundGrace) {
          _lockVault();
        } else if (_suspendCount > 0) {
          // Leave it paused, do not restart idle timer
        } else {
          resetTimer();
        }
        break;
      case AppLifecycleState.inactive:
        break;                               // transient (app switcher / shade) -> ignore, never lock
    }
  }

  /// Resets the inactivity timer. Called on user interactions.
  void resetTimer() {
    _timer?.cancel();
    if (_suspendCount > 0) return;
    if (_context == null || _ref == null) return;
    _timer = Timer(_timeout, _lockVault);
  }

  void suspend() {
    _suspendCount++;
    if (_suspendCount == 1) {
      _timer?.cancel();
      _timer = null;
      _suspendTimer?.cancel();
      _suspendTimer = Timer(suspendCeiling, _lockVault);
    }
  }

  void resume() {
    if (_suspendCount > 0) {
      _suspendCount--;
      if (_suspendCount == 0) {
        _suspendTimer?.cancel();
        _suspendTimer = null;
        resetTimer();
      }
    }
  }

  void beginProtectedOperation() {
    _protectedOpCount++;
    suspend();
  }

  void endProtectedOperation() {
    if (_protectedOpCount > 0) {
      _protectedOpCount--;
      resume();
    }
  }

  /// Full teardown for the conceal path: stops the media server, wipes transient
  /// plaintext, and cancels the idle timer and lifecycle observer. Fire-and-forget
  /// so that concealment navigation is never delayed by disk I/O.
  void tearDownForConceal() {
    unawaited(MediaStreamServer.instance.stop());
    unawaited(wipeTransientPlaintext());
    dispose();
  }

  /// Cancels the timer and stops the media server. Called when manually locked
  /// or panic mode triggers, so every manual lock path tears down streaming.
  void dispose() {
    unawaited(MediaStreamServer.instance.stop());
    _timer?.cancel();
    _timer = null;
    _suspendTimer?.cancel();
    _suspendTimer = null;
    _context = null;
    _ref = null;
    _container = null;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _backgroundedAt = null;
    _suspendCount = 0;
    _protectedOpCount = 0;
    _protectedOpAtPause = false;
  }

  static const _maxSecureWipeBytes = 64 * 1024 * 1024;

  static Future<void> secureDeleteFile(File f) async {
    try {
      if (!await f.exists()) return;
      final len = await f.length();
      if (len > 0 && len <= _maxSecureWipeBytes) {
        // Best-effort overwrite (FTL/wear-leveling may map to new physical blocks)
        final raf = await f.open(mode: FileMode.writeOnly);
        try {
          final rand = Random.secure();
          const chunkSize = 64 * 1024;
          var remaining = len;
          while (remaining > 0) {
            final writeSize = remaining < chunkSize ? remaining : chunkSize;
            final buf = Uint8List.fromList(List.generate(writeSize, (_) => rand.nextInt(256)));
            await raf.writeFrom(buf);
            remaining -= writeSize;
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
      }
      await f.delete();
    } catch (_) {}
  }

  static Future<void> secureDeleteDir(Directory d) async {
    try {
      if (!await d.exists()) return;
      await for (final entity in d.list(recursive: true)) {
        if (entity is File) {
          await secureDeleteFile(entity);
        }
      }
      await d.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> wipeTransientPlaintext() async {
    try {
      final tempDir = await getTemporaryDirectory();
      for (final name in const ['vault_playback', 'vault_docs', 'vault_share']) {
        final dir = Directory('${tempDir.path}/$name');
        await secureDeleteDir(dir);
      }
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.contains('_migrate_plain_') || name.contains('_migrate_ctr_')) {
            await secureDeleteFile(entity);
          }
        }
      }
    } catch (_) {}
  }

  void _lockVault() async {
    final container = _container;
    if (container == null) {
      _suspendCount = 0;
      _protectedOpCount = 0;
      _protectedOpAtPause = false;
      return;
    }

    final bool wasUnlocked;
    try {
      final crypto = container.read(vaultCryptoProvider);
      wasUnlocked = crypto.isUnlocked;
      if (!wasUnlocked) {
        dispose();
        return;
      }
      // Clear Vault keys
      crypto.clearKey();
    } on StateError {
      dispose();
      return;
    }

    unawaited(MediaStreamServer.instance.stop());

    await wipeTransientPlaintext();

    AutoLock.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/vault-pin',
      (route) => false,
    );

    dispose();
  }
}

/// A wrapper widget that transparently listens to all user interactions
/// (tap down, scrolls, swipe/drag, mouse movement) to reset the auto-lock timer.
class AutoLockWrapper extends StatelessWidget {
  final Widget child;

  const AutoLockWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => AutoLock().resetTimer(),
      onPointerMove: (_) => AutoLock().resetTimer(),
      onPointerSignal: (_) => AutoLock().resetTimer(),
      child: child,
    );
  }
}
