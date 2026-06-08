// mimic/lib/vault/security/duress_service.dart
import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/platform_service.dart';

class DuressService {
  static const String _pinHashKey = 'duress_pin_hash';
  static const String _pinSaltKey = 'duress_pin_salt';

  final PlatformService _platformService;

  DuressService(this._platformService);

  Future<void> setFakePin(String pin) async {
    if (kIsWeb) return;
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _platformService.secureWrite(_pinHashKey, hash);
    await _platformService.secureWrite(_pinSaltKey, salt);
  }

  Future<bool> isFakePin(String pin) async {
    if (kIsWeb) return false;
    final storedHash = await _platformService.secureRead(_pinHashKey);
    final storedSalt = await _platformService.secureRead(_pinSaltKey);
    if (storedHash == null || storedSalt == null) return false;
    final computedHash = _hashPin(pin, storedSalt);
    return computedHash == storedHash;
  }

  Future<bool> isFakePinEnabled() async {
    if (kIsWeb) return false;
    final hash = await _platformService.secureRead(_pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> clearFakePin() async {
    if (kIsWeb) return;
    await _platformService.secureDelete(_pinHashKey);
    await _platformService.secureDelete(_pinSaltKey);
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

final duressServiceProvider = Provider<DuressService>((ref) {
  return DuressService(ref.read(platformServiceProvider));
});
