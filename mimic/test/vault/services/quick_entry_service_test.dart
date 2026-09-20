// test/vault/services/quick_entry_service_test.dart
//
// F27 tests for the preference store and the single entry-gate decision.
// Same in-memory fake shape as pro_status_service_test.dart — no device,
// no network.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/quick_entry_service.dart';

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

/// A ready-to-open environment: Pro, preference on, vault exists, not
/// concealed. Individual tests break one condition at a time.
FakePlatformService readyPlatform() {
  final platform = FakePlatformService();
  platform.store[quickEntryEnabledKey] = quickEntryEnabledValue;
  platform.store[quickEntryVaultSaltKey] = 'a-salt';
  platform.store[quickEntryVaultConcealedKey] = 'false';
  return platform;
}

void main() {
  group('preference store', () {
    test('fresh install reads disabled (missing key)', () async {
      final service = QuickEntryService(FakePlatformService());
      expect(await service.isEnabled(), isFalse);
    });

    test('setEnabled(true) persists the canonical enabled value', () async {
      final platform = FakePlatformService();
      final service = QuickEntryService(platform);
      await service.setEnabled(true);
      expect(platform.store[quickEntryEnabledKey], 'true');
      expect(await service.isEnabled(), isTrue);
    });

    test('setEnabled(false) persists false and reads disabled', () async {
      final platform = FakePlatformService();
      final service = QuickEntryService(platform);
      await service.setEnabled(true);
      await service.setEnabled(false);
      expect(await service.isEnabled(), isFalse);
    });

    test('unknown stored value reads disabled, never enabled', () async {
      final platform = FakePlatformService();
      platform.store[quickEntryEnabledKey] = 'TRUE';
      expect(await QuickEntryService(platform).isEnabled(), isFalse);
    });

    test('storage read error reads disabled instead of throwing', () async {
      final service = QuickEntryService(_ThrowingPlatformService());
      expect(await service.isEnabled(), isFalse);
    });
  });

  group('shouldOpenEntry — the gate matrix', () {
    test('free user: denied even with preference on and vault present',
        () async {
      final service = QuickEntryService(readyPlatform());
      expect(await service.shouldOpenEntry(isPro: false), isFalse);
    });

    test('pro + preference off: denied (default OFF holds)', () async {
      final platform = readyPlatform();
      platform.store[quickEntryEnabledKey] = 'false';
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isFalse);
    });

    test('pro + preference missing: denied', () async {
      final platform = readyPlatform();
      platform.store.remove(quickEntryEnabledKey);
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isFalse);
    });

    test('pro + on + vault present + not concealed: ALLOWED', () async {
      final service = QuickEntryService(readyPlatform());
      expect(await service.shouldOpenEntry(isPro: true), isTrue);
    });

    test('pro + on + no vault: denied silently', () async {
      final platform = readyPlatform();
      platform.store.remove(quickEntryVaultSaltKey);
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isFalse);
    });

    test('pro + on + empty salt: denied silently', () async {
      final platform = readyPlatform();
      platform.store[quickEntryVaultSaltKey] = '';
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isFalse);
    });

    test('pro + on + vault concealed: denied silently', () async {
      final platform = readyPlatform();
      platform.store[quickEntryVaultConcealedKey] =
          quickEntryVaultConcealedValue;
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isFalse);
    });

    test('pro + on + conceal key missing: allowed (never concealed)',
        () async {
      final platform = readyPlatform();
      platform.store.remove(quickEntryVaultConcealedKey);
      expect(await QuickEntryService(platform).shouldOpenEntry(isPro: true),
          isTrue);
    });

    test('storage error mid-gate: denied, never throws', () async {
      final service = QuickEntryService(_ThrowingPlatformService());
      expect(await service.shouldOpenEntry(isPro: true), isFalse);
    });
  });
}

class _ThrowingPlatformService extends FakePlatformService {
  @override
  Future<String?> secureRead(String key) async =>
      throw const SocketException('closed');
}
