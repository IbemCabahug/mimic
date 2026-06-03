// lib/vault/security/auto_lock.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/vault_crypto.dart';

class AutoLock {
  static final AutoLock _instance = AutoLock._internal();
  factory AutoLock() => _instance;
  AutoLock._internal();

  Timer? _timer;
  BuildContext? _context;
  WidgetRef? _ref;
  static const Duration _timeout = Duration(seconds: 60);

  /// Initializes the inactivity timer. Called when vault is unlocked.
  void init(BuildContext context, WidgetRef ref) {
    _context = context;
    _ref = ref;
    resetTimer();
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
  }

  void _lockVault() {
    if (_context == null || _ref == null) return;

    // Clear Vault keys
    final crypto = _ref!.read(vaultCryptoProvider);
    crypto.clearKey();

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
