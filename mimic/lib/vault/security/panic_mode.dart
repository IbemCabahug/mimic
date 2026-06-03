// lib/vault/security/panic_mode.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../crypto/vault_crypto.dart';

class PanicMode {
  static final PanicMode _instance = PanicMode._internal();
  factory PanicMode() => _instance;
  PanicMode._internal();

  StreamSubscription? _subscription;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;

  // Configuration thresholds
  static const double _shakeThreshold = 14.0;
  static const Duration _minInterval = Duration(milliseconds: 250);
  static const Duration _maxWindow = Duration(seconds: 2);

  /// Initializes listening to accelerometer events. Called when vault is unlocked.
  void init(BuildContext context, WidgetRef ref) {
    _subscription?.cancel();
    _shakeCount = 0;
    _lastShakeTime = null;

    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (magnitude > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > _minInterval) {
          if (_lastShakeTime != null && now.difference(_lastShakeTime!) > _maxWindow) {
            // Reset count if the delay since the last shake exceeds our rapid window
            _shakeCount = 1;
          } else {
            _shakeCount++;
          }
          _lastShakeTime = now;

          if (_shakeCount >= 3) {
            if (context.mounted) {
              _triggerPanic(context, ref);
            }
          }
        }
      }
    });
  }

  /// Cancels listening. Called when vault is manually locked or panic mode fires.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _shakeCount = 0;
    _lastShakeTime = null;
  }

  void _triggerPanic(BuildContext context, WidgetRef ref) {
    // 1. Immediately wipe vault access keys
    final crypto = ref.read(vaultCryptoProvider);
    crypto.clearKey();

    // 2. Perform instant cut back to game home screen ('/') with no transition animation.
    // We dynamically look up the widget builder of the '/' route from MaterialApp to avoid direct imports.
    final route = PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) {
        final app = context.findAncestorWidgetOfExactType<MaterialApp>();
        final builder = app?.routes?['/'];
        if (builder != null) {
          return builder(context);
        }
        return const SizedBox.shrink();
      },
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );

    Navigator.of(context).pushAndRemoveUntil(route, (route) => false);

    // 3. De-register sensor listener
    dispose();
  }
}
