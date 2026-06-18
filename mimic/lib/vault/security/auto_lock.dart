// lib/vault/security/auto_lock.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../crypto/vault_crypto.dart';
import '../services/media_stream_server.dart';
import '../services/video_vault_service.dart';
import '../../core/services/platform_service.dart';

class AutoLock with WidgetsBindingObserver {
  static final AutoLock _instance = AutoLock._internal();
  factory AutoLock() => _instance;
  AutoLock._internal();

  Timer? _timer;
  BuildContext? _context;
  WidgetRef? _ref;
  static const Duration _timeout = Duration(seconds: 60);
  bool _observerRegistered = false;
  DateTime? _backgroundedAt;

  /// Initializes the inactivity timer. Called when vault is unlocked.
  void init(BuildContext context, WidgetRef ref) {
    _context = context;
    _ref = ref;

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
        _backgroundedAt = DateTime.now();   // record when we left the foreground
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
    if (_context == null || _ref == null) return;
    _timer = Timer(_timeout, _lockVault);
  }

  /// Cancels the timer. Called when manually locked or panic mode triggers.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _context = null;
    _ref = null;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _backgroundedAt = null;
  }

  void _lockVault() {
    if (_context == null || _ref == null) return;
    if (!_context!.mounted) {
      dispose();
      return;
    }

    // Clear Vault keys
    final crypto = _ref!.read(vaultCryptoProvider);
    crypto.clearKey();

    unawaited(MediaStreamServer.instance.stop());

    try {
      getTemporaryDirectory().then((tempDir) {
        final playbackDir = Directory('${tempDir.path}/vault_playback');
        if (playbackDir.existsSync()) {
          playbackDir.deleteSync(recursive: true);
        }
        final docsDir = Directory('${tempDir.path}/vault_docs');
        if (docsDir.existsSync()) {
          docsDir.deleteSync(recursive: true);
        }
      });
    } catch (_) {}

    // Navigate back to PIN screen
    if (_context!.mounted) {
      Navigator.of(_context!).pushNamedAndRemoveUntil(
        '/vault-pin',
        (route) => false,
      );
    }

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
