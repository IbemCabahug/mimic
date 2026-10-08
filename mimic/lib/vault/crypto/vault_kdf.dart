// lib/vault/crypto/vault_kdf.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'keystore_service.dart';
import 'hardened_verifier.dart'; // v4 verifier, for parseAnyPinVerifier's dispatch

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

/// A stored PIN verifier of ANY supported version, normalised to the two facts
/// every caller actually needs: the iteration count to derive at, and the digest
/// to compare against.
///
/// This is the type that lets v2, v3 and v4 coexist. Before this existed, every
/// call site hand-rolled `parsed.version == 3 ? 'v3:...' : 'v2:...'`, which is
/// correct for exactly two versions and silently WRONG the moment a third is
/// added: a v4 record would fall into the v2 branch and build a 'v2:...' string
/// that can never match, so the correct PIN would be rejected. Normalising the
/// version string into the record itself removes that class of bug.
class AnyPinVerifier {
  /// The record's version: 2, 3 or 4.
  final int version;

  /// The iteration count this record was WRITTEN at, which is the count a
  /// candidate PIN must be derived at to be compared against it. Never assumed,
  /// always read back from the record.
  final int iterations;

  /// The base64 SHA-256 digest stored in the record.
  final String digestBase64;

  const AnyPinVerifier({
    required this.version,
    required this.iterations,
    required this.digestBase64,
  });
}

/// Rebuilds the canonical verifier string for [key] at [verifier]'s own version
/// and iteration count.
///
/// This is the single place that knows how to spell each version. A caller gets
/// the exact string the record should contain for a given key, so a comparison
/// cannot drift from the format the record was written in.
///
/// v2 IS SPECIAL AND DELIBERATELY SO. A v2 record has NO iteration segment —
/// it is `v2:<digest>`, two segments — because the cost was fixed at
/// [kLegacyV2Iterations] when the format was written. Emitting
/// `v2:100000:<digest>` would produce a string that can never match a real v2
/// record, so every v2 vault would stop unlocking. This was a live regression
/// caught by the round-trip test the first time this dispatcher was wired in,
/// which is precisely why the spelling lives in ONE function guarded by a test
/// per version instead of being re-derived at five call sites.
///
/// Returns null when [key] is empty, so a caller cannot accidentally compare
/// against a digest of nothing.
String? rebuildVerifierFor(AnyPinVerifier verifier, Uint8List key) {
  if (key.isEmpty) return null;
  final digest = base64Encode(SHA256Digest().process(key));
  if (verifier.version == 2) {
    // Two segments only. Never add an iteration count here.
    return 'v2:$digest';
  }
  return 'v${verifier.version}:${verifier.iterations}:$digest';
}

/// True when the hardened (v4) verifier machinery applies to [storedHash].
///
/// A thin re-export so callers that already import vault_kdf do not need a
/// second import just to ask this question. Kept here because this file is the
/// historical home of the verifier format, and the dispatch decision belongs
/// beside the formats it dispatches between.
bool isHardenedPinVerifier(String storedHash) =>
    storedHash.startsWith('v4:');

/// Parses ANY supported verifier record (v2, v3 or v4) into [AnyPinVerifier].
///
/// This is the dispatcher that replaces the per-call-site version ternaries.
/// It fails closed on anything unrecognised, malformed, or out of bounds, and
/// it delegates the version-specific bounds to the parser that owns them, so v3
/// keeps its 100,000..1,000,000 window and v4 keeps its 600,000..4,000,000 one.
///
/// A v4 record is validated by [parseHardenedVerifier]; a v2 or v3 record by
/// [parseVerifier]. Neither parser can be reached for the other's version, so
/// the stricter floor cannot leak onto legacy records and lock anyone out.
AnyPinVerifier parseAnyPinVerifier(String storedHash) {
  if (isHardenedPinVerifier(storedHash)) {
    final hardened = parseHardenedVerifier(storedHash);
    return AnyPinVerifier(
      version: 4,
      iterations: hardened.iterations,
      digestBase64: hardened.digestBase64,
    );
  }
  final legacy = parseVerifier(storedHash);
  return AnyPinVerifier(
    version: legacy.version,
    iterations: legacy.iterations,
    digestBase64: legacy.digestBase64,
  );
}

/// Compares two strings in constant time to mitigate timing attacks.
///
/// This is the shared public copy. Three private copies still exist in
/// `vault_crypto.dart`, `duress_service.dart`, and `local_streaming_server.dart`
/// and are deliberately left alone for now, recorded as defect L20.
bool constantTimeEquals(String a, String b) {
  final ab = utf8.encode(a);
  final bb = utf8.encode(b);
  if (ab.length != bb.length) return false;
  var result = 0;
  for (var i = 0; i < ab.length; i++) {
    result |= ab[i] ^ bb[i];
  }
  return result == 0;
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
      final res = await nativeDerive(password, salt, iterations, keyLength);
      return Uint8List.fromList(res);
    } catch (e) {
      return _computePointycastlePbkdf2(password, salt, iterations, keyLength);
    }
  }

  return _computePointycastlePbkdf2(password, salt, iterations, keyLength);
}

