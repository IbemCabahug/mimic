// lib/vault/security/vault_conceal_service.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/core/router/app_router.dart' show navigatorKey;
import 'package:mimic/vault/crypto/vault_crypto.dart' show vaultCryptoProvider;
import 'package:mimic/vault/widgets/blood_splatter_overlay.dart' show showBloodSplatter;

class VaultConcealService {
  final Ref? _ref;
  final PlatformService _platformService;
  // Uses AccelerometerEvent (same stream type as ShakeWipeService) for consistency.
  StreamSubscription<AccelerometerEvent>? _subscription;
  bool _isConcealed = false;
  final ValueNotifier<bool> concealNotifier = ValueNotifier<bool>(false);
  bool _isListeningPaused = false;

  // Shake tracking
  final List<DateTime> _shakeTimestamps = [];
  DateTime? _lastTriggerTime;

  VaultConcealService([this._ref, PlatformService? platformService])
      : _platformService = platformService ?? const PlatformServicePlaceholder();

  Future<void> init() async {
    final val = await _platformService.secureRead('vault_concealed');
    _isConcealed = val == 'true';
    concealNotifier.value = _isConcealed;
  }

  Future<bool> isConcealed() async {
    final val = await _platformService.secureRead('vault_concealed');
    _isConcealed = val == 'true';
    concealNotifier.value = _isConcealed;
    return _isConcealed;
  }

  bool get isConcealedCached => _isConcealed;

  Future<void> setConcealed(bool concealed) async {
    _isConcealed = concealed;
    concealNotifier.value = concealed;
    await _platformService.secureWrite('vault_concealed', concealed ? 'true' : 'false');
  }

  void start() {
    if (_subscription != null) return;
    if (kIsWeb) return;
    // Use accelerometerEventStream() — same stream as ShakeWipeService.
    _subscription = accelerometerEventStream().listen(_onAccelerometerEvent);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void pauseShakeListening() {
    _isListeningPaused = true;
  }

  void resumeShakeListening() {
    _isListeningPaused = false;
  }

  Future<void> _onAccelerometerEvent(AccelerometerEvent event) async {
    if (_isListeningPaused) return;

    // Honor the shake_wipe_enabled SharedPreferences setting
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('shake_wipe_enabled') ?? false;
    if (!enabled) return;

    final now = DateTime.now();
    final lastTrigger = _lastTriggerTime;
    if (lastTrigger != null &&
        now.difference(lastTrigger).inMilliseconds < 1000) {
      return;
    }

    final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    // Threshold 18.0
    if (magnitude < 18.0) return;

    // Enforce minimum interval of 200ms between counted shakes
    if (_shakeTimestamps.isNotEmpty &&
        now.difference(_shakeTimestamps.last).inMilliseconds < 200) {
      return;
    }

    _shakeTimestamps.add(now);

    // 1500ms sliding window
    _shakeTimestamps.removeWhere((t) =>
        now.difference(t).inMilliseconds > 1500);

    // 3 shakes required
    if (_shakeTimestamps.length >= 3) {
      _shakeTimestamps.clear();
      _lastTriggerTime = now;
      await _toggleConceal();
    }
  }

  Future<void> _toggleConceal() async {
    final nextState = !_isConcealed;
    await setConcealed(nextState);

    if (nextState) {
      // Toggle ON: show blood splatter overlay on root navigator's overlay
      final overlay = navigatorKey.currentState?.overlay;
      if (overlay != null) {
        showBloodSplatter(overlay);
      }

      // If vault is currently unlocked, clear the key and navigate to game home '/'
      final ref = _ref;
      if (ref != null) {
        final crypto = ref.read(vaultCryptoProvider);
        if (crypto.isUnlocked) {
          crypto.clearKey();
          navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } else {
      // Toggle OFF: fire a single light HapticFeedback confirmation
      await HapticFeedback.mediumImpact();
    }
  }
}

class PlatformServicePlaceholder implements PlatformService {
  const PlatformServicePlaceholder();
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => null;
  @override
  Future<void> secureWrite(String key, String value) async {}
  @override
  Future<void> secureDelete(String key) async {}
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;
  @override
  Future<void> deleteFile(String path) async {}
}
