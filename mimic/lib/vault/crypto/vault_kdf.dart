// lib/vault/crypto/vault_kdf.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'keystore_service.dart';

/// Public constant for the current PBKDF2 iteration count.
const int kPbkdf2Iterations = 100000;

/// FROZEN: PBKDF2 iteration count for recovery phrases.
/// Changing this iteration count permanently destroys existing recovery phrases.
/// It can only move once the recovery record format carries a version and iteration field.
const int kRecoveryPhraseIterations = 100000;

/// FROZEN: PBKDF2 iteration count for duress PINs.
/// Changing this iteration count permanently destroys existing duress PINs.
/// It can only move once the duress record format carries a version and iteration field.
const int kDuressIterations = 100000;

/// FROZEN: v2 verifier records were always written at exactly this count.
/// This is a historical fact about bytes already on disk, not a policy knob.
/// Changing it locks out every vault still holding a v2 record.
const int kLegacyV2Iterations = 100000;

/// Public constant for the derived key length in bytes (AES-256).
const int kDerivedKeyLength = 32;

/// Minimum allowable PBKDF2 iterations for PIN verifiers (floor).
const int kMinPbkdf2Iterations = 100000;

/// Maximum allowable PBKDF2 iterations for PIN verifiers (ceiling).
const int kMaxPbkdf2Iterations = 1000000;

/// Typed exception thrown when a PIN verifier string is malformed or uses an unsupported format.
class InvalidVerifierException implements Exception {
  final String message;
  InvalidVerifierException([this.message = 'Invalid or unsupported PIN verifier format.']);

  @override
  String toString() => 'InvalidVerifierException: $message';
}

/// Parsed representation of a stored PIN verifier record.
class ParsedVerifier {
  final int version;
  final int iterations;
  final String digestBase64;
  final String raw;

  const ParsedVerifier({
    required this.version,
    required this.iterations,
    required this.digestBase64,
    required this.raw,
  });
}

/// Parses and validates a stored PIN verifier record.
///
/// Accepts:
/// - 'v3:<iterations>:<base64 sha256 of key>'
/// - 'v2:<base64 sha256 of key>' (treated as 100,000 iterations)
///
/// Fails closed with [InvalidVerifierException] for any malformed, missing,
/// non-numeric, out-of-bounds, or unsupported verifier string.
ParsedVerifier parseVerifier(String storedHash) {
  if (storedHash.startsWith('v3:')) {
    final parts = storedHash.split(':');
    if (parts.length != 3) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: expected exactly 3 colon-separated segments, got ${parts.length}',
      );
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: non-numeric iteration count "${parts[1]}"',
      );
    }
    if (iterations < kMinPbkdf2Iterations || iterations > kMaxPbkdf2Iterations) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: iteration count $iterations out of allowable bounds [$kMinPbkdf2Iterations, $kMaxPbkdf2Iterations]',
      );
    }
    if (parts[2].isEmpty) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: empty base64 digest',
      );
    }
    return ParsedVerifier(
      version: 3,
      iterations: iterations,
      digestBase64: parts[2],
      raw: storedHash,
    );
  } else if (storedHash.startsWith('v2:')) {
    final parts = storedHash.split(':');
    if (parts.length != 2 || parts[1].isEmpty) {
      throw InvalidVerifierException(
        'Malformed v2 verifier: expected "v2:<base64>"',
      );
    }
    return ParsedVerifier(
      version: 2,
      iterations: kLegacyV2Iterations,
      digestBase64: parts[1],
      raw: storedHash,
    );
  } else {
    throw InvalidVerifierException(
      'Unsupported verifier format (expected "v3:" or "v2:"): $storedHash',
    );
  }
}

/// Formats a v3 PIN verifier string from a derived key and iteration count.
///
/// Format: 'v3:<iterations>:<base64 sha256 of key>'
String formatVerifier(Uint8List key, [int iterations = kPbkdf2Iterations]) {
  final digest = SHA256Digest().process(key);
  return 'v3:$iterations:${base64Encode(digest)}';
}

/// Derives a PIN-based key-encryption key (KEK) from a PIN and base64-encoded salt.
///
/// Uses PBKDF2-HMAC-SHA256 with the specified [iterations] (default [kPbkdf2Iterations])
/// and [kDerivedKeyLength] (32 bytes). It is synchronous and pure.
Uint8List deriveVaultPinKek(String pin, String saltBase64, [int iterations = kPbkdf2Iterations]) {
  final salt = base64Decode(saltBase64);
  final pinBytes = Uint8List.fromList(utf8.encode(pin));
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, kDerivedKeyLength));
  return pbkdf2.process(pinBytes);
}

// Private known-answer test vector constants
final Uint8List _kVectorPassword = Uint8List.fromList(utf8.encode('password'));
final Uint8List _kVectorSalt = Uint8List.fromList(utf8.encode('salt'));
const int _kVectorIterations = 4096;
const int _kVectorKeyLength = 32;

Uint8List _computePointycastlePbkdf2(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLength,
) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, keyLength));
  return pbkdf2.process(password);
}

bool? _isNativePbkdf2Verified;

/// Native PBKDF2 self-check state: null = not yet attempted, true = verified,
/// false = verification failed and pointycastle is in use.
bool? get isNativePbkdf2Verified => _isNativePbkdf2Verified;

/// Resets the cached native PBKDF2 verification flag for tests.
@visibleForTesting
void resetNativePbkdf2VerificationForTests() {
  _isNativePbkdf2Verified = null;
}

/// Asynchronously derives a key using native PBKDF2 if verified, falling back to PointyCastle.
Future<Uint8List> derivePbkdf2Async(
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLength, {
  Future<Uint8List> Function(Uint8List, Uint8List, int, int)? native,
}) async {
  final nativeDerive = native ?? nativePbkdf2;

  if (kIsWeb) {
    return _computePointycastlePbkdf2(password, salt, iterations, keyLength);
  }

  if (_isNativePbkdf2Verified == null) {
    try {
      final expected = _computePointycastlePbkdf2(
        _kVectorPassword,
        _kVectorSalt,
        _kVectorIterations,
        _kVectorKeyLength,
      );
      final actual = await nativeDerive(
        _kVectorPassword,
        _kVectorSalt,
        _kVectorIterations,
        _kVectorKeyLength,
      );
      if (actual.length == expected.length) {
        var match = true;
        for (var i = 0; i < expected.length; i++) {
          if (actual[i] != expected[i]) {
            match = false;
            break;
          }
        }
        _isNativePbkdf2Verified = match;
      } else {
        _isNativePbkdf2Verified = false;
      }
    } catch (e) {
      _isNativePbkdf2Verified = false;
    }
  }

  if (_isNativePbkdf2Verified == true) {
    try {
      return await nativeDerive(password, salt, iterations, keyLength);
    } catch (e) {
      return _computePointycastlePbkdf2(password, salt, iterations, keyLength);
    }
  }

  return _computePointycastlePbkdf2(password, salt, iterations, keyLength);
}

