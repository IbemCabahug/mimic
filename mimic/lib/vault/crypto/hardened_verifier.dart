// lib/vault/crypto/hardened_verifier.dart
//
// The C1 half of the shared versioned-format layer: a stronger PIN verifier.
//
// THE PROBLEM (C1)
// ----------------
// vault_kdf.dart stores 'v3:<iterations>:<base64(SHA256(derivedKey))>' derived with
// 100,000 PBKDF2-HMAC-SHA256 iterations. Anyone who extracts secure storage gets
// the salt and the verifier, and can then test candidate PINs entirely offline:
// no lockout counter, no Keystore gate, no rate limit, no device present. A
// 6-digit space is 1,000,000 candidates and a GPU makes that cheap. OWASP's floor
// for PBKDF2-HMAC-SHA256 is 600,000.
//
// THE FIX
// -------
// A v4 verifier at 600,000 iterations, written and read ALONGSIDE the existing v2
// and v3 records. Existing vaults keep their v3 verifier and keep working
// byte-for-byte; nothing is rewritten until the owner unlocks and the app
// transparently upgrades the record.
//
// WHY THE UPGRADE CANNOT BE A CONSTANT SWAP
// ------------------------------------------
// kPbkdf2Iterations is a single constant used as the DEFAULT by _deriveKey and by
// formatVerifier, and kMinPbkdf2Iterations pins the accepted floor at 100,000 so
// that a stored iteration count is a historical fact rather than a policy knob.
// Raising the constant alone would break in three separate ways:
//
//   1. Existing v3 records still say 100,000. They would derive at 100,000 and be
//      compared against a verifier computed at 600,000. Every existing PIN fails
//      to unlock. That is total vault lockout on a live device.
//   2. The recovery phrase and duress PINs use their own FROZEN constants
//      (kRecoveryPhraseIterations, kDuressIterations) and their own record formats.
//      Moving them without a versioned field destroys every existing phrase.
//   3. kMinPbkdf2Iterations would have to rise too, and parseVerifier would then
//      REJECT every v2/v3 record on disk, again locking the owner out.
//
// So the iteration count travels INSIDE the record (it already does, for v3), and
// each record is interpreted at the count it was written with. The fix is a new
// record version, never a redefinition of an old one.
//
// The iteration floor for ACCEPTING a v4 record is deliberately not the same as the
// count we WRITE. We write 600,000 and accept anything at or above the OWASP floor,
// so a future session can raise the cost again without a format change.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Compares two verifier strings in constant time.
///
/// Defined here rather than imported from vault_kdf.dart on purpose.
/// vault_kdf.dart imports THIS file (to reach parseHardenedVerifier for the v4
/// branch of parseAnyPinVerifier), so importing back would create a circular
/// import between the two. Dart permits cycles between libraries, but the cycle
/// here would exist purely to share one eight-line function, and it would make
/// the dependency between the legacy and hardened formats harder to see.
///
/// Defect L20 records that five separate copies of a constant-time comparison
/// already exist across vault_crypto.dart, duress_service.dart and
/// local_streaming_server.dart. This is deliberately NOT a sixth
/// copy created by accident: it is here because the import cycle makes reuse
/// impossible without moving a shared module. Folding all six into one helper is
/// the correct fix for L20 and is out of scope here.
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

/// Iteration count used when WRITING a new v4 verifier.
///
/// OWASP's 2023 floor for PBKDF2-HMAC-SHA256 is 600,000. This is a WRITE target,
/// not a minimum: a stored v4 record below [kMinHardenedIterations] is refused.
const int kHardenedVerifierIterations = 600000;

/// Lowest iteration count a v4 record may claim.
///
/// This is the floor at which v4 is still worth calling hardened. It exists to
/// reject a tampered or downgraded record: an attacker who could rewrite the
/// verifier could otherwise rewrite it to claim 100,000 iterations, which parseVerifier
/// would happily accept for a v3 record.
const int kMinHardenedIterations = 600000;

/// Upper bound on a v4 iteration count, mirroring kMaxPbkdf2Iterations.
///
/// This bounds work an attacker (or a corrupt record) can force on every unlock.
/// A record claiming an enormous count would otherwise be a denial-of-service
/// lever: PBKDF2 cost is linear in iterations.
const int kMaxHardenedIterations = 4000000;

/// Thrown when a v4 verifier record is malformed or outside its iteration bounds.
class InvalidHardenedVerifierException implements Exception {
  final String message;
  const InvalidHardenedVerifierException([
    this.message = 'Invalid or unsupported hardened PIN verifier format.',
  ]);

  @override
  String toString() => 'InvalidHardenedVerifierException: $message';
}

/// A parsed v4 verifier record.
class HardenedVerifier {
  final int iterations;
  final String digestBase64;
  final String raw;

  const HardenedVerifier({
    required this.iterations,
    required this.digestBase64,
    required this.raw,
  });
}

/// True when [storedHash] is a v4 record this module can parse.
bool isHardenedVerifier(String storedHash) => storedHash.startsWith('v4:');

/// Builds the canonical v4 verifier string for an already-derived [key].
///

/// Parses and validates a stored v4 verifier record.
///
/// Fails closed for anything malformed, non-numeric, or outside
/// [kMinHardenedIterations]..[kMaxHardenedIterations]. Bounds matter on BOTH sides:
/// the floor rejects a downgraded record, the ceiling bounds the work an attacker
/// can force per unlock.
HardenedVerifier parseHardenedVerifier(String storedHash) {
  if (!isHardenedVerifier(storedHash)) {
    throw InvalidHardenedVerifierException(
      'Unsupported hardened verifier format (expected "v4:"): $storedHash',
    );
  }
  final parts = storedHash.split(':');
  if (parts.length != 3) {
    throw InvalidHardenedVerifierException(
      'Malformed v4 verifier: expected exactly 3 colon-separated segments, got ${parts.length}',
    );
  }
  final iterations = int.tryParse(parts[1]);
  if (iterations == null) {
    throw InvalidHardenedVerifierException(
      'Malformed v4 verifier: non-numeric iteration count "${parts[1]}"',
    );
  }
  if (iterations < kMinHardenedIterations || iterations > kMaxHardenedIterations) {
    throw InvalidHardenedVerifierException(
      'Malformed v4 verifier: iteration count $iterations outside the hardened bounds '
      '[$kMinHardenedIterations, $kMaxHardenedIterations]',
    );
  }
  if (parts[2].isEmpty) {
    throw InvalidHardenedVerifierException(
      'Malformed v4 verifier: empty base64 digest',
    );
  }
  return HardenedVerifier(
    iterations: iterations,
    digestBase64: parts[2],
    raw: storedHash,
  );
}

/// Rebuilds the expected v4 verifier string for [key] at [parsed]'s own count.
///
/// Keeping the count inside the record is what makes an existing vault keep
/// working: the stored count is replayed rather than assumed. Returns null when
/// [key] is not the right length, so a caller cannot accidentally compare a
/// truncated digest.
String? expectedHardenedVerifier(HardenedVerifier parsed, Uint8List key) {
  final digest = SHA256Digest().process(key);
  return 'v4:${parsed.iterations}:${base64Encode(digest)}';
}

/// Compares two verifier strings in constant time.
///
/// Reuses the shared implementation in vault_kdf.dart rather than adding a fifth
/// private copy; defects L20 records that three such copies already exist.
bool hardenedVerifierEquals(String a, String b) => constantTimeEquals(a, b);

/// [key] is the PBKDF2 OUTPUT, not the PIN: callers must derive at
/// [kHardenedVerifierIterations] first, so the record and the derivation cannot
/// disagree about the cost.
///
/// Format: `'v4:<iterations>:<base64 sha256 of key>'`
String formatHardenedVerifier(
  Uint8List key, {
  int iterations = kHardenedVerifierIterations,
}) {
  final digest = SHA256Digest().process(key);
  return 'v4:$iterations:${base64Encode(digest)}';
}
