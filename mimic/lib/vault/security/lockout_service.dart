import 'package:flutter/services.dart';
import 'package:mimic/core/services/platform_service.dart';

abstract class MonotonicClock {
  Future<int> elapsedRealtime();
}

class AndroidMonotonicClock implements MonotonicClock {
  static const MethodChannel _channel = MethodChannel('mimic/keystore');

  @override
  Future<int> elapsedRealtime() async {
    final result = await _channel.invokeMethod<int>('elapsedRealtime');
    return result ?? 0;
  }
}

class FakeMonotonicClock implements MonotonicClock {
  int value = 0;

  @override
  Future<int> elapsedRealtime() async {
    return value;
  }
}

Duration cooldownForAttempts(int attempts) {
  if (attempts <= 4) return Duration.zero;
  if (attempts == 5) return const Duration(seconds: 30);
  if (attempts == 6) return const Duration(seconds: 60);
  if (attempts == 7) return const Duration(minutes: 5);
  if (attempts == 8) return const Duration(minutes: 15);
  if (attempts == 9) return const Duration(minutes: 30);
  return const Duration(minutes: 60); // 10+
}

class LockoutService {
  final PlatformService _storage;
  final MonotonicClock _clock;

  LockoutService(this._storage, this._clock);

  Future<void> setLockout(int attempts) async {
    final duration = cooldownForAttempts(attempts);
    if (duration == Duration.zero) return;

    final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
    final nowElapsed = await _clock.elapsedRealtime();

    await _storage.secureWrite('lockout_set_wall', nowWall.toString());
    await _storage.secureWrite('lockout_set_elapsed', nowElapsed.toString());
    await _storage.secureWrite('lockout_duration_ms', duration.inMilliseconds.toString());
  }

  Future<Duration> remainingLockout() async {
    final wallStr = await _storage.secureRead('lockout_set_wall');
    final elapsedStr = await _storage.secureRead('lockout_set_elapsed');
    final durationStr = await _storage.secureRead('lockout_duration_ms');

    if (wallStr == null || elapsedStr == null || durationStr == null) {
      return Duration.zero;
    }

    final setWall = int.tryParse(wallStr) ?? 0;
    final setElapsed = int.tryParse(elapsedStr) ?? 0;
    final durationMs = int.tryParse(durationStr) ?? 0;

    final duration = Duration(milliseconds: durationMs);

    final nowWall = DateTime.now().toUtc().millisecondsSinceEpoch;
    final nowElapsed = await _clock.elapsedRealtime();

    Duration wallRemaining = duration - Duration(milliseconds: nowWall - setWall);
    Duration elapsedRemaining = duration - Duration(milliseconds: nowElapsed - setElapsed);

    // BACKWARD-CLOCK GUARD
    if (nowWall < setWall) {
      wallRemaining = elapsedRemaining; // Ignore wall, use elapsed. (Will be maxed later against elapsed)
    }

    // REBOOT GUARD
    if (nowElapsed < setElapsed) {
      elapsedRemaining = wallRemaining; // Ignore elapsed, use wall.
    }

    Duration remaining = wallRemaining > elapsedRemaining ? wallRemaining : elapsedRemaining;

    if (remaining < Duration.zero) {
      remaining = Duration.zero;
    }

    return remaining;
  }

  Future<void> reset() async {
    await _storage.secureDelete('lockout_set_wall');
    await _storage.secureDelete('lockout_set_elapsed');
    await _storage.secureDelete('lockout_duration_ms');
    await _storage.secureDelete('wrong_attempts');
  }
}
