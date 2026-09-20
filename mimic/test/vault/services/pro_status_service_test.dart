// test/vault/services/pro_status_service_test.dart
//
// Phase 1 entitlement tests. The service takes a PlatformService, so
// these run against the same in-memory fake shape the crypto tests use —
// no Play billing, no device, no network.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

/// Minimal in-memory PlatformService: secure storage only, files unused.
class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);

  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List?> readEncryptedFile(String path) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteFile(String path) async => throw UnimplementedError();

  @override
  Future<File> resolveVaultFile(String path) async =>
      throw UnimplementedError();
}

void main() {
  // Billing-era matrix: billingEnforced: true pins the behaviour that
  // activates when kBillingEnforced flips to true in Phase 2 — the stored
  // entitlement decides, exactly as the Play wiring will require.
  test('billing era: fresh install is free (missing key)', () async {
    final service = ProStatusService(
      FakePlatformService(),
      billingEnforced: true,
    );
    expect(await service.isPro(), isFalse);
  });

  test('billing era: grant then revoke round-trips through secure storage',
      () async {
    final platform = FakePlatformService();
    final service = ProStatusService(platform, billingEnforced: true);
    await service.grantPro();
    expect(platform.store[proEntitlementKey], proEntitlementValue);
    expect(await service.isPro(), isTrue);
    await service.revokePro();
    expect(await service.isPro(), isFalse);
  });

  test('billing era: unknown stored value answers free, never Pro',
      () async {
    final platform = FakePlatformService();
    platform.store[proEntitlementKey] = 'Pro';
    expect(
      await ProStatusService(platform, billingEnforced: true).isPro(),
      isFalse,
    );
  });

  test('billing era: empty stored value answers free', () async {
    final platform = FakePlatformService();
    platform.store[proEntitlementKey] = '';
    expect(
      await ProStatusService(platform, billingEnforced: true).isPro(),
      isFalse,
    );
  });

  test('billing era: storage read error answers free instead of throwing',
      () async {
    final service = ProStatusService(
      _ThrowingPlatformService(),
      billingEnforced: true,
    );
    expect(await service.isPro(), isFalse);
  });

  test('billing era: revoke with failing delete still answers free',
      () async {
    final platform = _FailingDeletePlatformService();
    platform.store[proEntitlementKey] = proEntitlementValue;
    final service = ProStatusService(platform, billingEnforced: true);
    await service.revokePro();
    expect(await service.isPro(), isFalse);
  });

  // Launch window (kBillingEnforced == false, the shipped default): every
  // install reads Pro before storage is consulted, so early downloaders
  // get the features unlocked. The stored key is irrelevant either way.
  group('pre-billing window (billingEnforced: false)', () {
    test('missing key still answers Pro', () async {
      final service = ProStatusService(FakePlatformService());
      expect(await service.isPro(), isTrue);
    });

    test('stale free value still answers Pro', () async {
      final platform = FakePlatformService();
      platform.store[proEntitlementKey] = '';
      expect(await ProStatusService(platform).isPro(), isTrue);
    });

    test('a revoked entitlement still answers Pro until billing lands',
        () async {
      final platform = FakePlatformService();
      final service = ProStatusService(platform);
      await service.grantPro();
      await service.revokePro();
      expect(platform.store[proEntitlementKey], isNull);
      expect(await service.isPro(), isTrue);
    });

    test('storage read error still answers Pro, never throws', () async {
      final service = ProStatusService(_ThrowingPlatformService());
      expect(await service.isPro(), isTrue);
    });
  });
}

class _ThrowingPlatformService extends FakePlatformService {
  @override
  Future<String?> secureRead(String key) async =>
      throw const SocketException('closed');
}

class _FailingDeletePlatformService extends FakePlatformService {
  @override
  Future<void> secureDelete(String key) async =>
      throw const SocketException('closed');
}
