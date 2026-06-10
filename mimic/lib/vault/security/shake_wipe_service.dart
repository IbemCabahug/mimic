// mimic/lib/vault/security/shake_wipe_service.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeWipeService {
  static const double shakeThreshold = 18.0;
  static const int shakeWindowMs = 1500;
  static const int minShakesRequired = 3;
  static const int refractoryPeriodMs = 1000;

  StreamSubscription<AccelerometerEvent>? _subscription;
  final List<DateTime> _shakeTimestamps = [];
  DateTime? _lastTriggerTime;
  VoidCallback? _onWipeTriggered;
  bool _isListening = false;

  void startListening(VoidCallback onWipeTriggered) {
    if (_isListening) return;
    if (kIsWeb) return;
    _onWipeTriggered = onWipeTriggered;
    _shakeTimestamps.clear();
    _lastTriggerTime = null;
    _isListening = true;

    _subscription = accelerometerEventStream().listen(_onAccelerometerEvent);
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
    _onWipeTriggered = null;
    _shakeTimestamps.clear();
    _lastTriggerTime = null;
  }

  bool get isListening => _isListening;

  void _onAccelerometerEvent(AccelerometerEvent event) {
    if (!_isListening) return;

    final now = DateTime.now();

    // Check refractory window
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!).inMilliseconds < refractoryPeriodMs) {
      return;
    }

    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (magnitude < shakeThreshold) return;

    // Enforce minimum interval of 200ms between counted shake bumps
    if (_shakeTimestamps.isNotEmpty &&
        now.difference(_shakeTimestamps.last).inMilliseconds < 200) {
      return;
    }

    _shakeTimestamps.add(now);

    // Keep only timestamps within the sliding window
    _shakeTimestamps.removeWhere((t) =>
        now.difference(t).inMilliseconds > shakeWindowMs);

    if (_shakeTimestamps.length >= minShakesRequired) {
      _shakeTimestamps.clear();
      _lastTriggerTime = now;
      _onWipeTriggered?.call();
    }
  }
}

final shakeWipeServiceProvider = Provider<ShakeWipeService>((ref) {
  return ShakeWipeService();
});
