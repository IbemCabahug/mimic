import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  final Map<String, Uint8List> fileStore = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    fileStore[path] = data;
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => fileStore[path];

  @override
  Future<void> deleteFile(String path) async {
    fileStore.remove(path);
  }

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

class FailingKeystoreService implements KeystoreService {
  final PlatformException exception;

  FailingKeystoreService(this.exception);

  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    throw KeystoreWrapException(exception.message ?? 'Keystore wrap failed');
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final combined = base64Decode(base64Data);
    if (combined.length < 12) return 'KEY_INVALID';
    final original = combined.sublist(12);
    return base64Encode(original);
  }

  @override
  Future<void> deleteKey() async {}
}

class StrictFakeKeystoreService implements KeystoreService {
  bool _keyExists = false;
  int ensureKeyCallCount = 0;

  bool get keyExists => _keyExists;

  @override
  Future<void> ensureKey() async {
    ensureKeyCallCount++;
    _keyExists = true;
  }

  @override
  Future<String> wrap(String base64Data) async {
    if (!_keyExists) {
      throw KeystoreWrapException('Key missing');
    }
    final original = base64Decode(base64Data);
    final iv = Uint8List(12); // dummy IV
    final combined = Uint8List(iv.length + original.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, original);
    return base64Encode(combined);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final combined = base64Decode(base64Data);
    if (combined.length < 12) return 'KEY_INVALID';
    final original = combined.sublist(12);
    return base64Encode(original);
  }

  @override
  Future<void> deleteKey() async {
    _keyExists = false;
  }
}

class EnsureKeyFailingKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {
    throw KeystoreWrapException('ensureKey failed');
  }

  @override
  Future<String> wrap(String base64Data) async {
    final original = base64Decode(base64Data);
    final iv = Uint8List(12);
    final combined = Uint8List(iv.length + original.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, original);
    return base64Encode(combined);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final combined = base64Decode(base64Data);
    if (combined.length < 12) return 'KEY_INVALID';
    final original = combined.sublist(12);
    return base64Encode(original);
  }

  @override
  Future<void> deleteKey() async {}
}

void main() {
  group('Keystore wrap failure', () {
    test('wrap failure surfaces as KeystoreWrapException during vault creation', () async {
      final platform = FakePlatformService();
      final failingKeystore = FailingKeystoreService(
        PlatformException(code: 'WRAP_ERROR', message: 'simulated wrap failure'),
      );
      final crypto = VaultCrypto(platform, failingKeystore);

      await expectLater(
        crypto.initialize('1111'),
        throwsA(isA<KeystoreWrapException>()),
        reason: 'Wrap failure must surface as a typed Dart exception',
      );
    });

    test('wrap failure does not persist a wrapped master key', () async {
      final platform = FakePlatformService();
      final failingKeystore = FailingKeystoreService(
        PlatformException(code: 'WRAP_ERROR', message: 'simulated wrap failure'),
      );
      final crypto = VaultCrypto(platform, failingKeystore);

      try {
        await crypto.initialize('1111');
      } on KeystoreWrapException {
        // expected
      }

      expect(platform.store.containsKey('master_key_wrapped'), isFalse,
          reason: 'No wrapped key must be persisted when wrap fails');
      expect(platform.store.containsKey('vault_salt'), isFalse,
          reason: 'No salt must be persisted when wrap fails');
      expect(platform.store.containsKey('vault_pin_hash'), isFalse,
          reason: 'No pin hash must be persisted when wrap fails');
    });
  });

  group('StrictFakeKeystoreService (ensureKey before wrap contract)', () {
    test('T2: fresh vault creation succeeds with StrictFakeKeystoreService', () async {
      final platform = FakePlatformService();
      final keystore = StrictFakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      expect(keystore.keyExists, isFalse);
      expect(keystore.ensureKeyCallCount, 0);

      await crypto.initialize('1234');

      expect(crypto.isUnlocked, isTrue);
      expect(keystore.keyExists, isTrue);
      expect(keystore.ensureKeyCallCount, greaterThanOrEqualTo(1));
      expect(platform.store['master_key_wrapped']?.startsWith('hw1:'), isTrue);
    });

    test('T3: changePin succeeds with StrictFakeKeystoreService', () async {
      final platform = FakePlatformService();
      final keystore = StrictFakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1234');
      final beforeWrapped = platform.store['master_key_wrapped'];
      expect(beforeWrapped?.startsWith('hw1:'), isTrue);

      final initialEnsureKeyCount = keystore.ensureKeyCallCount;

      await crypto.changePin('5678');

      expect(keystore.keyExists, isTrue);
      expect(keystore.ensureKeyCallCount, greaterThan(initialEnsureKeyCount));
      final afterWrapped = platform.store['master_key_wrapped'];
      expect(afterWrapped?.startsWith('hw1:'), isTrue);
      expect(afterWrapped, isNot(equals(beforeWrapped)));

      crypto.lock();
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('5678');
      expect(crypto2.isUnlocked, isTrue);
    });

    test('T4: migrateToHardwareBinding succeeds with StrictFakeKeystoreService on legacy vault', () async {
      final platform = FakePlatformService();
      final keystore = StrictFakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      platform.store.remove('master_key_wrapped');
      crypto.lock();

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.needsHardwareMigration, isTrue);
      final legacyWrapped = platform.store['master_key_wrapped']!;
      expect(legacyWrapped.startsWith('hw1:'), isFalse);

      final initialEnsureKeyCount = keystore.ensureKeyCallCount;

      await crypto2.migrateToHardwareBinding();

      expect(crypto2.needsHardwareMigration, isFalse);
      expect(keystore.keyExists, isTrue);
      expect(keystore.ensureKeyCallCount, greaterThan(initialEnsureKeyCount));
      expect(platform.store['master_key_wrapped']!.startsWith('hw1:'), isTrue);
    });

    test('T5: failing ensureKey aborts vault creation and persists no master key (fail-closed)', () async {
      final platform = FakePlatformService();
      final failingKeystore = EnsureKeyFailingKeystoreService();
      final crypto = VaultCrypto(platform, failingKeystore);

      await expectLater(
        crypto.initialize('1234'),
        throwsA(isA<KeystoreWrapException>()),
        reason: 'ensureKey failure must surface as KeystoreWrapException and abort',
      );

      expect(platform.store.containsKey('master_key_wrapped'), isFalse,
          reason: 'master_key_wrapped must not be persisted if ensureKey fails');
      expect(platform.store.containsKey('vault_salt'), isFalse,
          reason: 'vault_salt must not be persisted if ensureKey fails');
      expect(platform.store.containsKey('vault_pin_hash'), isFalse,
          reason: 'vault_pin_hash must not be persisted if ensureKey fails');
    });
  });
}

