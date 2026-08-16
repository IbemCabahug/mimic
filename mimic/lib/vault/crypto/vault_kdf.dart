// lib/vault/crypto/vault_kdf.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Public constant for the current PBKDF2 iteration count.
const int kPbkdf2Iterations = 100000;

/// Public constant for the derived key length in bytes (AES-256).
const int kDerivedKeyLength = 32;

/// Maximum allowable PBKDF2 iterations for defensive bounds checking (10 million).
const int kMaxPbkdf2Iterations = 10000000;

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
/// non-numeric, non-positive, absurdly large, or unsupported verifier string.
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
    if (iterations <= 0) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: iteration count must be positive, got $iterations',
      );
    }
    if (iterations > kMaxPbkdf2Iterations) {
      throw InvalidVerifierException(
        'Malformed v3 verifier: iteration count $iterations exceeds maximum allowable ($kMaxPbkdf2Iterations)',
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
      iterations: kPbkdf2Iterations,
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

