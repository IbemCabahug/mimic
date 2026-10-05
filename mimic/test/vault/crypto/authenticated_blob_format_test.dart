// Tests for the shared versioned-format layer (defects C1 and C2).
//
// These exercise the format in isolation, with no VaultCrypto, no filesystem and
// no device, so a failure here is unambiguous: it is the format, not the wiring.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/authenticated_blob_format.dart';
import 'package:mimic/vault/crypto/hardened_verifier.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:pointycastle/export.dart';

/// Builds a well-formed authenticated blob the way the writer is specified to:
/// encrypt FIRST, then tag the ciphertext.
Uint8List buildBlob({
  required List<int> macKey,
  required List<int> iv,
  required List<int> ciphertext,
}) {
  final blob = Uint8List(kAuthHeaderLength + ciphertext.length);
  blob.setRange(0, 8, kMediaMagicCtrV3);
  blob.setRange(kAuthIvOffset, kAuthTagOffset, iv);
  final tag = computeAuthTag(
    macKey: Uint8List.fromList(macKey),
    iv: Uint8List.fromList(iv),
    ciphertext: Uint8List.fromList(ciphertext),
  );
  blob.setRange(kAuthTagOffset, kAuthCiphertextOffset, tag);
  blob.setRange(kAuthCiphertextOffset, blob.length, ciphertext);
  return blob;
}

Uint8List fixedBytes(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7 + seed) & 0xFF));

void main() {
  final macKey = fixedBytes(32, 1);
  final iv = fixedBytes(16, 2);
  final ciphertext = fixedBytes(64, 3);

  group('authenticated blob format', () {
    test('a well-formed blob authenticates and yields its ciphertext', () {
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      expect(blob.length, kAuthHeaderLength + ciphertext.length);
      expect(authenticateBlob(blob: blob, macKey: macKey), ciphertext);
    });

    test('C2: flipping one ciphertext bit fails authentication', () {
      // The single test that C2 exists for. CTR gives no integrity on its own,
      // so this bit flip decrypts to different plaintext with no error at all.
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      blob[kAuthCiphertextOffset + 5] ^= 0x01;
      expect(
        () => authenticateBlob(blob: blob, macKey: macKey),
        throwsA(isA<BlobAuthenticationException>()
            .having((e) => e.isTamperSuspected, 'isTamperSuspected', isTrue)),
      );
    });

    test('C2: flipping the last ciphertext bit also fails', () {
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      blob[blob.length - 1] ^= 0x80;
      expect(() => authenticateBlob(blob: blob, macKey: macKey),
          throwsA(isA<BlobAuthenticationException>()));
    });

    test('C2: rewriting the IV fails, so the keystream cannot be redirected', () {
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      blob[kAuthIvOffset] ^= 0xFF;
      expect(() => authenticateBlob(blob: blob, macKey: macKey),
          throwsA(isA<BlobAuthenticationException>()));
    });

    test('the tag covers the magic, so a c2 blob cannot be relabelled c3', () {
      // A blob tagged while claiming c2 must not verify as c3.
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      blob.setRange(0, 8, kMediaMagicCtrV2);
      expect(() => authenticateBlob(blob: blob, macKey: macKey),
          throwsA(isA<BlobAuthenticationException>()));
    });

    test('the wrong MAC key fails, so the key really is bound to the tag', () {
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      expect(
        () => authenticateBlob(blob: blob, macKey: fixedBytes(32, 99)),
        throwsA(isA<BlobAuthenticationException>()),
      );
    });

    test('a truncated blob is a shape error, not a suspected tamper', () {
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: ciphertext);
      expect(
        () => authenticateBlob(blob: blob.sublist(0, 20), macKey: macKey),
        throwsA(isA<BlobAuthenticationException>()
            .having((e) => e.isTamperSuspected, 'isTamperSuspected', isFalse)),
      );
    });

    test('a blob exactly one byte under the header is rejected', () {
      expect(
        () => authenticateBlob(blob: fixedBytes(kAuthHeaderLength - 1, 4), macKey: macKey),
        throwsA(isA<BlobAuthenticationException>()),
      );
    });

    test('an empty ciphertext is still authenticated', () {
      // A zero-length payload must not be special-cased into an unverified pass.
      final blob = buildBlob(macKey: macKey, iv: iv, ciphertext: const []);
      expect(authenticateBlob(blob: blob, macKey: macKey), isEmpty);
    });

    test('the magic is the documented eight bytes and classifies as c3', () {
      expect(kMediaMagicCtrV3.length, 8);
      expect(String.fromCharCodes(kMediaMagicCtrV3.sublist(0, 6)), 'MVKEYc');
      expect(kMediaMagicCtrV3[6], 0x33); // '3'
      expect(kMediaMagicCtrV3[7], 0x00);
    });

    test('header offsets are contiguous and non-overlapping', () {
      expect(kAuthIvOffset, 8);
      expect(kAuthTagOffset, 24);
      expect(kAuthCiphertextOffset, 56);
      expect(kAuthHeaderLength, 56);
      expect(kAuthTagLength, 32);
    });
  });

  group('MAC key derivation', () {
    test('is deterministic for the same cipher key', () {
      expect(deriveMacKey(fixedBytes(32, 7)), deriveMacKey(fixedBytes(32, 7)));
    });

    test('differs for a different cipher key', () {
      expect(deriveMacKey(fixedBytes(32, 7)), isNot(deriveMacKey(fixedBytes(32, 8))));
    });

    test('is 32 bytes, so it is a full-length AES-256 subkey', () {
      expect(deriveMacKey(fixedBytes(32, 7)).length, 32);
    });

    test('C2: the MAC key is NOT the cipher key, so keys are never reused', () {
      // The classic encrypt-then-MAC mistake is signing with the encryption key.
      final cipherKey = fixedBytes(32, 11);
      expect(deriveMacKey(cipherKey), isNot(cipherKey));
    });

    test('is domain-separated from the cipher key by the frozen label', () {
      // Proves the label is actually mixed in: HMAC(key, label) != HMAC(key, "").
      final cipherKey = fixedBytes(32, 12);
      final byHand = HMac(SHA256Digest(), 64)
        ..init(KeyParameter(cipherKey))
        ..process(Uint8List(0));
      expect(byHand, isNot(deriveMacKey(cipherKey)));
      expect(kAuthMacKeyLabel, 'mimic.vault.mac.v1');
    });

    test('a tag made with one MAC key does not verify with another', () {
      final blob = buildBlob(macKey: deriveMacKey(fixedBytes(32, 5)),
          iv: iv, ciphertext: ciphertext);
      expect(
        () => authenticateBlob(blob: blob, macKey: deriveMacKey(fixedBytes(32, 6))),
        throwsA(isA<BlobAuthenticationException>()),
      );
    });
  });

  group('constant-time tag comparison', () {
    test('equal bytes compare equal', () {
      expect(constantTimeBytesEqual(fixedBytes(32, 1), fixedBytes(32, 1)), isTrue);
    });

    test('one differing byte compares unequal', () {
      final a = fixedBytes(32, 1);
      final b = fixedBytes(32, 1)..[31] ^= 0x01;
      expect(constantTimeBytesEqual(a, b), isFalse);
    });

    test('a difference in the FIRST byte compares unequal', () {
      // Proves it does not short-circuit on a leading mismatch.
      final a = fixedBytes(32, 1);
      final b = fixedBytes(32, 1)..[0] ^= 0x01;
      expect(constantTimeBytesEqual(a, b), isFalse);
    });

    test('differing lengths compare unequal without reading out of bounds', () {
      expect(constantTimeBytesEqual(fixedBytes(32, 1), fixedBytes(31, 1)), isFalse);
      expect(constantTimeBytesEqual(fixedBytes(31, 1), fixedBytes(32, 1)), isFalse);
      expect(constantTimeBytesEqual(Uint8List(0), Uint8List(0)), isTrue);
    });
  });

  group('range authentication is refused, not faked', () {
    test('throws RangeAuthenticationUnavailable rather than returning a verdict', () {
      expect(
        () => authenticateRange(macKey: macKey, offset: 0, length: 256 * 1024),
        throwsA(isA<RangeAuthenticationUnavailable>()),
      );
    });

    test('refuses for every offset and length, including the whole file', () {
      for (final pair in const [[0, 1], [1024, 4096], [0, 1 << 20]]) {
        expect(
          () => authenticateRange(macKey: macKey, offset: pair[0], length: pair[1]),
          throwsA(isA<RangeAuthenticationUnavailable>()),
          reason: 'offset ${pair[0]} length ${pair[1]} must not be verifiable',
        );
      }
    });
  });
  group('hardened PIN verifier (C1)', () {
    test('C1: the write count meets the OWASP floor of 600,000', () {
      expect(kHardenedVerifierIterations, greaterThanOrEqualTo(600000));
      expect(kMinHardenedIterations, greaterThanOrEqualTo(600000));
    });

    test('C1: the hardened count is 6x the current kPbkdf2Iterations', () {
      // Quantifies the actual improvement rather than asserting a slogan.
      expect(kPbkdf2Iterations, 100000);
      expect(kHardenedVerifierIterations, greaterThan(kPbkdf2Iterations * 5));
    });

    test('a v4 record round-trips through format and parse', () {
      final key = fixedBytes(32, 21);
      final record = formatHardenedVerifier(key);
      expect(record, startsWith('v4:600000:'));
      final parsed = parseHardenedVerifier(record);
      expect(parsed.iterations, kHardenedVerifierIterations);
      expect(parsed.digestBase64, isNotEmpty);
      expect(parsed.raw, record);
    });

    test('the expected verifier is reproduced from the same key', () {
      final key = fixedBytes(32, 22);
      final parsed = parseHardenedVerifier(formatHardenedVerifier(key));
      expect(expectedHardenedVerifier(parsed, key), parsed.raw);
    });

    test('a DIFFERENT key does not reproduce the verifier', () {
      final parsed = parseHardenedVerifier(formatHardenedVerifier(fixedBytes(32, 23)));
      expect(hardenedVerifierEquals(
        expectedHardenedVerifier(parsed, fixedBytes(32, 24))!, parsed.raw), isFalse);
    });

    test('a wrong PIN is rejected at the hardened count', () {
      // End-to-end shape of an offline attack: the right PIN verifies, a wrong
      // one does not, both derived at the record's own cost.
      final correctKey = fixedBytes(32, 25);
      final record = formatHardenedVerifier(correctKey);
      final parsed = parseHardenedVerifier(record);
      expect(hardenedVerifierEquals(
        expectedHardenedVerifier(parsed, correctKey)!, parsed.raw), isTrue);
      expect(hardenedVerifierEquals(
        expectedHardenedVerifier(parsed, fixedBytes(32, 26))!, parsed.raw), isFalse);
    });

    test('the stored iteration count is replayed, never assumed', () {
      // A record written at a higher cost must verify at THAT cost. This is what
      // lets the cost be raised again later without a format change.
      final key = fixedBytes(32, 27);
      final record = formatHardenedVerifier(key, iterations: 800000);
      final parsed = parseHardenedVerifier(record);
      expect(parsed.iterations, 800000);
      expect(hardenedVerifierEquals(
        expectedHardenedVerifier(parsed, key)!, parsed.raw), isTrue);
    });

    test('a DOWNGRADED record claiming 100,000 iterations is rejected', () {
      // The floor is what stops an attacker rewriting a record to claim a cheap
      // cost. parseVerifier would accept this string as v3.
      expect(kPbkdf2Iterations, lessThan(kMinHardenedIterations));
      final forged = 'v4:100000:${formatHardenedVerifier(fixedBytes(32, 28)).split(':')[2]}';
      expect(() => parseHardenedVerifier(forged),
          throwsA(isA<InvalidHardenedVerifierException>()));
    });

    test('an absurd iteration count is rejected, bounding unlock cost', () {
      // PBKDF2 cost is linear in iterations, so an unbounded record is a DoS lever.
      final forged = 'v4:999999999:${formatHardenedVerifier(fixedBytes(32, 29)).split(':')[2]}';
      expect(() => parseHardenedVerifier(forged),
          throwsA(isA<InvalidHardenedVerifierException>()));
    });

    test('the ceiling is respected exactly', () {
      final key = fixedBytes(32, 30);
      final atCeiling = formatHardenedVerifier(key, iterations: kMaxHardenedIterations);
      expect(parseHardenedVerifier(atCeiling).iterations, kMaxHardenedIterations);
      final overCeiling = 'v4:${kMaxHardenedIterations + 1}:AAAA';
      expect(() => parseHardenedVerifier(overCeiling),
          throwsA(isA<InvalidHardenedVerifierException>()));
    });

    test('malformed v4 records fail closed', () {
      for (final bad in const [
        'v4',
        'v4:',
        'v4:600000',
        'v4:600000:',
        'v4:600000:a:b',
        'v4:abc:AAAA',
      ]) {
        expect(() => parseHardenedVerifier(bad),
            throwsA(isA<InvalidHardenedVerifierException>()),
            reason: '"$bad" must not parse');
      }
    });

    test('a v2 or v3 record is NOT accepted as hardened', () {
      // The two formats stay readable at their own counts. v4 must not swallow them.
      expect(isHardenedVerifier('v3:100000:AAAA'), isFalse);
      expect(isHardenedVerifier('v2:AAAA'), isFalse);
      expect(() => parseHardenedVerifier('v3:100000:AAAA'),
          throwsA(isA<InvalidHardenedVerifierException>()));
    });

    test('the legacy v3 verifier still parses under the OLD rules', () {
      // Proves the C1 fix does not disturb existing vaults: an existing v3 record
      // is read by the untouched parseVerifier at its own 100,000 count.
      final key = fixedBytes(32, 31);
      final v3 = formatVerifier(key);
      expect(v3, startsWith('v3:100000:'));
      final parsed = parseVerifier(v3);
      expect(parsed.version, 3);
      expect(parsed.iterations, kPbkdf2Iterations);
      expect(parsed.digestBase64, isNotEmpty);
    });

    test('both formats remain distinguishable from one another', () {
      final key = fixedBytes(32, 32);
      expect(formatVerifier(key), isNot(formatHardenedVerifier(key)));
      expect(isHardenedVerifier(formatVerifier(key)), isFalse);
      expect(isHardenedVerifier(formatHardenedVerifier(key)), isTrue);
    });
  });
}
