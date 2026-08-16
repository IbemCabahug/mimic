// mimic/lib/vault/security/duress_service.dart
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart' as pc;
import '../../core/services/platform_service.dart';
import '../crypto/vault_kdf.dart';

class DuressService {
  static const String _pinHashKey = 'duress_pin_hash';
  static const String _pinSaltKey = 'duress_pin_salt';

  final PlatformService _platformService;

  DuressService(this._platformService);

  String _verifier(String pin, String salt) {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final saltBytes = Uint8List.fromList(utf8.encode(salt));
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(saltBytes, kPbkdf2Iterations, kDerivedKeyLength));
    final derived = pbkdf2.process(pinBytes);
    return 'v2:${base64Encode(derived)}';
  }

  bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var result = 0;
    for (var i = 0; i < ab.length; i++) {
      result |= ab[i] ^ bb[i];
    }
    return result == 0;
  }

  Future<void> setFakePin(String pin) async {
    if (kIsWeb) return;
    final salt = _generateSalt();
    final hash = _verifier(pin, salt);
    await _platformService.secureWrite(_pinHashKey, hash);
    await _platformService.secureWrite(_pinSaltKey, salt);
  }

  Future<bool> isFakePin(String pin) async {
    if (kIsWeb) return false;
    final storedHash = await _platformService.secureRead(_pinHashKey);
    final storedSalt = await _platformService.secureRead(_pinSaltKey);
    if (storedHash == null || storedSalt == null) return false;
    bool ok;
    if (storedHash.startsWith('v2:')) {
      ok = _constantTimeEquals(storedHash, _verifier(pin, storedSalt));
    } else {
      // Legacy single-pass salted SHA-256 — upgrade on success.
      ok = _constantTimeEquals(storedHash, _hashPin(pin, storedSalt));
      if (ok) {
        await _platformService.secureWrite(_pinHashKey, _verifier(pin, storedSalt));
      }
    }
    return ok;
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
