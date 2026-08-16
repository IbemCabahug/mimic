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
}
