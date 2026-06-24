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
  BuildContext? _context;
  WidgetRef? _ref;
  ProviderContainer? _container;
  static const Duration _timeout = Duration(seconds: 60);
  bool _observerRegistered = false;
  DateTime? _backgroundedAt;
  bool _suspended = false;

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

    resetTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgroundedAt ??= DateTime.now();   // record when we left the foreground
        _timer?.cancel();                   // foreground idle timer is meaningless in background
        break;
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && DateTime.now().difference(since) >= _timeout) {
          _lockVault();                      // backgrounded >= timeout -> lock
        } else {
          resetTimer();                      // returned in time -> resume the idle timer
        }
        break;
      case AppLifecycleState.inactive:
        break;                               // transient (app switcher / shade) -> ignore, never lock
    }
  }

  /// Resets the inactivity timer. Called on user interactions.
  void resetTimer() {
    _timer?.cancel();
    if (_suspended) return;
    if (_context == null || _ref == null) return;
    _timer = Timer(_timeout, _lockVault);
  }

  void suspend() {
    _suspended = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    _suspended = false;
    resetTimer();
  }

  /// Cancels the timer. Called when manually locked or panic mode triggers.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _context = null;
    _ref = null;
    _container = null;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _backgroundedAt = null;
    _suspended = false;
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
    if (container == null) return;

    try {
      // Clear Vault keys
      container.read(vaultCryptoProvider).clearKey();
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
