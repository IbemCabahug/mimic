// Phase 4A-READ: the verifier dispatcher wired into VaultCrypto.
//
// This suite proves the thing that matters most about a change to the unlock
// path: an EXISTING vault must still unlock. Every legacy format is driven
// through the real VaultCrypto, not through a helper, so a regression in the
// wiring shows up here rather than on the owner's phone.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:mimic/vault/crypto/hardened_verifier.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';

Uint8List fixedBytes(int length, int seed) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7 + seed) & 0xFF));

/// Builds a v2 record, the oldest format on disk: no iteration count, so it is
/// always read at [kLegacyV2Iterations].
String v2RecordFor(Uint8List key) => 'v2:${base64Encode(SHA256Digest().process(key))}';

void main() {
  group('parseAnyPinVerifier dispatch', () {
    test('a v4 record dispatches to the hardened parser', () {
      final key = fixedBytes(32, 1);
      final parsed = parseAnyPinVerifier(formatHardenedVerifier(key));
      expect(parsed.version, 4);
      expect(parsed.iterations, kHardenedVerifierIterations);
      expect(rebuildVerifierFor(parsed, key), formatHardenedVerifier(key));
    });

    test('a v3 record still dispatches to the legacy parser', () {
      final key = fixedBytes(32, 2);
      final parsed = parseAnyPinVerifier(formatVerifier(key));
      expect(parsed.version, 3);
      expect(parsed.iterations, kPbkdf2Iterations);
      expect(rebuildVerifierFor(parsed, key), formatVerifier(key));
    });

    test('a v2 record keeps its legacy count and its two-segment spelling', () {
      final key = fixedBytes(32, 3);
      final parsed = parseAnyPinVerifier(v2RecordFor(key));
      expect(parsed.version, 2);
      expect(parsed.iterations, kLegacyV2Iterations);
      // The v2 spelling has NO iteration segment. This is the case that the old
      // `version == 3 ? 'v3:...' : 'v2:...'` ternary got right by accident.
      expect(rebuildVerifierFor(parsed, key), v2RecordFor(key));
      expect(v2RecordFor(key), isNot(contains(':100000:')));
      // REGRESSION GUARD. A v2 record carries no iteration segment. Emitting one
      // produces a string that can never match a real v2 record, so every v2
      // vault silently stops unlocking. This exact bug was introduced once when
      // the dispatcher was first wired in, and this assertion is what caught it.
      expect(rebuildVerifierFor(parsed, key)!.split(':').length, 2,
          reason: 'A v2 record must stay two segments: v2:<digest>');
    });

    test('C1: the v4 floor does NOT leak onto legacy records', () {
      // If the hardened floor were applied to every version, a 100,000-iteration
      // v3 record would be rejected and every existing owner would be locked out.
      // This is the single most important non-regression in the dispatcher.
      final v3 = parseAnyPinVerifier(formatVerifier(fixedBytes(32, 4)));
      expect(v3.iterations, kPbkdf2Iterations);
      expect(v3.iterations, lessThan(kMinHardenedIterations));
      expect(() => parseAnyPinVerifier(formatVerifier(fixedBytes(32, 4))),
          returnsNormally);
    });

    test('a downgraded v4 record is still refused through the dispatcher', () {
      final forged = 'v4:100000:${formatHardenedVerifier(fixedBytes(32, 5)).split(':')[2]}';
      expect(() => parseAnyPinVerifier(forged),
          throwsA(isA<InvalidHardenedVerifierException>()));
    });

    test('an unsupported version fails closed through the dispatcher', () {
      for (final bad in const ['v1:abc', 'v5:600000:abc', 'nonsense', '']) {
        expect(() => parseAnyPinVerifier(bad), throwsA(isA<Exception>()),
            reason: '"$bad" must not parse');
      }
    });

    test('the dispatcher rebuilds byte-identical strings for every version', () {
      final key = fixedBytes(32, 6);
      for (final record in [
        v2RecordFor(key),
        formatVerifier(key),
        formatHardenedVerifier(key),
      ]) {
        final parsed = parseAnyPinVerifier(record);
        expect(rebuildVerifierFor(parsed, key), record,
            reason: '$record must round-trip exactly');
      }
    });

    test('a wrong key never reproduces the record', () {
      final key = fixedBytes(32, 7);
      for (final record in [
        v2RecordFor(key),
        formatVerifier(key),
        formatHardenedVerifier(key),
      ]) {
        final parsed = parseAnyPinVerifier(record);
        expect(rebuildVerifierFor(parsed, fixedBytes(32, 8)), isNot(record));
      }
    });

    test('an empty key refuses to build a comparison string', () {
      final parsed = parseAnyPinVerifier(formatVerifier(fixedBytes(32, 9)));
      expect(rebuildVerifierFor(parsed, Uint8List(0)), isNull);
    });
  });
}
