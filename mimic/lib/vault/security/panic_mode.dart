// lib/vault/security/panic_mode.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PanicMode {
  static final PanicMode _instance = PanicMode._internal();
  factory PanicMode() => _instance;
  PanicMode._internal();

  StreamSubscription? _subscription;
  // int _shakeCount = 0;
  // DateTime? _lastShakeTime;

  // Configuration thresholds
  // static const double _shakeThreshold = 14.0;
  // static const Duration _minInterval = Duration(milliseconds: 250);
  // static const Duration _maxWindow = Duration(seconds: 2);

  /// Initializes listening to accelerometer events. Called when vault is unlocked.
  /// NOTE: Shake trigger disabled — the global VaultConcealService now handles
  /// shake-based vault concealment. Kept here for future non-shake triggers.
  void init(BuildContext context, WidgetRef ref) {
    _subscription?.cancel();
    // _shakeCount = 0;
    // _lastShakeTime = null;

    // Shake listener disabled; VaultConcealService handles shake-to-conceal globally.
    // _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
    //   final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    //   if (magnitude > _shakeThreshold) {
    //     final now = DateTime.now();
    //     if (_lastShakeTime == null || now.difference(_lastShakeTime!) > _minInterval) {
    //       if (_lastShakeTime != null && now.difference(_lastShakeTime!) > _maxWindow) {
    //         _shakeCount = 1;
    //       } else {
    //         _shakeCount++;
    //       }
    //       _lastShakeTime = now;
    //
    //       if (_shakeCount >= 3) {
    //         if (context.mounted) {
    //           _triggerPanic(context, ref);
    //         }
    //       }
    //     }
    //   }
    // });
  }

  /// Cancels listening. Called when vault is manually locked or panic mode fires.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
