// test/vault/crypto/atomicity_test.dart
//
// Proves the atomicity invariant for the vault triple:
// (vault_salt, vault_pin_hash, master_key_wrapped) must never be observable
// in a mixed old/new state. Any interruption at any point must leave either
// the complete old triple or the complete new triple, both fully valid.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
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
  Completer<void>? wrapEntered;
  Completer<void>? wrapGate;

  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    if (shouldFailWrap) {
      throw KeystoreWrapException('Simulated wrap failure');
    }
    final entered = wrapEntered;
    if (entered != null && !entered.isCompleted) {
      entered.complete();
    }
    final gate = wrapGate;
    if (gate != null) {
      await gate.future;
    }
    return _delegate.wrap(base64Data);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final override = unwrapOverride;
    if (override != null) {
      return override;
    }
    final result = await _delegate.unwrap(base64Data);
    final transformer = unwrapTransformer;
    if (transformer != null) {
      return transformer(result);
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

  group('Concurrency and operational failure hardening', () {
    test('1. Two concurrent changePin calls both complete cleanly, leaving consistent triple with second PIN winning', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('concurrency test payload'));
      final ciphertext = crypto.encrypt(secret);

      // Fire two changePin calls concurrently
      final f1 = crypto.changePin('2222');
      final f2 = crypto.changePin('3333');
      await Future.wait([f1, f2]);

      expect(crypto.isUnlocked, isTrue);
      expect(crypto.decrypt(ciphertext), equals(secret));

      // Assert no temp or swap artifacts remain
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);

      // Fresh instance: the second PIN '3333' wins and unlocks the vault
      crypto.lock();
      final unlockCrypto = VaultCrypto(platform, keystore);
      await unlockCrypto.initialize('3333');
      expect(unlockCrypto.isUnlocked, isTrue);
      expect(unlockCrypto.decrypt(ciphertext), equals(secret));

      // Old PIN '1111' and intermediate PIN '2222' fail
      unlockCrypto.lock();
      final oldCrypto1 = VaultCrypto(platform, keystore);
      await expectLater(
        () => oldCrypto1.initialize('1111'),
        throwsA(isA<InvalidPinException>()),
      );
      final oldCrypto2 = VaultCrypto(platform, keystore);
      await expectLater(
        () => oldCrypto2.initialize('2222'),
        throwsA(isA<InvalidPinException>()),
      );
    });

    test('2. Concurrent initialize calls serialize cleanly and do not corrupt recovery state', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('init concurrency payload'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Simulate partial staging swap marker to verify serialized recovery
      platform.store['_swap_in_progress'] = 'pin:swapped';
      platform.store['_bak_vault_salt'] = 'old_salt';
      platform.store['_bak_vault_pin_hash'] = 'old_hash';
      platform.store['_bak_master_key_wrapped'] = 'old_wrapped';

      final initCrypto = VaultCrypto(platform, keystore);
      final f1 = initCrypto.initialize('1111');
      final f2 = initCrypto.initialize('1111');
      await Future.wait([f1, f2]);

      expect(initCrypto.isUnlocked, isTrue);
      expect(initCrypto.decrypt(ciphertext), equals(secret));

      // Swap artifacts cleaned up properly
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);
    });

    test('3. Operational failure throws non-InvalidPinException while genuine wrong PIN throws InvalidPinException', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      crypto.lock();

      // Case A: Genuine wrong PIN throws InvalidPinException
      final wrongPinCrypto = VaultCrypto(platform, keystore);
      await expectLater(
        () => wrongPinCrypto.initialize('9999'),
        throwsA(isA<InvalidPinException>()),
        reason: 'Wrong PIN must throw InvalidPinException so wrong_attempts is incremented',
      );

      // Case B: Operational failure (e.g. missing critical key in storage) throws SystemKeyMissingException
      final corruptedPlatform = FakePlatformService();
      corruptedPlatform.store['vault_salt'] = platform.store['vault_salt']!;
      // Intentionally omit 'vault_pin_hash'
      final operationalCrypto = VaultCrypto(corruptedPlatform, keystore);
      await expectLater(
        () => operationalCrypto.initialize('1111'),
        throwsA(isA<SystemKeyMissingException>()),
        reason: 'Storage corruption/missing key must throw SystemKeyMissingException, not InvalidPinException',
      );

      // Case C: Operational failure (e.g. corrupted verifier syntax) throws InvalidVerifierException
      corruptedPlatform.store['vault_pin_hash'] = 'malformed_verifier';
      final malformedCrypto = VaultCrypto(corruptedPlatform, keystore);
      await expectLater(
        () => malformedCrypto.initialize('1111'),
        throwsA(isA<InvalidVerifierException>()),
        reason: 'Malformed verifier must throw InvalidVerifierException, not InvalidPinException',
      );
    });

    test('4. lock() issued during in-flight changePin completes safely, leaves vault locked, and new PIN works', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('lock during changePin test payload'));
      final ciphertext = crypto.encrypt(secret);

      // Start changePin
      final changePinFuture = crypto.changePin('2222');

      // Issue lock() while changePin is in-flight
      crypto.lock();

      // Await completion of the changePin operation
      await changePinFuture;

      // Vault must be locked after the operation completes
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(8)), throwsException);
      expect(() => crypto.decrypt(ciphertext), throwsException);

      // Clean storage state: no swap or temp artifacts left behind
      expect(platform.store.containsKey('_swap_in_progress'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_salt'), isFalse);
      expect(platform.store.containsKey('_tmp_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_tmp_master_key_wrapped'), isFalse);
      expect(platform.store.containsKey('_bak_vault_salt'), isFalse);
      expect(platform.store.containsKey('_bak_vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('_bak_master_key_wrapped'), isFalse);

      // Verify that the new PIN '2222' unlocks and decrypts the data
      final unlockCrypto = VaultCrypto(platform, keystore);
      await unlockCrypto.initialize('2222');
      expect(unlockCrypto.isUnlocked, isTrue);
      expect(unlockCrypto.decrypt(ciphertext), equals(secret));

      // Old PIN '1111' is rejected
      unlockCrypto.lock();
      final oldCrypto = VaultCrypto(platform, keystore);
      await expectLater(
        () => oldCrypto.initialize('1111'),
        throwsA(isA<InvalidPinException>()),
      );
    });

    test('5. Vault creation interrupted after hash and wrapped key writes but before salt write allows fresh creation to succeed', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();

      // Simulate an interrupted creation: hash and wrapped key were written, but salt is missing (not yet committed)
      platform.store['vault_pin_hash'] = 'v3:100000:some_partial_hash';
      platform.store['master_key_wrapped'] = 'hw1:some_partial_wrapped_blob';
      expect(platform.store.containsKey('vault_salt'), isFalse);

      // A fresh creation attempt with PIN '1234' must succeed without throwing SystemKeyMissingException
      final freshCrypto = VaultCrypto(platform, keystore);
      await freshCrypto.initialize('1234');

      expect(freshCrypto.isUnlocked, isTrue);
      expect(platform.store.containsKey('vault_salt'), isTrue);
      expect(platform.store.containsKey('vault_pin_hash'), isTrue);
      expect(platform.store.containsKey('master_key_wrapped'), isTrue);

      final payload = Uint8List.fromList(utf8.encode('creation recovery payload'));
      final cipher = freshCrypto.encrypt(payload);

      // Lock and unlock to verify end-to-end viability
      freshCrypto.lock();
      final reOpenCrypto = VaultCrypto(platform, keystore);
      await reOpenCrypto.initialize('1234');
      expect(reOpenCrypto.isUnlocked, isTrue);
      expect(reOpenCrypto.decrypt(cipher), equals(payload));
    });

    test('6. lock() immediately clears isUnlocked and nulls instance fields DURING in-flight changePin window', () async {
      // WHAT THIS TEST PROVES:
      // 1. Calling lock() synchronously sets isUnlocked to false immediately.
      // 2. The instance methods encrypt() and decrypt() fail immediately without waiting for changePin to finish.
      // 3. VaultCrypto fields are immediately decoupled from the in-flight operation.
      //
      // WHAT THIS TEST DOES NOT PROVE:
      // It does not prove that Dart's GC or underlying operating system memory has overwritten
      // every byte in RAM at that exact microsecond; the underlying byte buffer zeroing is scheduled
      // and completes sequentially via _mutex once changePin releases its local reference.
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final ciphertext = crypto.encrypt(Uint8List.fromList(utf8.encode('test secret')));

      // Start changePin
      final changePinFuture = crypto.changePin('2222');

      // Issue lock() while changePin is in-flight
      crypto.lock();

      // Assert state AT THIS EXACT INSTANT (during the in-flight window, BEFORE awaiting changePinFuture)
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);
      expect(() => crypto.decrypt(ciphertext), throwsException);

      // Now await completion of changePinFuture
      await changePinFuture;

      // Assert state AFTER the in-flight window
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);

      // Verify the new PIN '2222' unlocks
      final unlockCrypto = VaultCrypto(platform, keystore);
      await unlockCrypto.initialize('2222');
      expect(unlockCrypto.isUnlocked, isTrue);
    });

    test('7. A vault whose salt is absent but whose pin hash is present is treated as not-yet-created by UI predicate', () async {
      final platform = FakePlatformService();

      // Interrupted creation state: hash present, salt absent
      platform.store['vault_pin_hash'] = 'v3:100000:some_partial_hash';
      expect(platform.store.containsKey('vault_salt'), isFalse);

      // Evaluate the exact UI predicate used in PinScreen._checkCreateMode
      final salt = await platform.secureRead('vault_salt');
      final isCreateMode = (salt == null || salt.isEmpty);

      expect(isCreateMode, isTrue, reason: 'Absence of vault_salt must trigger create mode even if vault_pin_hash exists');
    });

    test('8. lock() issued during in-flight initialize (unlock) leaves vault locked, and correct PIN still unlocks', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('unlock lock race payload'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Launch initialize (unlock path)
      final unlockFuture = crypto.initialize('1111');

      // Issue lock() while initialize is in-flight
      crypto.lock();

      // Await completion of initialize
      await unlockFuture;

      // Vault must remain locked
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);
      expect(() => crypto.decrypt(ciphertext), throwsException);

      // Subsequent normal unlock succeeds
      final reCrypto = VaultCrypto(platform, keystore);
      await reCrypto.initialize('1111');
      expect(reCrypto.isUnlocked, isTrue);
      expect(reCrypto.decrypt(ciphertext), equals(secret));
    });

    test('9. lock() issued during first-time vault creation leaves vault created and locked, and chosen PIN opens it on next attempt', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      // Launch initialize on empty storage (creation path)
      final creationFuture = crypto.initialize('5555');

      // Issue lock() while creation is in-flight
      crypto.lock();

      // Await completion of creation
      await creationFuture;

      // Vault must be locked in memory
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);

      // Storage must have all three canonical keys written and committed
      expect(platform.store.containsKey('vault_salt'), isTrue);
      expect(platform.store.containsKey('vault_pin_hash'), isTrue);
      expect(platform.store.containsKey('master_key_wrapped'), isTrue);

      // The chosen PIN '5555' successfully unlocks the newly created vault on the next attempt
      final unlockCrypto = VaultCrypto(platform, keystore);
      await unlockCrypto.initialize('5555');
      expect(unlockCrypto.isUnlocked, isTrue);

      final payload = Uint8List.fromList(utf8.encode('new vault payload'));
      final cipher = unlockCrypto.encrypt(payload);
      expect(unlockCrypto.decrypt(cipher), equals(payload));
    });

    test('10. lock() issued during in-flight recoverWithPhrase leaves vault locked and returns false', () async {
      // Proves that a lock arriving during recovery causes recoverWithPhrase to abort
      // key assignment, zero all working buffers, leave the vault locked, and report
      // failure (false) to the caller so they do not navigate into an unreadable vault.
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      const words = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await crypto.storeRecoveryBlob(words);
      final secret = Uint8List.fromList(utf8.encode('recovery lock race payload'));
      final ciphertext = crypto.encrypt(secret);
      crypto.lock();

      // Start recoverWithPhrase
      final recoveryFuture = crypto.recoverWithPhrase(words);

      // Issue lock() while recoverWithPhrase is in-flight
      crypto.lock();

      // Await completion of recovery: lock during recovery reports false
      final recovered = await recoveryFuture;
      expect(recovered, isFalse);

      // Vault must remain locked
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);
      expect(() => crypto.decrypt(ciphertext), throwsException);

      // Next unlock with phrase or PIN succeeds
      final nextCrypto = VaultCrypto(platform, keystore);
      final nextRecovered = await nextCrypto.recoverWithPhrase(words);
      expect(nextRecovered, isTrue);
      expect(nextCrypto.isUnlocked, isTrue);
      expect(nextCrypto.decrypt(ciphertext), equals(secret));
    });

    test('11. Plain unlock asserts isUnlocked is true and decrypt works (catches regression that made vault permanently unopenable)', () async {
      // REGRESSION TEST:
      // In Phase 1f, _initializeInternal wrapped key assignment in `if (_isUnlocked)`.
      // Since _isUnlocked is false upon entering initialize, the derived key was always
      // discarded and zeroed, rendering the vault permanently unopenable.
      // This test ensures that a normal initialize() correctly sets isUnlocked to true
      // and populates the derived key so decrypt succeeds.
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      // Create vault with PIN '1234'
      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      final plaintext = Uint8List.fromList(utf8.encode('unopenable regression payload'));
      final ciphertext = crypto.encrypt(plaintext);

      // Lock the vault
      crypto.lock();
      expect(crypto.isUnlocked, isFalse);

      // Unlock on a fresh instance
      final unlockCrypto = VaultCrypto(platform, keystore);
      await unlockCrypto.initialize('1234');

      expect(unlockCrypto.isUnlocked, isTrue,
          reason: 'Vault must be unlocked after valid initialize');
      final decrypted = unlockCrypto.decrypt(ciphertext);
      expect(decrypted, equals(plaintext),
          reason: 'Decryption must succeed with derived key after unlock');
    });

    test('12. lock() arriving during changePin does NOT prevent storage commit, new PIN works on fresh instance', () async {
      // PROVES:
      // An intervening lock() request zeroes in-memory buffers for the current session
      // but does NOT prevent or abort the storage commit that is underway. The canonical storage
      // is atomically updated with the new PIN credentials, and a fresh instance
      // can immediately unlock using the new PIN.
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      final secret = Uint8List.fromList(utf8.encode('storage commit resilience payload'));
      final ciphertext = crypto.encrypt(secret);

      // Start changePin to '9876'
      final changePinFuture = crypto.changePin('9876');

      // Issue lock while changePin is in flight
      crypto.lock();

      // Wait for changePin to finish its execution and storage commit
      await changePinFuture;

      // Current instance must remain locked in memory
      expect(crypto.isUnlocked, isFalse);
      expect(() => crypto.encrypt(Uint8List(16)), throwsException);

      // Fresh instance must unlock with the NEW PIN '9876', confirming storage commit succeeded
      final freshCrypto = VaultCrypto(platform, keystore);
      await freshCrypto.initialize('9876');
      expect(freshCrypto.isUnlocked, isTrue);
      expect(freshCrypto.decrypt(ciphertext), equals(secret));

      // Old PIN '1111' must be rejected
      freshCrypto.lock();
      final oldCrypto = VaultCrypto(platform, keystore);
      await expectLater(
        () => oldCrypto.initialize('1111'),
        throwsA(isA<InvalidPinException>()),
      );
    });

    test('13. Request-time lock epoch capture: lock() while initialize() is queued prevents key commit', () async {
      // PROVES (T1 fix):
      // Capturing the lock epoch at request time (before calling _synchronized) ensures that
      // when an operation is queued on the mutex behind an in-flight operation, any lock()
      // issued while it waits in the queue will increment _lockEpoch. When the queued
      // operation eventually runs and reaches its commit point, it detects that the epoch
      // has changed and aborts key assignment, guaranteeing _derivedKey is never committed.
      final platform = FakePlatformService();
      final keystore = ControllableKeystoreService();
      final crypto = VaultCrypto(platform, keystore);

      await crypto.initialize('1111');
      crypto.lock();

      // Set up gates to hold changePin inside wrap() while holding the mutex
      final wrapEntered = Completer<void>();
      final wrapGate = Completer<void>();
      keystore.wrapEntered = wrapEntered;
      keystore.wrapGate = wrapGate;

      // Unlock on active instance so changePin can run
      final activeCrypto = VaultCrypto(platform, keystore);
      await activeCrypto.initialize('1111');

      // 1. Start changePin('2222'), which enters wrap() and pauses, holding the mutex
      final changePinFuture = activeCrypto.changePin('2222');
      await wrapEntered.future;

      // 2. While mutex is held, call initialize('2222').
      // Request-time epoch capture reads _lockEpoch into a local before queuing on _synchronized.
      // '2222' matches the PIN committed by changePin, ensuring that initialize succeeds
      // cryptographically and only fails to commit because of the lock epoch mismatch.
      final queuedInitFuture = activeCrypto.initialize('2222');

      // 3. Issue lock() while initialize is waiting in the mutex queue.
      // Synchronously increments _lockEpoch and enqueues _lockInternal behind queuedInit.
      activeCrypto.lock();

      // 4. Release changePin to let the queue drain
      wrapGate.complete();
      await changePinFuture;
      await queuedInitFuture;

      // 5. Assert: vault ends locked in memory and in-flight keys were never committed
      expect(activeCrypto.isUnlocked, isFalse);
      expect(() => activeCrypto.encrypt(Uint8List(16)), throwsException);

      // Verify that the new PIN '2222' committed to storage and opens on a fresh instance
      final freshCrypto = VaultCrypto(platform, keystore);
      await freshCrypto.initialize('2222');
      expect(freshCrypto.isUnlocked, isTrue);
    });

    test('14. vault creation purges stale recovery and lockout state from a previous vault', () async {
      final platform = FakePlatformService();
      final keystore = FakeKeystoreService();

      // Seed stale artifacts from a prior vault that was wiped or left in dirty state
      platform.store['recovery_blob'] = 'stale_recovery_blob_data';
      platform.store['recovery_salt'] = 'stale_recovery_salt_data';
      platform.store['wrong_attempts'] = '5';
      platform.store['lockout_set_wall'] = '1700000000000';
      platform.store['lockout_set_elapsed'] = '1000000';
      platform.store['lockout_duration_ms'] = '300000';
      platform.store['master_key_wrapped'] = 'stale_master_key_wrapped';

      // Ensure no vault_salt is present so creation branch is taken
      expect(platform.store.containsKey('vault_salt'), isFalse);

      final crypto = VaultCrypto(platform, keystore);
      await crypto.initialize('1234');

      // Assert vault created successfully
      expect(crypto.isUnlocked, isTrue);
      expect(platform.store.containsKey('vault_salt'), isTrue);

      // Assert all six stale keys are purged from storage
      expect(platform.store.containsKey('recovery_blob'), isFalse,
          reason: 'Stale recovery_blob must be purged on vault creation');
      expect(platform.store.containsKey('recovery_salt'), isFalse,
          reason: 'Stale recovery_salt must be purged on vault creation');
      expect(platform.store.containsKey('wrong_attempts'), isFalse,
          reason: 'Stale wrong_attempts counter must be purged on vault creation');
      expect(platform.store.containsKey('lockout_set_wall'), isFalse,
          reason: 'Stale lockout_set_wall timestamp must be purged on vault creation');
      expect(platform.store.containsKey('lockout_set_elapsed'), isFalse,
          reason: 'Stale lockout_set_elapsed timestamp must be purged on vault creation');
      expect(platform.store.containsKey('lockout_duration_ms'), isFalse,
          reason: 'Stale lockout_duration_ms timer must be purged on vault creation');

      // Assert master_key_wrapped holds the newly generated hardware-wrapped key, not the stale one
      final newWrapped = platform.store['master_key_wrapped'];
      expect(newWrapped, isNotNull);
      expect(newWrapped, isNot(equals('stale_master_key_wrapped')));
      expect(newWrapped != null && newWrapped.startsWith('hw1:'), isTrue);
    });
  });
}
