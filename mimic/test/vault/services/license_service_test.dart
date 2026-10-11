// test/vault/services/license_service_test.dart

import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/license_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> secureRead(String key) async => _storage[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.unmodifiable(_storage);

  @override
  Future<void> secureWrite(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteFile(String path) async {}

  @override
  bool isWeb() => false;

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => File(path);

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

void main() {
  late FakePlatformService platform;
  late ProStatusService proStatus;
  late LicenseService licenseService;

  setUp(() {
    platform = FakePlatformService();
    proStatus = ProStatusService(platform, billingEnforced: true);
    licenseService = LicenseService(
      platform: platform,
      proStatus: proStatus,
      secretKey: 'test_secret_key_123',
    );
  });

  group('LicenseService Key Generation & Validation', () {
    test('generates key matching MIMIC-XXXX-XXXX-XXXX-XXXX format', () {
      final key = licenseService.generateKey();
      expect(key, matches(RegExp(r'^MIMIC-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$')));
    });

    test('validates newly generated key as valid Lifetime Pro', () {
      final key = licenseService.generateKey(type: LicenseType.lifetimePro);
      final result = licenseService.validateKey(key);

      expect(result.isValid, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.type, equals(LicenseType.lifetimePro));
      expect(result.formattedKey, equals(key));
      expect(result.errorMessage, isNull);
    });

    test('validates Beta Tester key correctly', () {
      final key = licenseService.generateKey(type: LicenseType.betaTester);
      final result = licenseService.validateKey(key);

      expect(result.isValid, isTrue);
      expect(result.type, equals(LicenseType.betaTester));
    });

    test('normalizes lowercase, unhyphenated, and missing MIMIC- prefix', () {
      final originalKey = licenseService.generateKey();
      // Remove MIMIC- and hyphens, convert to lowercase
      final stripped = originalKey.replaceAll('MIMIC-', '').replaceAll('-', '').toLowerCase();

      final result = licenseService.validateKey(stripped);
      expect(result.isValid, isTrue);
      expect(result.formattedKey, equals(originalKey));
    });

    test('rejects tampered characters in key', () {
      final originalKey = licenseService.generateKey();
      // Tamper with the last character
      final lastChar = originalKey[originalKey.length - 1];
      final replacementChar = lastChar == 'A' ? 'B' : 'A';
      final tamperedKey = originalKey.substring(0, originalKey.length - 1) + replacementChar;

      final result = licenseService.validateKey(tamperedKey);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid or unrecognized'));
    });

    test('rejects keys created with a different secret', () {
      final otherService = LicenseService(
        platform: platform,
        proStatus: proStatus,
        secretKey: 'different_secret',
      );
      final foreignKey = otherService.generateKey();

      final result = licenseService.validateKey(foreignKey);
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Invalid or unrecognized'));
    });

    test('rejects invalid lengths and malformed input', () {
      expect(licenseService.validateKey('TOO-SHORT').isValid, isFalse);
      expect(licenseService.validateKey('').isValid, isFalse);
      expect(licenseService.validateKey('MIMIC-ZZZZ-ZZZZ-ZZZZ-ZZZZ').isValid, isFalse);
    });
  });

  group('LicenseService Redemption & Persistence', () {
    test('redeeming valid key grants Pro status in secure storage', () async {
      expect(await proStatus.isPro(), isFalse);

      final key = licenseService.generateKey();
      final redeemResult = await licenseService.redeemKey(key);

      expect(redeemResult.isSuccess, isTrue);
      expect(await proStatus.isPro(), isTrue);

      final licenseInfo = await licenseService.getRedeemedLicense();
      expect(licenseInfo, isNotNull);
      expect(licenseInfo!.formattedKey, equals(key));
      expect(licenseInfo.type, equals(LicenseType.lifetimePro));
    });

    test('redeeming invalid key fails and does not grant Pro', () async {
      expect(await proStatus.isPro(), isFalse);

      final redeemResult = await licenseService.redeemKey('MIMIC-0000-0000-0000-0000');
      expect(redeemResult.isSuccess, isFalse);
      expect(await proStatus.isPro(), isFalse);

      final licenseInfo = await licenseService.getRedeemedLicense();
      expect(licenseInfo, isNull);
    });

    test('online activation grants Pro when device limit is not reached', () async {
      final key = licenseService.generateKey();
      final onlineService = LicenseService(
        platform: platform,
        proStatus: proStatus,
        secretKey: 'test_secret_key_123',
        activationUrl: 'https://example.com/activate',
        httpPoster: (url, body) async => {
          'success': true,
          'message': 'Device registered',
        },
      );

      final result = await onlineService.redeemKey(key);
      expect(result.isSuccess, isTrue);
      expect(await proStatus.isPro(), isTrue);
    });

    test('online activation rejects when server reports device limit reached', () async {
      final key = licenseService.generateKey();
      final onlineService = LicenseService(
        platform: platform,
        proStatus: proStatus,
        secretKey: 'test_secret_key_123',
        activationUrl: 'https://example.com/activate',
        httpPoster: (url, body) async => {
          'success': false,
          'error': 'DEVICE_LIMIT_REACHED',
          'message': 'Maximum device limit reached',
        },
      );

      final result = await onlineService.redeemKey(key);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('maximum device limit (2 devices)'));
      expect(await proStatus.isPro(), isFalse);
    });

    test('online activation alerts when network fails', () async {
      final key = licenseService.generateKey();
      final onlineService = LicenseService(
        platform: platform,
        proStatus: proStatus,
        secretKey: 'test_secret_key_123',
        activationUrl: 'https://example.com/activate',
        httpPoster: (url, body) async => throw Exception('SocketException'),
      );

      final result = await onlineService.redeemKey(key);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('Internet connection is required once'));
      expect(await proStatus.isPro(), isFalse);
    });
  });
}
