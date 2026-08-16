// test/vault/crypto/atomicity_test.dart
//
// Proves the atomicity invariant for the vault triple:
// (vault_salt, vault_pin_hash, master_key_wrapped) must never be observable
// in a mixed old/new state. Any interruption at any point must leave either
// the complete old triple or the complete new triple, both fully valid.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
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
  Future<File> resolveVaultFile(String path) async =>
      throw UnimplementedError();
}

/// A keystore service whose wrap() or unwrap() can be configured on demand.
class ControllableKeystoreService implements KeystoreService {
  final FakeKeystoreService _delegate = FakeKeystoreService();
  bool shouldFailWrap = false;
  String? unwrapOverride;
  String Function(String)? unwrapTransformer;

  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    if (shouldFailWrap) {
      throw KeystoreWrapException('Simulated wrap failure');
    }
    return _delegate.wrap(base64Data);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    if (unwrapOverride != null) {
      return unwrapOverride!;
    }
    final result = await _delegate.unwrap(base64Data);
    if (unwrapTransformer != null) {
      return unwrapTransformer!(result);
    }
    return result;
  }

  @override
  Future<void> deleteKey() async {}
}

void main() {
  group('Atomicity invariant for vault triple', () {
    test('a) wrap fails → old triple intact, no temps left behind', () async {
      final platform = FakePlatformService();
      final keystore = ControllableKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      // Create vault with initial PIN.
      await crypto.initialize('1111');
      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      // Encrypt data to verify DEK later.
      final secret = Uint8List.fromList(utf8.encode('atomicity proof'));
      final ciphertext = crypto.encrypt(secret);

      // Make wrap fail for the next call.
      keystore.shouldFailWrap = true;

      await expectLater(
        crypto.changePin('2222'),
        throwsA(isA<KeystoreWrapException>()),
        reason: 'changePin must throw when wrap fails',
      );

      // Old triple must be intact.
      expect(platform.store['vault_salt'], equals(origSalt),
          reason: 'Salt must be unchanged after failed wrap');
      expect(platform.store['vault_pin_hash'], equals(origHash),
          reason: 'Pin hash must be unchanged after failed wrap');
      expect(platform.store['master_key_wrapped'], equals(origWrapped),
          reason: 'Wrapped key must be unchanged after failed wrap');

      // No temp or swap keys left behind.
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse,
          reason: 'No temp salt after wrap failure');
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse,
          reason: 'No temp hash after wrap failure');
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse,
          reason: 'No temp wrapped after wrap failure');
      expect(platform.store.containsKey('_swap_in_progress'), isFalse,
          reason: 'No swap marker after wrap failure');

      // Old PIN still unlocks and DEK is intact.
      keystore.shouldFailWrap = false;
      crypto.lock();
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret),
          reason: 'DEK must still decrypt after failed changePin');
    });

    test(
        'b) crash after temps written, before canonical swap → old triple still unlocks',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('pre-crash data'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Simulate crash: temps are written but marker is NOT set yet.
      // (In the real code, this is a crash between step 3 and step 6.)
      platform.store['_tmp_vault_salt'] = 'orphaned_salt';
      platform.store['_tmp_vault_pin_hash'] = 'orphaned_hash';
      platform.store['_tmp_master_key_wrapped'] = 'orphaned_wrapped';
      // No marker, no backups — simulates crash before backup/marker writes.

      // Unlock with old PIN — recovery cleans up orphaned temps, canonical intact.
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue,
          reason: 'Old triple must still unlock after orphaned temps');
      expect(crypto2.decrypt(ciphertext), equals(secret),
          reason: 'Old DEK must still decrypt after orphaned temps');

      // Temps must be cleaned up.
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse,
          reason: 'Orphaned temp salt must be cleaned up');
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse,
          reason: 'Orphaned temp hash must be cleaned up');
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse,
          reason: 'Orphaned temp wrapped must be cleaned up');

      // Canonical triple is the original.
      expect(platform.store['vault_salt'], equals(origSalt));
      expect(platform.store['vault_pin_hash'], equals(origHash));
      expect(platform.store['master_key_wrapped'], equals(origWrapped));
    });

    test(
        'c) crash mid canonical swap → recovery path restores a consistent triple',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('must survive'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Simulate crash mid-swap: temps, backups, and marker all exist.
      // Canonical is partially overwritten (only salt was updated).
      platform.store['_tmp_vault_salt'] = 'new_salt';
      platform.store['_tmp_vault_pin_hash'] = 'new_hash';
      platform.store['_tmp_master_key_wrapped'] = 'new_wrapped';
      platform.store['_bak_vault_salt'] = origSalt;
      platform.store['_bak_vault_pin_hash'] = origHash;
      platform.store['_bak_master_key_wrapped'] = origWrapped;
      platform.store['_swap_in_progress'] = 'true';
      // Corrupt canonical: only salt updated, hash and wrapped still old.
      platform.store['vault_salt'] = 'new_salt';
      // vault_pin_hash and master_key_wrapped remain at original values.

      // Unlock with old PIN — recovery should roll back from backup.
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue,
          reason: 'Recovery must restore canonical and allow unlock');
      expect(crypto2.decrypt(ciphertext), equals(secret),
          reason: 'DEK must survive a mid-swap crash recovery');

      // All swap artifacts cleaned up.
      expect(platform.store.containsKey('_swap_in_progress'), isFalse,
          reason: 'Swap marker must be cleaned up after recovery');
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);

      // Canonical triple is the old (restored) triple.
      expect(platform.store['vault_salt'], equals(origSalt),
          reason: 'Canonical salt must be restored from backup');
      expect(platform.store['vault_pin_hash'], equals(origHash),
          reason: 'Canonical hash must be restored from backup');
      expect(platform.store['master_key_wrapped'], equals(origWrapped),
          reason: 'Canonical wrapped must be restored from backup');
    });

    test(
        'd) happy path changePin → new PIN unlocks, old PIN rejected, DEK unchanged',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      // Encrypt data under original DEK.
      final secret = Uint8List.fromList(utf8.encode('precious media'));
      final ciphertext = crypto.encrypt(secret);

      final origWrapped = platform.store['master_key_wrapped']!;

      await crypto.changePin('2222');

      // Same instance still decrypts (DEK unchanged).
      expect(crypto.decrypt(ciphertext), equals(secret),
          reason: 'DEK must not change during PIN change');

      // Wrapped key must have changed (new KEK).
      expect(platform.store['master_key_wrapped'], isNot(equals(origWrapped)),
          reason: 'Wrapped key must change due to new KEK');

      // New PIN unlocks on fresh instance.
      crypto.lock();
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('2222');
      expect(crypto2.isUnlocked, isTrue,
          reason: 'New PIN must unlock the vault');
      expect(crypto2.decrypt(ciphertext), equals(secret),
          reason: 'New PIN must decrypt data encrypted before PIN change');

      // Old PIN rejected.
      crypto2.lock();
      final crypto3 = VaultCrypto(platform, keystore);
      await expectLater(
        crypto3.initialize('1111'),
        throwsA(isA<Exception>()),
        reason: 'Old PIN must be rejected after change',
      );

      // No swap artifacts remain.
      expect(platform.store.containsKey('_swap_in_progress'), isFalse,
          reason: 'Swap marker must be cleaned up on success');
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse,
          reason: 'Temp salt must be cleaned up on success');
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse,
          reason: 'Temp hash must be cleaned up on success');
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse,
          reason: 'Temp wrapped must be cleaned up on success');
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse,
          reason: 'Backup salt must be cleaned up on success');
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse,
          reason: 'Backup hash must be cleaned up on success');
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse,
          reason: 'Backup wrapped must be cleaned up on success');
    });
  });

  group('Hardware migration and recovery atomicity', () {
    test(
        'a) migrate: staged blob fails hardware unwrap -> canonical master_key_wrapped unchanged, _needsHardwareMigration still true, _temporaryKek still usable',
        () async {
      final platform = FakePlatformService();
      final keystore = ControllableKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('migration payload'));
      final ciphertext = crypto.encrypt(secret);

      platform.store.remove('master_key_wrapped');
      crypto.lock();

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.needsHardwareMigration, isTrue);
      final legacyWrapped = platform.store['master_key_wrapped']!;
      expect(legacyWrapped.startsWith('hw1:'), isFalse);

      keystore.unwrapOverride = 'KEY_INVALID';

      await expectLater(
        crypto2.migrateToHardwareBinding(),
        throwsA(isA<StateError>()),
        reason: 'Migration must fail if staged hardware unwrap fails',
      );

      expect(platform.store['master_key_wrapped'], equals(legacyWrapped));
      expect(crypto2.needsHardwareMigration, isTrue);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);

      keystore.unwrapOverride = null;
      await crypto2.migrateToHardwareBinding();
      expect(crypto2.needsHardwareMigration, isFalse);
      expect(platform.store['master_key_wrapped']!.startsWith('hw1:'), isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));
    });

    test(
        'b) migrate: staged blob unwraps to the wrong DEK -> canonical master_key_wrapped unchanged, _needsHardwareMigration still true, _temporaryKek still usable',
        () async {
      final platform = FakePlatformService();
      final keystore = ControllableKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('migration payload 2'));
      final ciphertext = crypto.encrypt(secret);

      platform.store.remove('master_key_wrapped');
      crypto.lock();

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.needsHardwareMigration, isTrue);
      final legacyWrapped = platform.store['master_key_wrapped']!;

      keystore.unwrapTransformer = (orig) =>
          base64Encode(Uint8List.fromList(List.generate(32, (i) => i)));

      await expectLater(
        crypto2.migrateToHardwareBinding(),
        throwsA(isA<StateError>()),
        reason: 'Migration must fail if unwrapped DEK does not match live DEK',
      );

      expect(platform.store['master_key_wrapped'], equals(legacyWrapped));
      expect(crypto2.needsHardwareMigration, isTrue);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);

      keystore.unwrapTransformer = null;
      await crypto2.migrateToHardwareBinding();
      expect(crypto2.needsHardwareMigration, isFalse);
      expect(platform.store['master_key_wrapped']!.startsWith('hw1:'), isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));
    });

    test(
        'c) migrate happy path -> canonical updated, flag cleared, KEK zeroed, and media still decrypts',
        () async {
      final platform = FakePlatformService();
      final keystore = ControllableKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('happy path media'));
      final ciphertext = crypto.encrypt(secret);

      platform.store.remove('master_key_wrapped');
      crypto.lock();

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.needsHardwareMigration, isTrue);
      final legacyWrapped = platform.store['master_key_wrapped']!;

      await crypto2.migrateToHardwareBinding();

      expect(platform.store['master_key_wrapped'], isNot(equals(legacyWrapped)));
      expect(platform.store['master_key_wrapped']!.startsWith('hw1:'), isTrue);
      expect(crypto2.needsHardwareMigration, isFalse);

      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);

      expect(crypto2.decrypt(ciphertext), equals(secret));

      crypto2.lock();
      final crypto3 = VaultCrypto(platform, keystore);
      await crypto3.initialize('1111');
      expect(crypto3.needsHardwareMigration, isFalse);
      expect(crypto3.decrypt(ciphertext), equals(secret));
    });

    test(
        'd) recovery: marker present, canonical inconsistent, backups incomplete -> throws, and marker plus backups plus temps all still present afterward',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      crypto.lock();

      platform.store['_swap_in_progress'] = 'true';
      platform.store['_tmp_vault_salt'] = 'new_salt';
      platform.store['_tmp_vault_pin_hash'] = 'new_hash';
      platform.store['_tmp_master_key_wrapped'] = 'new_wrapped';
      platform.store['_bak_vault_salt'] = origSalt;
      platform.store['_bak_vault_pin_hash'] = origHash;
      // Intentionally omit _bak_master_key_wrapped
      platform.store['vault_salt'] = 'inconsistent_salt';

      final crypto2 = VaultCrypto(platform, keystore);
      await expectLater(
        crypto2.initialize('1111'),
        throwsA(isA<VaultSwapRecoveryException>()),
        reason: 'Recovery must throw when backup triple is incomplete',
      );

      expect(platform.store.containsKey('_swap_in_progress'), isTrue,
          reason: 'Marker must be preserved for retry');
      expect(platform.store.containsKey('_tmp_vault_salt'), isTrue);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isTrue);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isTrue);
      expect(platform.store.containsKey('_bak_vault_salt'), isTrue);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isTrue);
    });

    test(
        'e) recovery: marker present, canonical inconsistent, backups complete -> canonical restored and all artifacts cleaned',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('recovery data'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      platform.store['_swap_in_progress'] = 'true';
      platform.store['_tmp_vault_salt'] = 'new_salt';
      platform.store['_tmp_vault_pin_hash'] = 'new_hash';
      platform.store['_tmp_master_key_wrapped'] = 'new_wrapped';
      platform.store['_bak_vault_salt'] = origSalt;
      platform.store['_bak_vault_pin_hash'] = origHash;
      platform.store['_bak_master_key_wrapped'] = origWrapped;
      platform.store['vault_salt'] = 'inconsistent_salt';

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));

      expect(platform.store['vault_salt'], equals(origSalt));
      expect(platform.store['vault_pin_hash'], equals(origHash));
      expect(platform.store['master_key_wrapped'], equals(origWrapped));

      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
    });

    test(
        'f) marker pin:swapped, temps already deleted, backups still present -> recovery must NOT restore',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final oldSalt = platform.store['vault_salt']!;
      final oldHash = platform.store['vault_pin_hash']!;
      final oldWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('regression proof'));
      final ciphertext = crypto.encrypt(secret);

      // Perform changePin to '2222' to get valid new values
      await crypto.changePin('2222');
      final newSalt = platform.store['vault_salt']!;
      final newHash = platform.store['vault_pin_hash']!;
      final newWrapped = platform.store['master_key_wrapped']!;
      crypto.lock();

      // Simulate power loss after temps deleted but before marker deleted
      platform.store['_swap_in_progress'] = 'pin:swapped';
      platform.store['_bak_vault_salt'] = oldSalt;
      platform.store['_bak_vault_pin_hash'] = oldHash;
      platform.store['_bak_master_key_wrapped'] = oldWrapped;
      // Temps are already deleted (not in platform.store)
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);

      // Unlock on fresh instance: must recognize pin:swapped, NOT restore old triple,
      // and allow unlock with the NEW PIN '2222'
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('2222');
      expect(crypto2.isUnlocked, isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));

      // Canonical triple must remain the new values
      expect(platform.store['vault_salt'], equals(newSalt));
      expect(platform.store['vault_pin_hash'], equals(newHash));
      expect(platform.store['master_key_wrapped'], equals(newWrapped));

      // Artifacts must be cleaned up
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
    });

    test(
        'g) marker hw:swapped, temps deleted, backup wrapped present -> canonical master_key_wrapped unchanged, no restore',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      // 1. Set up vault in pre-migration state (needsHardwareMigration true)
      await crypto.initialize('1111');
      // 2. Encrypt known plaintext before migrating
      final secret = Uint8List.fromList(utf8.encode('hw swapped proof'));
      final ciphertext = crypto.encrypt(secret);

      platform.store.remove('master_key_wrapped');
      crypto.lock();

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.needsHardwareMigration, isTrue);
      final legacyWrapped = platform.store['master_key_wrapped']!;

      // 3. Run a REAL migrateToHardwareBinding() to produce a genuine hw1: blob
      await crypto2.migrateToHardwareBinding();
      final migratedHwWrapped = platform.store['master_key_wrapped']!;
      expect(migratedHwWrapped.startsWith('hw1:'), isTrue);
      crypto2.lock();

      // 4. Simulate crash: marker 'hw:swapped' and different backup value
      platform.store['_swap_in_progress'] = 'hw:swapped';
      platform.store['_bak_master_key_wrapped'] = legacyWrapped;
      // Temps are absent
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);

      // 5. Fresh instance initialize() with the PIN
      final crypto3 = VaultCrypto(platform, keystore);
      await crypto3.initialize('1111');

      // 6. Assertions: unlock succeeds, plaintext decrypts, canonical not replaced, artifacts gone
      expect(crypto3.isUnlocked, isTrue);
      expect(crypto3.decrypt(ciphertext), equals(secret));
      expect(platform.store['master_key_wrapped'], equals(migratedHwWrapped));
      expect(platform.store['master_key_wrapped'], isNot(equals(legacyWrapped)));

      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
    });

    test(
        'h) marker pin:staged, canonical partially written, full backup present -> canonical restored to the OLD triple, vault unlocks with the OLD pin',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('staged pin proof'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Crash while canonical writes were in flight (only salt written)
      platform.store['_swap_in_progress'] = 'pin:staged';
      platform.store['_tmp_vault_salt'] = 'new_staged_salt';
      platform.store['_tmp_vault_pin_hash'] = 'new_staged_hash';
      platform.store['_tmp_master_key_wrapped'] = 'new_staged_wrapped';
      platform.store['_bak_vault_salt'] = origSalt;
      platform.store['_bak_vault_pin_hash'] = origHash;
      platform.store['_bak_master_key_wrapped'] = origWrapped;
      platform.store['vault_salt'] = 'new_staged_salt'; // partially written

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));

      // Canonical triple restored to old values
      expect(platform.store['vault_salt'], equals(origSalt));
      expect(platform.store['vault_pin_hash'], equals(origHash));
      expect(platform.store['master_key_wrapped'], equals(origWrapped));

      // Artifacts cleaned
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
    });

    test(
        'i) marker legacy literal true, canonical inconsistent, full backup present -> treated as pin:staged, restored, no exception',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      final origSalt = platform.store['vault_salt']!;
      final origHash = platform.store['vault_pin_hash']!;
      final origWrapped = platform.store['master_key_wrapped']!;

      final secret = Uint8List.fromList(utf8.encode('legacy literal true proof'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Simulate legacy install state with marker 'true'
      platform.store['_swap_in_progress'] = 'true';
      platform.store['_bak_vault_salt'] = origSalt;
      platform.store['_bak_vault_pin_hash'] = origHash;
      platform.store['_bak_master_key_wrapped'] = origWrapped;
      platform.store['vault_salt'] = 'corrupted_legacy_salt';

      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('1111');
      expect(crypto2.isUnlocked, isTrue);
      expect(crypto2.decrypt(ciphertext), equals(secret));

      expect(platform.store['vault_salt'], equals(origSalt));
      expect(platform.store['vault_pin_hash'], equals(origHash));
      expect(platform.store['master_key_wrapped'], equals(origWrapped));

      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
    });

    test(
        'j) after any successful cleanup, assert the marker is absent AND that no temp or backup keys remain',
        () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1111');

      void assertNoArtifacts() {
        expect(platform.store.containsKey('_swap_in_progress'), isFalse);
        expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
        expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
        expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
        expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
        expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
        expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
      }

      // Case 1: normal changePin
      await crypto.changePin('2222');
      assertNoArtifacts();

      // Case 2: recovery from pin:staged
      platform.store['_swap_in_progress'] = 'pin:staged';
      platform.store['_tmp_vault_salt'] = 't_salt';
      platform.store['_tmp_vault_pin_hash'] = 't_hash';
      platform.store['_tmp_master_key_wrapped'] = 't_wrapped';
      platform.store['_bak_vault_salt'] = platform.store['vault_salt']!;
      platform.store['_bak_vault_pin_hash'] = platform.store['vault_pin_hash']!;
      platform.store['_bak_master_key_wrapped'] = platform.store['master_key_wrapped']!;
      final crypto2 = VaultCrypto(platform, keystore);
      await crypto2.initialize('2222');
      assertNoArtifacts();

      // Case 3: recovery from hw:staged
      platform.store['_swap_in_progress'] = 'hw:staged';
      platform.store['_tmp_master_key_wrapped'] = 't_wrapped';
      platform.store['_bak_master_key_wrapped'] = platform.store['master_key_wrapped']!;
      final crypto3 = VaultCrypto(platform, keystore);
      await crypto3.initialize('2222');
      assertNoArtifacts();
    });
  });
}
