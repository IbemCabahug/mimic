// lib/vault/crypto/authenticated_blob_format.dart
//
// The shared versioned-format layer for defects C1 and C2.
//
// WHY THIS FILE EXISTS
// -------------------
// C2 (no ciphertext authentication): every media blob is AES-CTR or AES-CBC with
// no MAC anywhere. CTR is a stream cipher, so flipping bit N of ciphertext flips
// bit N of the recovered plaintext. An attacker with write access to a blob can
// alter what the user sees without knowing the key, and nothing detects it.
//
// C1 (offline PIN brute-force): the stored PIN verifier is a bare SHA-256 of the
// derived key at 100,000 PBKDF2 iterations (see vault_kdf.dart). Extraction of
// secure storage yields salt + verifier, after which every 4-8 digit PIN can be
// tried offline with no lockout, no Keystore and no rate limit.
//
// WHAT THIS FILE DOES NOT DO
// -------------------------
// It defines formats and verifies them. It does not encrypt, decrypt, or touch
// the filesystem, and it is not yet wired into VaultCrypto. Nothing here runs
// until an explicit integration step imports it, so adding it cannot regress a
// live vault. That is deliberate: a crypto format change must be reviewable and
// testable before any byte of anyone's data depends on it.
//
// FORMAT: "MVKEYc3\0" - AES-CTR ciphertext with an HMAC-SHA256 tag
// ----------------------------------------------------------------
//   offset  size  field
//   0       8     magic kMediaMagicCtrV3 ("MVKEYc3\0")
//   8       16    IV / initial CTR counter block
//   24      32    HMAC-SHA256 tag over magic || IV || ciphertext
//   56      n     AES-CTR ciphertext (same keystream as c2)
//
// The MAC covers the magic as well as the payload, so a c2 blob cannot be relabelled
// as c3 and still verify.
//
// The MAC key is DERIVED, never reused: macKey = HMAC-SHA256(cipherKey,
// "mimic.vault.mac.v1"). Reusing the encryption key as the MAC key is the classic
// encrypt-then-MAC mistake; deriving a distinct subkey by HMAC is the standard
// mitigation and costs one extra SHA-256 per unlock.
//
// TRUNCATION: the tag is kept at the full 32 bytes. A truncated tag saves 16 bytes
// per blob and buys nothing here, because the threat model in PROJECT_STATUS.md
// section 4 is an attacker with physical access to the device.
//
// RANGE READS: a whole-blob tag cannot authenticate a partial read. Verifying a
// 256 KB video range would require the entire ciphertext, which is exactly the cost
// the streaming server was built to avoid (M13). [authenticateRange] states this
// honestly instead of pretending partial authentication is possible: callers get
// [RangeAuthenticationUnavailable] and decide. This limitation is recorded rather
// than hidden because a half-verified video range is worse than an honestly
// unverified one.

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Thrown when a blob claims to be authenticated but its tag does not verify.
///
/// This is a SECURITY event, not a damaged file. The distinction matters: a
/// corrupted blob is a hardware or partial-write problem and may be recoverable
/// from a backup, whereas a failed tag means the bytes were altered by someone who
/// could not produce a valid tag. It is deliberately a separate type so the UI
/// cannot collapse it into the generic "file is damaged" message, which would
/// understate a possible tamper.
class BlobAuthenticationException implements Exception {
  final String message;

  /// When true the blob failed because the tag did not match the bytes.
  /// When false it failed because the header was truncated or malformed.
  final bool isTamperSuspected;

  const BlobAuthenticationException(
    this.message, {
    this.isTamperSuspected = true,
  });

  @override
  String toString() => 'BlobAuthenticationException: $message';
}

/// Thrown when a caller asks to authenticate a partial read of an authenticated
/// blob, which a whole-blob tag structurally cannot support.
///
/// See the RANGE READS note at the top of this file. This is raised instead of
/// returning a "verified" answer, because a range that was never checked must
/// never be presented as authenticated.

/// Derives the MAC key from [cipherKey] using HMAC-SHA256 over a frozen label.
///
/// Returns a 32-byte subkey that is cryptographically independent of [cipherKey]
/// even though it is deterministically derived from it. Callers must treat the
/// result as a secret and zero it when done.
Uint8List deriveMacKey(Uint8List cipherKey) {
  final hmac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(Uint8List.fromList(cipherKey)));
  return hmac.process(Uint8List.fromList(kAuthMacKeyLabel.codeUnits));
}

/// Computes the HMAC-SHA256 tag over the magic, the IV and the ciphertext.
///
/// This is encrypt-then-MAC: the caller must encrypt FIRST and compute the tag
/// over the resulting ciphertext. Computing it over the plaintext would be
/// MAC-then-encrypt and would leak plaintext equality.
Uint8List computeAuthTag({
  required Uint8List macKey,
  required Uint8List iv,
  required Uint8List ciphertext,
}) {
  final hmac = HMac(SHA256Digest(), 64)
    ..init(KeyParameter(macKey));

  // Magic and IV are authenticated so that a blob cannot be relabelled from c2
  // to c3, nor have its IV rewritten to redirect the keystream.
  hmac.update(Uint8List.fromList(kMediaMagicCtrV3), 0, kMediaMagicCtrV3.length);
  hmac.update(iv, 0, iv.length);
  hmac.update(ciphertext, 0, ciphertext.length);

  final out = Uint8List(kAuthTagLength);
  hmac.doFinal(out, 0);
  return out;
}

/// Compares two byte strings in time that does not depend on their contents.
///
/// A tag comparison that returns early on the first differing byte leaks, through
/// response timing, how many leading bytes an attacker guessed correctly. This
/// walks the full length and accumulates differences, so the time depends only on
/// the LENGTH, which is not secret (the tag is always 32 bytes).
///
/// Length is compared first and returns early. That is safe here precisely
/// because every tag is exactly [kAuthTagLength]; the length is fixed by the

/// The parsed, not-yet-verified pieces of an authenticated blob header.
class AuthenticatedBlobHeader {
  final Uint8List iv;
  final Uint8List tag;
  final Uint8List ciphertext;

  const AuthenticatedBlobHeader({
    required this.iv,
    required this.tag,
    required this.ciphertext,
  });
}

/// Splits [blob] into IV, tag and ciphertext WITHOUT verifying the tag.
///
/// Use this only when you need the pieces before verification (for example to
/// decrypt and then verify, or to inspect a blob's shape). Do NOT decrypt
/// attacker-supplied bytes before authenticating them unless you accept the
/// malleability you are inviting; prefer [authenticateBlob], which verifies
/// before returning anything.
///
/// Throws [BlobAuthenticationException] with `isTamperSuspected: false` if the
/// blob is too short to hold a full header, because that is a shape problem
/// rather than a failed comparison.
AuthenticatedBlobHeader parseAuthHeader(Uint8List blob) {
  if (blob.length < kAuthHeaderLength) {
    throw const BlobAuthenticationException(
      'Authenticated blob is shorter than its header.',
      isTamperSuspected: false,
    );
  }
  final magic = blob.sublist(0, kAuthIvOffset);
  for (var i = 0; i < magic.length; i++) {
    if (magic[i] != kMediaMagicCtrV3[i]) {
      throw const BlobAuthenticationException(
        'Blob does not begin with the authenticated magic header.',
        isTamperSuspected: false,
      );
    }
  }
  return AuthenticatedBlobHeader(
    iv: blob.sublist(kAuthIvOffset, kAuthTagOffset),
    tag: blob.sublist(kAuthTagOffset, kAuthCiphertextOffset),
    ciphertext: blob.sublist(kAuthCiphertextOffset),
  );
}

/// Verifies [blob]'s tag against [macKey] and returns the ciphertext only if it
/// is authentic.
///
/// Throws [BlobAuthenticationException] if the header is malformed or the tag does
/// not match. Returning the ciphertext is the ONLY success path, so a caller
/// cannot accidentally decrypt an unauthenticated blob by ignoring a boolean.
///
/// The tag is checked BEFORE the ciphertext is handed back, which is the whole
/// point of encrypt-then-MAC: unauthenticated plaintext must never be produced.
Uint8List authenticateBlob({
  required Uint8List blob,
  required Uint8List macKey,
}) {
  final header = parseAuthHeader(blob);
  final expected = computeAuthTag(
    macKey: macKey,
    iv: header.iv,
    ciphertext: header.ciphertext,
  );
  if (!constantTimeBytesEqual(header.tag, expected)) {
    throw const BlobAuthenticationException(
      'Authentication tag does not match the blob contents.',
    );
  }
  return header.ciphertext;
}

/// Always throws [RangeAuthenticationUnavailable].
///
/// Present so that a caller reaching for range authentication has to handle the
/// limitation explicitly and cannot get a misleading "verified" answer. See the
/// RANGE READS note at the top of this file.
Never authenticateRange({
  required Uint8List macKey,
  required int offset,
  required int length,
}) {
  throw const RangeAuthenticationUnavailable();
}

/// format, not chosen by an attacker.
bool constantTimeBytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class RangeAuthenticationUnavailable implements Exception {
  final String message;
  const RangeAuthenticationUnavailable([
    this.message = 'A partial read of an authenticated blob cannot be verified; '
        'authenticate the whole blob instead.',
  ]);

  @override
  String toString() => 'RangeAuthenticationUnavailable: $message';
}


/// New authenticated-CTR media magic: "MVKEYc3\0" (AES-CTR + HMAC-SHA256 tag).
///
/// Byte layout is identical to c2 except that a 32-byte tag sits between the IV
/// and the ciphertext, and the tag covers the magic and IV as well.
const List<int> kMediaMagicCtrV3 = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x63, 0x33, 0x00];

/// Length of the authenticated blob header: magic + IV + tag.
const int kAuthHeaderLength = 8 + 16 + 32;

/// Length of the HMAC-SHA256 tag in bytes. Full 32 bytes, never truncated.
const int kAuthTagLength = 32;

/// Offset of the IV within an authenticated blob (immediately after the magic).
const int kAuthIvOffset = 8;

/// Offset of the tag within an authenticated blob (immediately after the IV).
const int kAuthTagOffset = 8 + 16;

/// Offset of the ciphertext within an authenticated blob.
const int kAuthCiphertextOffset = kAuthHeaderLength;

/// Domain-separation label for deriving the MAC key from the cipher key.
///
/// This string is part of the on-disk contract: changing it makes every existing
/// c3 blob unverifiable, exactly like changing a PBKDF2 iteration count. It is
/// frozen for the life of the format.
const String kAuthMacKeyLabel = 'mimic.vault.mac.v1';
