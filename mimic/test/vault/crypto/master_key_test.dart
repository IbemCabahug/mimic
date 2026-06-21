// test/vault/crypto/master_key_test.dart
//
// Proves the master-key (KEK/DEK) lockbox: changing or resetting the PIN must
// NEVER orphan data, legacy vaults migrate transparently, and changePin refuses
// to run on a locked vault.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';

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

const List<String> kRecoveryWords = [
  'alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot',
  'golf', 'hotel', 'india', 'juliet', 'kilo', 'lima',
];

void main() {
  group('Master-key lockbox (KEK/DEK)', () {
    test(
      'reset PIN via recovery phrase keeps existing data decryptable',
      () async {
        final platform = FakePlatformService();
        final crypto = VaultCrypto(platform);
        await crypto.initialize('1111'); // first-time setup

        // Recovery phrase wraps the data key.
        await crypto.storeRecoveryBlob(kRecoveryWords);

        // Encrypt data under the original PIN.
        final secret = Uint8List.fromList(utf8.encode('top secret bytes'));
        final ciphertext = crypto.encrypt(secret);

        // Simulate the "Forgot PIN" flow: fresh instance -> recover -> reset PIN.
        final crypto2 = VaultCrypto(platform);
        final recovered = await crypto2.recoverWithPhrase(kRecoveryWords);
        expect(recovered, isTrue);
        await crypto2.changePin('2222');

        // The pre-reset data MUST still decrypt (this is the bug we killed).
        expect(crypto2.decrypt(ciphertext), equals(secret),
            reason: 'Data must survive a PIN reset via recovery phrase');

        // A fresh unlock with the NEW PIN must also read it.
        final crypto3 = VaultCrypto(platform);
        await crypto3.initialize('2222');
        expect(crypto3.decrypt(ciphertext), equals(secret));
      },
    );

    test(
      'changePin re-wraps the same data key (no orphaning)',
      () async {
        final platform = FakePlatformService();
        final crypto = VaultCrypto(platform);
        await crypto.initialize('1111');

        final secret = Uint8List.fromList(utf8.encode('unchanged-key proof'));
        final ciphertext = crypto.encrypt(secret);

        await crypto.changePin('9999');

        // Same live instance still decrypts.
        expect(crypto.decrypt(ciphertext), equals(secret));

        // Fresh unlock with the new PIN decrypts pre-change data.
        final crypto2 = VaultCrypto(platform);
        await crypto2.initialize('9999');
        expect(crypto2.decrypt(ciphertext), equals(secret),
            reason: 'changePin must not orphan previously-encrypted data');

        // The old PIN must no longer unlock.
        final crypto3 = VaultCrypto(platform);
        await expectLater(
          crypto3.initialize('1111'),
          throwsA(isA<Exception>()),
          reason: 'Old PIN must be rejected after a PIN change',
        );
      },
    );

    test(
      'legacy vault with no wrapped key migrates and keeps data',
      () async {
        final platform = FakePlatformService();
        final crypto = VaultCrypto(platform);
        await crypto.initialize('4321');

        final secret = Uint8List.fromList(utf8.encode('legacy data'));
        final ciphertext = crypto.encrypt(secret);

        // Simulate a pre-lockbox vault: remove the wrapped key entirely.
        platform.store.remove('master_key_wrapped');
        expect(platform.store.containsKey('master_key_wrapped'), isFalse);

        // Unlock with a fresh instance: should adopt the existing data key,
        // persist a wrapped copy, and still decrypt the old data.
        final crypto2 = VaultCrypto(platform);
        await crypto2.initialize('4321');
        expect(platform.store.containsKey('master_key_wrapped'), isTrue,
            reason: 'Legacy unlock must persist a wrapped data key');
        expect(crypto2.decrypt(ciphertext), equals(secret),
            reason: 'Legacy data must remain decryptable after migration');

        // A later unlock (now via the wrapped path) must also work.
        final crypto3 = VaultCrypto(platform);
        await crypto3.initialize('4321');
        expect(crypto3.decrypt(ciphertext), equals(secret));
      },
    );

    test(
      'changePin throws when the vault is locked',
      () async {
        final platform = FakePlatformService();
        final locked = VaultCrypto(platform);
        expect(locked.isUnlocked, isFalse);
        await expectLater(
          locked.changePin('2222'),
          throwsA(isA<Exception>()),
          reason: 'changePin must refuse when no data key is loaded',
        );
      },
    );

    test(
      'device repro: setup -> recover -> reset PIN (no-arg storeRecoveryBlob) -> recover again',
      () async {
        final platform = FakePlatformService();

        // 1) Initial setup + save recovery phrase (mirrors RecoveryPhraseScreen).
        final setup = VaultCrypto(platform);
        await setup.initialize('1111');
        await setup.storeRecoveryBlob(kRecoveryWords);
        final secret = Uint8List.fromList(utf8.encode('device secret'));
        final ciphertext = setup.encrypt(secret);

        // 2) Forgot-PIN flow on one shared instance (like the singleton provider):
        //    EnterRecoveryScreen.recoverWithPhrase -> ResetPinScreen.changePin + storeRecoveryBlob().
        final session = VaultCrypto(platform);
        final recovered1 = await session.recoverWithPhrase(kRecoveryWords);
        expect(recovered1, isTrue, reason: 'first recovery must succeed');
        await session.changePin('2222');
        await session.storeRecoveryBlob(); // NO ARGS — exactly what reset_pin_screen does

        // 3) Later: Forgot PIN again, fresh instance, SAME 12 words.
        final again = VaultCrypto(platform);
        final recovered2 = await again.recoverWithPhrase(kRecoveryWords);
        expect(recovered2, isTrue,
            reason: 'recovery with the SAME words must still work after a PIN reset');
        expect(again.decrypt(ciphertext), equals(secret),
            reason: 'data must still decrypt after recover -> reset -> recover');
      },
    );

    test('photos survive a PIN change and an app restart (DEK preserved)', () async {
      final platform = FakePlatformService();
      final crypto = VaultCrypto(platform);
      await crypto.initialize('11111111');

      final secret = Uint8List.fromList(utf8.encode('my secret photo bytes'));
      final encrypted = await crypto.encryptSystem(secret);

      // Proper PIN change must NOT change the data key.
      await crypto.changePin('22222222');
      final afterChange = await crypto.decryptSystem(encrypted);
      expect(afterChange, equals(secret));

      // Fresh app instance unlocking with the new PIN must still decrypt.
      final crypto2 = VaultCrypto(platform);
      await crypto2.initialize('22222222');
      final afterRestart = await crypto2.decryptSystem(encrypted);
      expect(afterRestart, equals(secret));
    });
  });
}
