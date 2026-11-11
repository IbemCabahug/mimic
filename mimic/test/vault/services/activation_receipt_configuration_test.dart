import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/activation_receipt_configuration.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/activation_receipt_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final n = fixture['publicKey']['n'] as String;
  ActivationReceiptConfiguration config({
    bool enabled = true,
    bool staging = true,
    String kid = 'test-only-1',
    String? modulus,
  }) => ActivationReceiptConfiguration(
    enabled: enabled,
    staging: staging,
    keyId: kid,
    publicModulus: modulus ?? n,
  );

  test('valid staging public config constructs a staging-only verifier', () {
    final verifier = config().createVerifier();
    expect(verifier, isNotNull);
    expect(verifier!.audience, 'com.ibem.mimic.staging:activation');
  });
  test(
    'disabled flag and production identity cannot enable staging verifier',
    () {
      expect(config(enabled: false).createVerifier(), isNull);
      expect(config(staging: false).createVerifier(), isNull);
      expect(
        config(staging: false).enabled,
        isTrue,
        reason: 'A bad opt-in must fail closed, not fall back to legacy',
      );
    },
  );
  test('environment defaults preserve legacy configuration', () {
    const defaults = ActivationReceiptConfiguration.fromEnvironment();
    expect(defaults.enabled, isFalse);
    expect(defaults.createVerifier(), isNull);
  });
  for (final invalid in ['', 'bad key', 'a' * 33]) {
    test('rejects invalid pinned key ID length=${invalid.length}', () {
      expect(config(kid: invalid).createVerifier(), isNull);
    });
  }
  for (final invalid in [
    '',
    'PRIVATE KEY',
    '$n=',
    '***',
    'a' * 684,
    base64Url.encode(List.filled(128, 255)).replaceAll('=', ''),
    base64Url.encode([0, ...List.filled(255, 255)]).replaceAll('=', ''),
    base64Url.encode([...List.filled(255, 255), 254]).replaceAll('=', ''),
  ]) {
    test(
      'rejects malformed/small/noncanonical modulus length=${invalid.length}',
      () {
        expect(config(modulus: invalid).createVerifier(), isNull);
      },
    );
  }
  test('accepts configured 3072/4096-bit public modulus sizes', () {
    for (final size in [384, 512]) {
      final modulus = base64Url
          .encode(List.filled(size, 255))
          .replaceAll('=', '');
      expect(config(modulus: modulus).createVerifier(), isNotNull);
    }
  });
}
