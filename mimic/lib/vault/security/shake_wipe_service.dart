// mimic/lib/vault/security/shake_wipe_service.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeWipeService {
  static const double _shakeThreshold = 25.0;
  static const int _shakeWindowMs = 2000;
  static const int _minShakesRequired = 2;

  StreamSubscription<AccelerometerEvent>? _subscription;
  int _shakeCount = 0;
  DateTime? _lastShakeTime;
  VoidCallback? _onWipeTriggered;
  bool _isListening = false;

  void startListening(VoidCallback onWipeTriggered) {
    if (_isListening) return;
    if (kIsWeb) return;
    _onWipeTriggered = onWipeTriggered;
    _shakeCount = 0;
    _lastShakeTime = null;
    _isListening = true;

    _subscription = accelerometerEventStream().listen(_onAccelerometerEvent);
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    _onWipeTriggered = null;
    _shakeCount = 0;
    _lastShakeTime = null;
  }

  bool get isListening => _isListening;

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_isListening) return;

    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (magnitude < _shakeThreshold) return;

    final now = DateTime.now();
    if (_lastShakeTime != null && now.difference(_lastShakeTime!).inMilliseconds > _shakeWindowMs) {
      _shakeCount = 0;
    }

    _shakeCount++;
    _lastShakeTime = now;

    if (_shakeCount >= _minShakesRequired) {
      _shakeCount = 0;
      _lastShakeTime = null;
      _onWipeTriggered?.call();
    }
  }
}

final shakeWipeServiceProvider = Provider<ShakeWipeService>((ref) {
  return ShakeWipeService();
});
