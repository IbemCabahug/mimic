import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:pointycastle/export.dart';

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

    test('Phase B: encryptSystem -> decryptSystem round-trips a payload', () async {
      final vaultCrypto = VaultCrypto(FakePlatformService());
      await vaultCrypto.initialize('1234');
      final payload = Uint8List.fromList([10, 20, 30]);
      final cipher = await vaultCrypto.encryptSystem(payload);
      final decrypted = await vaultCrypto.decryptSystem(cipher);
      expect(decrypted, equals(payload));
    });

    test('Phase B: CROSS-INSTALL simulate fresh install decrypts media', () async {
      final oldService = FakePlatformService();
      final oldCrypto = VaultCrypto(oldService);
      await oldCrypto.initialize('1234');
      final recoveryWords = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await oldCrypto.storeRecoveryBlob(recoveryWords);
      
      final payload = Uint8List.fromList([10, 20, 30]);
      final cipher = await oldCrypto.encryptSystem(payload);

      // Simulate a fresh install: new service (no old system_key in storage), 
      // but master key is recovered.
      final newService = FakePlatformService();
      final blobStr = await oldService.secureRead('recovery_blob');
      final saltStr = await oldService.secureRead('recovery_salt');
      await newService.secureWrite('recovery_blob', blobStr!);
      await newService.secureWrite('recovery_salt', saltStr!);

      final newCrypto = VaultCrypto(newService);
      final recovered = await newCrypto.recoverWithPhrase(recoveryWords);
      expect(recovered, isTrue);

      final decrypted = await newCrypto.decryptSystem(cipher);
      expect(decrypted, equals(payload));
    });

    test('Phase B: LEGACY COMPAT decrypts old system_key blob', () async {
      final oldService = FakePlatformService();
      // Emulate the old encryptSystem directly to craft a legacy blob
      final systemKeyBytes = Uint8List.fromList(List.filled(32, 7)); // dummy key
      await oldService.secureWrite('system_key', base64Encode(systemKeyBytes));

      final payload = Uint8List.fromList([99, 88, 77]);
      final iv = Uint8List.fromList(List.filled(16, 1));
      
      final cipher = CBCBlockCipher(AESEngine());
      final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
      paddedCipher.init(
        true,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(systemKeyBytes), iv), null),
      );
      final encrypted = paddedCipher.process(payload);
      
      final legacyBlob = Uint8List(iv.length + encrypted.length);
      legacyBlob.setRange(0, iv.length, iv);
      legacyBlob.setRange(iv.length, legacyBlob.length, encrypted);

      // Now use the NEW vault crypto
      final vaultCrypto = VaultCrypto(oldService); // Same service so it reads system_key
      await vaultCrypto.initialize('1234');
      
      final decrypted = await vaultCrypto.decryptSystem(legacyBlob);
      expect(decrypted, equals(payload));
    });
  });
}
