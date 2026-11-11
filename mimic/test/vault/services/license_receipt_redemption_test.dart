import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/activation_receipt_verifier.dart';
import 'package:mimic/vault/services/license_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:pointycastle/export.dart';

import 'license_service_test.dart' show FakePlatformService;

class RecordingPlatform extends FakePlatformService {
  final writes = <String>[];
  String? failingKey;

  @override
  Future<void> secureWrite(String key, String value) async {
    writes.add(key);
    if (key == failingKey) throw StateError('test storage failure');
    await super.secureWrite(key, value);
  }
}

BigInt integerFromBase64(String value) => BigInt.parse(
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
  final vectors = fixture['vectors'] as Map<String, dynamic>;
  final code = fixture['code'] as String;
  final nonce = fixture['nonce'] as String;
  final device = fixture['deviceId'] as String;
  final verifier = ActivationReceiptVerifier(
    trustedKeys: {
      'test-only-1': RSAPublicKey(
        integerFromBase64(jwk['n']),
        integerFromBase64(jwk['e']),
      ),
    },
    audience: fixture['audience'],
    clock: () =>
        DateTime.fromMillisecondsSinceEpoch(fixture['now'] * 1000, isUtc: true),
  );
  late RecordingPlatform platform;
  late ProStatusService pro;
  late List<Map<String, dynamic>> requests;
  late Map<String, dynamic> response;

  setUp(() async {
    platform = RecordingPlatform();
    await platform.secureWrite(kStoredLicenseDeviceId, device);
    platform.writes.clear();
    pro = ProStatusService(platform, billingEnforced: true);
    requests = [];
    response = {
      'success': true,
      'receiptVersion': 1,
      'receipt': Map<String, dynamic>.from(vectors['valid']),
    };
  });

  LicenseService service({
    String url = 'https://example.invalid/activate',
    bool configured = true,
    bool fixedNonce = true,
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? poster,
  }) => LicenseService(
    platform: platform,
    proStatus: pro,
    secretKey: '',
    activationUrl: url,
    requireSignedReceipt: true,
    receiptVerifier: configured ? verifier : null,
    nonceGenerator: fixedNonce ? () => nonce : null,
    httpPoster:
        poster ??
        (url, body) async {
          requests.add(Map<String, dynamic>.from(body));
          return response;
        },
  );

  test(
    'redeems a recorded legacy-format code without any client signing secret',
    () async {
      final result = await service().redeemKey(code);
      expect(result.isSuccess, isTrue);
      expect(result.formattedKey, code);
      expect(await pro.isPro(), isTrue);
      expect(requests.single, {
        'action': 'activate',
        'key': code,
        'deviceId': device,
        'receiptVersion': 1,
        'nonce': nonce,
      });
      expect(platform.writes, [
        kStoredActivationReceipt,
        kStoredLicenseKey,
        kStoredLicenseRedeemedAt,
        kStoredLicenseTypeCode,
        kStoredLicenseDeviceId,
        proEntitlementKey,
      ]);
      expect(
        jsonDecode((await platform.secureRead(kStoredActivationReceipt))!),
        vectors['valid'],
      );
      expect((await service().getRedeemedLicense())!.formattedKey, code);
    },
  );

  test(
    'normalizes old customer code input before requesting signed activation',
    () async {
      final input = code
          .replaceAll('MIMIC-', '')
          .replaceAll('-', '')
          .toLowerCase();
      expect((await service().redeemKey(input)).isSuccess, isTrue);
      expect(requests.single['key'], code);
    },
  );

  for (final invalid in [
    '',
    'http://example.invalid/activate',
    'https://user:password@example.invalid/activate',
    'https://example.invalid/#fragment',
  ]) {
    test(
      'rejects unsafe/missing endpoint before activation: $invalid',
      () async {
        expect(
          (await service(url: invalid).redeemKey(code)).isSuccess,
          isFalse,
        );
        expect(requests, isEmpty);
        expect(platform.writes, isEmpty);
        expect(await pro.isPro(), isFalse);
      },
    );
  }
  test(
    'missing verifier never falls back to unsigned or HMAC activation',
    () async {
      expect(
        (await service(configured: false).redeemKey(code)).isSuccess,
        isFalse,
      );
      expect(requests, isEmpty);
      expect(platform.writes, isEmpty);
    },
  );

  for (final input in [
    '',
    'too-short',
    'MIMIC-03AB-CDEF-1234-5678',
    'x' * 129,
  ]) {
    test(
      'malformed/unsupported input does not request activation: ${input.length}',
      () async {
        expect((await service().redeemKey(input)).isSuccess, isFalse);
        expect(requests, isEmpty);
        expect(platform.writes, isEmpty);
      },
    );
  }

  for (final invalid in <Map<String, dynamic>>[
    {'success': true},
    {'success': true, 'receiptVersion': '1'},
    {'success': true, 'receiptVersion': 1, 'receipt': null},
    {'success': true, 'receiptVersion': 1, 'receipt': []},
    {'success': 'true', 'receiptVersion': 1},
    {'success': false, 'message': 'PRIVATE backend details'},
  ]) {
    test(
      'unsigned or malformed success cannot grant Pro: ${jsonEncode(invalid)}',
      () async {
        response = invalid;
        final result = await service().redeemKey(code);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, isNot(contains('PRIVATE')));
        expect(platform.writes, isEmpty);
        expect(await pro.isPro(), isFalse);
      },
    );
  }

  for (final name in vectors.keys.where(
    (name) => !const {
      'valid',
      'whitespace',
      'ancient_lifetime',
      'clock_skew_boundary',
    }.contains(name),
  )) {
    test(
      'invalid signed claims $name cannot grant Pro or persist metadata',
      () async {
        response['receipt'] = Map<String, dynamic>.from(vectors[name]);
        expect((await service().redeemKey(code)).isSuccess, isFalse);
        expect(platform.writes, isEmpty);
        expect(await pro.isPro(), isFalse);
      },
    );
  }

  test(
    'device limit response preserves existing error UX without storing receipt',
    () async {
      response = {'success': false, 'error': 'DEVICE_LIMIT_REACHED'};
      expect(
        (await service().redeemKey(code)).errorMessage,
        contains('maximum device limit'),
      );
      expect(platform.writes, isEmpty);
    },
  );

  test(
    'network failure and raw exceptions fail closed without exposing details',
    () async {
      final offline = await service(
        poster: (_, _) async => throw const SocketException('private address'),
      ).redeemKey(code);
      expect(offline.errorMessage, contains('Internet connection'));
      final failed = await service(
        poster: (_, _) async => throw StateError('PRIVATE details'),
      ).redeemKey(code);
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, isNot(contains('PRIVATE')));
      expect(platform.writes, isEmpty);
    },
  );

  test(
    'timeout reports a retryable error without storing receipt data',
    () async {
      final result = await service(
        poster: (_, _) async => throw TimeoutException('private endpoint'),
      ).redeemKey(code);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('timed out'));
      expect(result.errorMessage, isNot(contains('private endpoint')));
      expect(platform.writes, isEmpty);
    },
  );

  test(
    'invalid nonce injection fails before a request or entitlement write',
    () async {
      final client = LicenseService(
        platform: platform,
        proStatus: pro,
        secretKey: '',
        activationUrl: 'https://example.invalid/activate',
        requireSignedReceipt: true,
        receiptVerifier: verifier,
        nonceGenerator: () => 'not-a-secure-nonce',
        httpPoster: (_, body) async {
          requests.add(body);
          return response;
        },
      );
      expect((await client.redeemKey(code)).isSuccess, isFalse);
      expect(requests, isEmpty);
      expect(platform.writes, isEmpty);
    },
  );

  test(
    'receipt for another device fails without touching existing storage',
    () async {
      await platform.secureWrite(kStoredLicenseDeviceId, 'different-device');
      platform.writes.clear();
      expect((await service().redeemKey(code)).isSuccess, isFalse);
      expect(platform.writes, isEmpty);
      expect(await pro.isPro(), isFalse);
    },
  );

  for (final failureKey in [
    kStoredActivationReceipt,
    kStoredLicenseKey,
    kStoredLicenseRedeemedAt,
    kStoredLicenseTypeCode,
    kStoredLicenseDeviceId,
    proEntitlementKey,
  ]) {
    for (final alreadyPro in [false, true]) {
      test(
        'storage failure at $failureKey preserves prior entitlement=$alreadyPro',
        () async {
          if (alreadyPro) await pro.grantPro();
          platform.writes.clear();
          platform.failingKey = failureKey;
          expect((await service().redeemKey(code)).isSuccess, isFalse);
          expect(await pro.isPro(), alreadyPro);
          expect(platform.writes.last, failureKey);
          platform.failingKey = null;
          expect((await service().redeemKey(code)).isSuccess, isTrue);
          expect(await pro.isPro(), isTrue);
        },
      );
    }
  }

  test(
    'new attempts use fresh secure nonces and reject earlier exchange receipts',
    () async {
      final client = service(fixedNonce: false);
      expect((await client.redeemKey(code)).isSuccess, isFalse);
      expect((await client.redeemKey(code)).isSuccess, isFalse);
      final first = requests[0]['nonce'] as String;
      final second = requests[1]['nonce'] as String;
      expect(first, isNot(second));
      expect(base64Url.decode(base64Url.normalize(first)), hasLength(32));
      expect(base64Url.decode(base64Url.normalize(second)), hasLength(32));
      expect(platform.writes, isEmpty);
    },
  );

  test(
    'signed activation stays offline after restart with no revalidation',
    () async {
      expect((await service().redeemKey(code)).isSuccess, isTrue);
      final restarted = ProStatusService(platform, billingEnforced: true);
      final client = service(
        poster: (_, _) async => throw const SocketException('offline'),
      );
      expect(await restarted.isPro(), isTrue);
      expect((await client.getRedeemedLicense())!.formattedKey, code);
      expect(requests, hasLength(1));
    },
  );

  test(
    'legacy/Play offline entitlement survives missing configuration and failed activation',
    () async {
      await pro.grantPro();
      await platform.secureWrite(kStoredLicenseKey, 'existing-customer-code');
      final before = await platform.secureReadAll();
      expect(
        (await service(configured: false).redeemKey(code)).isSuccess,
        isFalse,
      );
      response = {'success': true};
      expect((await service().redeemKey(code)).isSuccess, isFalse);
      expect(await platform.secureReadAll(), before);
      expect(
        await ProStatusService(platform, billingEnforced: true).isPro(),
        isTrue,
      );
    },
  );
}
