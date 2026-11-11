import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/activation_receipt_verifier.dart';
import 'package:pointycastle/export.dart';

BigInt decodeInteger(String value) => BigInt.parse(
  base64Url
      .decode(base64Url.normalize(value))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(),
  radix: 16,
);

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/activation_receipt_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final jwk = fixture['publicKey'] as Map<String, dynamic>;
  final publicKey = RSAPublicKey(
    decodeInteger(jwk['n']),
    decodeInteger(jwk['e']),
  );
  final vectors = fixture['vectors'] as Map<String, dynamic>;
  final code = fixture['code'] as String;
  final nonce = fixture['nonce'] as String;
  final deviceId = fixture['deviceId'] as String;
  final now = DateTime.fromMillisecondsSinceEpoch(
    fixture['now'] * 1000,
    isUtc: true,
  );
  final verifier = ActivationReceiptVerifier(
    trustedKeys: {'test-only-1': publicKey},
    audience: fixture['audience'],
    clock: () => now,
  );

  VerifiedActivationReceipt? verify(Map<String, dynamic> envelope) =>
      verifier.verify(
        envelope,
        licenseCode: code,
        deviceId: deviceId,
        requestNonce: nonce,
      );
  Map<String, dynamic> valid() => Map<String, dynamic>.from(vectors['valid']);

  for (final name in vectors.keys) {
    final accepts = const {
      'valid',
      'whitespace',
      'ancient_lifetime',
      'clock_skew_boundary',
    }.contains(name);
    test('Node-signed vector $name ${accepts ? 'passes' : 'fails closed'}', () {
      expect(
        verify(Map<String, dynamic>.from(vectors[name])),
        accepts ? isNotNull : isNull,
      );
    });
  }

  test('returns only verified entitlement claims', () {
    final receipt = verify(valid())!;
    expect(receipt.keyId, 'test-only-1');
    expect(receipt.licenseType, 1);
    expect(receipt.issuedAt, now);
  });

  for (final field in ['payload', 'signature']) {
    for (final value in [
      null,
      true,
      1,
      '',
      'A',
      '***',
      'AA=',
      'AA+',
      'A' * 10000,
    ]) {
      test(
        'rejects malformed $field ${value.toString().length > 50 ? 'oversized' : value}',
        () {
          expect(verify(valid()..[field] = value), isNull);
        },
      );
    }
    test('rejects changed $field', () {
      final envelope = valid();
      final bytes = base64Url.decode(base64Url.normalize(envelope[field]));
      bytes[bytes.length ~/ 2] ^= 1;
      envelope[field] = base64Url.encode(bytes).replaceAll('=', '');
      expect(verify(envelope), isNull);
    });
    test('rejects padded $field', () {
      expect(verify(valid()..[field] = '${valid()[field]}='), isNull);
    });
  }

  test('rejects unrecognized key and caller-supplied algorithm/key', () {
    expect(verify(valid()..['kid'] = 'unknown'), isNull);
    expect(verify(valid()..['alg'] = 'none'), isNull);
    expect(verify(valid()..['publicKey'] = jwk), isNull);
    expect(verify(valid()..remove('kid')), isNull);
  });
  test('fails closed with no installed public keys', () {
    final empty = ActivationReceiptVerifier(
      trustedKeys: {},
      audience: fixture['audience'],
    );
    expect(
      empty.verify(
        valid(),
        licenseCode: code,
        deviceId: deviceId,
        requestNonce: nonce,
      ),
      isNull,
    );
  });
  test('rejects signature from a different pinned RSA key', () {
    final wrongKey = ActivationReceiptVerifier(
      trustedKeys: {
        'test-only-1': RSAPublicKey(
          publicKey.modulus! - BigInt.two,
          BigInt.from(65537),
        ),
      },
      audience: fixture['audience'],
      clock: () => now,
    );
    expect(
      wrongKey.verify(
        valid(),
        licenseCode: code,
        deviceId: deviceId,
        requestNonce: nonce,
      ),
      isNull,
    );
  });
  test('rejects truncated and extended RSA signatures', () {
    final signature = base64Url.decode(
      base64Url.normalize(valid()['signature']),
    );
    for (final bytes in [
      signature.sublist(1),
      [...signature, 0],
    ]) {
      expect(
        verify(
          valid()..['signature'] = base64Url.encode(bytes).replaceAll('=', ''),
        ),
        isNull,
      );
    }
  });
  test('rejects invalid pinned keys and configuration', () {
    for (final key in [
      RSAPublicKey(BigInt.one << 1023, BigInt.from(65537)),
      RSAPublicKey(publicKey.modulus!, BigInt.from(3)),
    ]) {
      expect(
        () => ActivationReceiptVerifier(
          trustedKeys: {'test': key},
          audience: 'test',
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => ActivationReceiptVerifier(trustedKeys: {}, audience: ''),
      throwsArgumentError,
    );
    expect(
      () => ActivationReceiptVerifier(
        trustedKeys: {'bad key': publicKey},
        audience: 'test',
      ),
      throwsArgumentError,
    );
  });
  test('binds to locally retained request values', () {
    for (final changed in ['device', 'code', 'nonce']) {
      expect(
        verifier.verify(
          valid(),
          licenseCode: changed == 'code' ? 'MIMIC-01AB-CDEF-1234-5679' : code,
          deviceId: changed == 'device' ? 'other-device' : deviceId,
          requestNonce: changed == 'nonce'
              ? base64Url.encode(List.filled(32, 9)).replaceAll('=', '')
              : nonce,
        ),
        isNull,
      );
    }
  });
  test(
    'rejects replay into a later exchange, but has no one-use state itself',
    () {
      expect(verify(valid()), isNotNull);
      expect(verify(valid()), isNotNull);
      expect(
        verifier.verify(
          valid(),
          licenseCode: code,
          deviceId: deviceId,
          requestNonce: base64Url
              .encode(List.filled(32, 10))
              .replaceAll('=', ''),
        ),
        isNull,
      );
    },
  );
  test('rejects invalid local request context', () {
    expect(
      verifier.verify(
        valid(),
        licenseCode: code.toLowerCase(),
        deviceId: deviceId,
        requestNonce: nonce,
      ),
      isNull,
    );
    expect(
      verifier.verify(
        valid(),
        licenseCode: code,
        deviceId: '',
        requestNonce: nonce,
      ),
      isNull,
    );
    expect(
      verifier.verify(
        valid(),
        licenseCode: code,
        deviceId: deviceId,
        requestNonce: 'short',
      ),
      isNull,
    );
  });
}
