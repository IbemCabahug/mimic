import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class ShakeRouteDetector {
  ShakeRouteDetector({
    this.shakeThreshold = 15.0,
    this.armedWindow = const Duration(seconds: 4),
    this.refractory = const Duration(milliseconds: 500),
  });

  final double shakeThreshold;
  final Duration armedWindow;
  final Duration refractory;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  Timer? _expiryTimer;
  DateTime? _lastShake;
  DateTime? _armedUntil;

  void Function(bool armed)? onArmedChanged;

  bool get isAdminArmed {
    final until = _armedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void start() {
    _sub ??= userAccelerometerEventStream().listen(_onEvent);
  }

  void _onEvent(UserAccelerometerEvent e) {
    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (magnitude < shakeThreshold) return;

    final now = DateTime.now();
    if (_lastShake != null && now.difference(_lastShake!) < refractory) return;
    _lastShake = now;

    final wasArmed = isAdminArmed;
    _armedUntil = now.add(armedWindow);
    if (!wasArmed) onArmedChanged?.call(true);

    _expiryTimer?.cancel();
    _expiryTimer = Timer(armedWindow, () {
      _armedUntil = null;
      onArmedChanged?.call(false);
    });
  }

  void disarm() {
    _expiryTimer?.cancel();
    final wasArmed = isAdminArmed;
    _armedUntil = null;
    if (wasArmed) onArmedChanged?.call(false);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }
}
