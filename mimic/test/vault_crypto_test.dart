import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => _store[key];

  @override
  Future<void> secureWrite(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<void> deleteFile(String path) async {}
}

void main() {
  group('VaultCrypto', () {
    test('encrypt and decrypt are inverses', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());

      await vaultCrypto.initialize('1234');

      final testText = 'Hello, World!';
      final data = Uint8List.fromList(utf8.encode(testText));
      final encrypted = vaultCrypto.encrypt(data);
      final decrypted = vaultCrypto.decrypt(encrypted);
      expect(utf8.decode(decrypted), equals(testText));
    });

    test('Empty data encrypt/decrypt works', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());

      await vaultCrypto.initialize('1234');

      final encrypted = vaultCrypto.encrypt(Uint8List(0));
      final decrypted = vaultCrypto.decrypt(encrypted);
      expect(decrypted, equals(Uint8List(0)));
    });

    test('Single byte encrypt/decrypt works', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());

      await vaultCrypto.initialize('1234');

      final encrypted = vaultCrypto.encrypt(Uint8List.fromList([65]));
      final decrypted = vaultCrypto.decrypt(encrypted);
      expect(decrypted, equals(Uint8List.fromList([65])));
    });

    test('Large data encrypt/decrypt works', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());

      await vaultCrypto.initialize('1234');

      final testData = Uint8List.fromList(List.filled(1000, 65)); // 'A' * 1000
      final encrypted = vaultCrypto.encrypt(testData);
      final decrypted = vaultCrypto.decrypt(encrypted);
      expect(decrypted, equals(testData));
    });

    test('lock clears derived key', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());

      await vaultCrypto.initialize('1234');
      expect(vaultCrypto.isUnlocked, isTrue);

      vaultCrypto.lock();
      expect(vaultCrypto.isUnlocked, isFalse);
    });
  });
}
