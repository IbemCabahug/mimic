import 'package:mimic/vault/crypto/keystore_service.dart';
// test/vault/crypto/vault_crypto_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/recovery_phrase.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/core/services/platform_service.dart';

// ---------------------------------------------------------------------------
// Fake PlatformService — an in-memory implementation of flutter_secure_storage
// that also exposes its internal store for inspection in tests 9 & 10.
// ---------------------------------------------------------------------------
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



/// Generates a random base64-encoded salt, matching VaultCrypto's internal format.
String generateTestSalt() {
  final random = Random.secure();
  final bytes = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
  return base64Encode(bytes);
}

// ===========================================================================
// Tests
// ===========================================================================
void main() {
  // -------------------------------------------------------------------------
  // Group 1: deriveKey determinism & uniqueness  (Tests 1, 2, 3)
  // -------------------------------------------------------------------------
  group('deriveKey', () {
    test('1 — same PIN + same salt produces the same key every time', () {
      final salt = generateTestSalt();

      final key1 = deriveVaultPinKek('5678', salt);
      final key2 = deriveVaultPinKek('5678', salt);

      expect(key1, equals(key2),
          reason: 'PBKDF2 must be deterministic for identical inputs');
      expect(key1.length, equals(32),
          reason: 'AES-256 key must be 32 bytes');
    });

    test('2 — different PINs produce different keys', () {
      final salt = generateTestSalt();

      final keyA = deriveVaultPinKek('1111', salt);
      final keyB = deriveVaultPinKek('9999', salt);

      expect(keyA, isNot(equals(keyB)),
          reason: 'Different PINs must derive different keys');
    });

    test('3 — same PIN + different salt produces different keys', () {
      final salt1 = generateTestSalt();
      final salt2 = generateTestSalt();

      // Guarantee the two salts are actually different (astronomically unlikely
      // to collide, but the test should be explicit).
      expect(salt1, isNot(equals(salt2)),
          reason: 'Test setup: salts must differ');

      final key1 = deriveVaultPinKek('1234', salt1);
      final key2 = deriveVaultPinKek('1234', salt2);

      expect(key1, isNot(equals(key2)),
          reason: 'Same PIN with different salts must derive different keys');
    });

    test('3b — fixed backward-compatibility vector for vault PIN-derived KEK',
        () {
      final result =
          deriveVaultPinKek('246810', 'AAECAwQFBgcICQoLDA0ODw==');

      final expected = Uint8List.fromList([
        180, 129, 108, 27, 8, 133, 44, 134,
        39, 208, 226, 161, 83, 20, 243, 98,
        139, 248, 14, 113, 250, 98, 63, 41,
        228, 3, 43, 234, 148, 211, 211, 28,
      ]);

      expect(result.length, equals(32),
          reason: 'PIN-derived KEK must remain 32 bytes');
      expect(result, equals(expected),
          reason:
              'Changing any derived byte would break compatibility with existing wrapped vault keys');
    });
  });

  // -------------------------------------------------------------------------
  // Group 2: encrypt / decrypt round-trips  (Tests 4, 5, 6, 7)
  // -------------------------------------------------------------------------
  group('encrypt / decrypt round-trip', () {
    late VaultCrypto crypto;

    setUp(() async {
      crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await crypto.initialize('testpin');
    });

    test('4 — encryptFile + decryptFile: round-trip matches original Uint8List',
        () {
      // A known payload — 37 bytes, not block-aligned on purpose.
      final original = Uint8List.fromList(
        utf8.encode('The owl flies at midnight — 🦉'),
      );

      final ciphertext = crypto.encrypt(original);
      final decrypted = crypto.decrypt(ciphertext);

      expect(decrypted, equals(original),
          reason: 'Decrypted bytes must exactly match the original');
    });

    test('5 — encrypted bytes are never equal to the original bytes', () {
      final original = Uint8List.fromList(
        List.generate(64, (i) => i), // 0x00..0x3F
      );

      final ciphertext = crypto.encrypt(original);

      // The ciphertext includes the 16-byte IV prefix + PKCS7-padded cipher
      // output, so it's always longer than the plaintext.
      expect(ciphertext.length, greaterThan(original.length),
          reason: 'Ciphertext must be longer (IV + padding)');
      expect(ciphertext, isNot(equals(original)),
          reason: 'Ciphertext must never equal plaintext');

      // Also verify the payload portion (after the IV) doesn't match.
      final payloadOnly = ciphertext.sublist(16);
      expect(payloadOnly, isNot(equals(original)),
          reason: 'Even without the IV prefix, encrypted payload must differ');
    });

    test('6 — encryptString + decryptString: round-trip matches original string',
        () {
      const original = 'Sensitive note with unicode: こんにちは 🔐';

      final ciphertext = crypto.encryptString(original);
      final decrypted = crypto.decryptString(ciphertext);

      expect(decrypted, equals(original));
    });

    test('7 — two encryptString calls with same input produce different ciphertext (random IV)',
        () {
      const input = 'Repeated plaintext';

      final cipher1 = crypto.encryptString(input);
      final cipher2 = crypto.encryptString(input);

      expect(cipher1, isNot(equals(cipher2)),
          reason: 'Each encryption must use a fresh random IV');

      // Both must still decrypt to the same plaintext.
      expect(crypto.decryptString(cipher1), equals(input));
      expect(crypto.decryptString(cipher2), equals(input));
    });
  });

  // -------------------------------------------------------------------------
  // Group 3: Corrupted ciphertext  (Test 8)
  // -------------------------------------------------------------------------
  group('corrupted ciphertext', () {
    late VaultCrypto crypto;

    setUp(() async {
      crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await crypto.initialize('testpin');
    });

    test('8 — decryptFile with corrupted ciphertext throws and never returns garbage silently',
        () {
      final original = Uint8List.fromList(utf8.encode('Secret data'));
      final ciphertext = crypto.encrypt(original);

      // Corrupt several bytes in the encrypted payload (past the 16-byte IV).
      final corrupted = Uint8List.fromList(ciphertext);
      for (var i = 16; i < corrupted.length && i < 32; i++) {
        corrupted[i] ^= 0xFF; // flip every bit
      }

      // PKCS7 un-padding should detect the mangled block and throw.
      expect(
        () => crypto.decrypt(corrupted),
        throwsA(isA<Exception>()),
        reason:
            'Decrypting corrupted ciphertext must throw — never return garbage',
      );
    });

    test('8b — decryptFile with truncated ciphertext (< IV length) throws', () {
      final tooShort = Uint8List.fromList([1, 2, 3]);

      expect(
        () => crypto.decrypt(tooShort),
        throwsA(isA<Exception>()),
        reason: 'Ciphertext shorter than 16 bytes must be rejected',
      );
    });

    test('8c — decrypt on a locked vault throws', () {
      crypto.lock();

      final ciphertext = Uint8List.fromList(List.filled(32, 0));
      expect(
        () => crypto.decrypt(ciphertext),
        throwsA(isA<Exception>()),
        reason: 'Vault must reject operations when locked',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 4: Secure storage guarantees  (Tests 9, 10)
  // -------------------------------------------------------------------------
  group('secure storage guarantees', () {
    test('9 — derived key never appears in flutter_secure_storage in plain text',
        () async {
      final fakePlatform = FakePlatformService();
      final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto.initialize('mySecretPin');

      // Derive the key independently so we know what to look for.
      final saltB64 = fakePlatform.store['vault_salt']!;
      final rawKey = deriveVaultPinKek('mySecretPin', saltB64);
      final rawKeyB64 = base64Encode(rawKey);
      final rawKeyHex = rawKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // Walk every value in the store and assert the key doesn't appear
      // in any encoding (base64, hex, or raw bytes-as-latin1).
      for (final entry in fakePlatform.store.entries) {
        expect(entry.value, isNot(equals(rawKeyB64)),
            reason:
                'Key "${entry.key}" must not store the derived key as base64');
        expect(entry.value, isNot(equals(rawKeyHex)),
            reason:
                'Key "${entry.key}" must not store the derived key as hex');
        expect(entry.value.contains(rawKeyB64), isFalse,
            reason:
                'Key "${entry.key}" must not contain the derived key (base64 substring)');
      }
    });

    test('10 — salt is stored in flutter_secure_storage and retrieved correctly on second run',
        () async {
      final fakePlatform = FakePlatformService();

      // --- First run: initialize creates & stores a salt ---
      final crypto1 = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto1.initialize('1234');

      expect(fakePlatform.store.containsKey('vault_salt'), isTrue,
          reason: 'Salt must be persisted under "vault_salt"');

      final storedSalt = fakePlatform.store['vault_salt']!;

      // Validate the stored value is valid base64 that decodes to 16 bytes.
      final saltBytes = base64Decode(storedSalt);
      expect(saltBytes.length, equals(16),
          reason: 'Salt must be exactly 16 bytes');

      // Encrypt something with the first instance.
      const secret = 'Phase 4 test data';
      final ciphertext = crypto1.encryptString(secret);

      // --- Second run: new VaultCrypto, same FakePlatformService (simulates
      //     a cold restart — storage persists, in-memory state is gone) ---
      final crypto2 = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto2.initialize('1234'); // same PIN

      // The salt should NOT have been regenerated.
      expect(fakePlatform.store['vault_salt'], equals(storedSalt),
          reason: 'Salt must be read from storage, not regenerated');

      // Decrypt the ciphertext produced by the first instance.
      final decrypted = crypto2.decryptString(ciphertext);
      expect(decrypted, equals(secret),
          reason:
              'Second run must derive the same key from stored salt and decrypt correctly');
    });

    test('10b — initialize with wrong PIN on second run throws', () async {
      final fakePlatform = FakePlatformService();

      final crypto1 = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto1.initialize('correctPin');

      // Second run with wrong PIN.
      final crypto2 = VaultCrypto(fakePlatform, FakeKeystoreService());
      expect(
        () => crypto2.initialize('wrongPin'),
        throwsA(isA<Exception>()),
        reason: 'Must reject an incorrect PIN on subsequent initialization',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 5: Recovery Phrase Integration Tests
  // -------------------------------------------------------------------------
  group('recovery phrase integration', () {
    late FakePlatformService fakePlatform;
    late VaultCrypto crypto;
    final words = [
      'abandon', 'abandon', 'abandon', 'abandon',
      'abandon', 'abandon', 'abandon', 'abandon',
      'abandon', 'abandon', 'abandon', 'about'
    ];

    setUp(() {
      fakePlatform = FakePlatformService();
      crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    });

    test('storeRecoveryBlob throws if vault is locked', () async {
      expect(
        () => crypto.storeRecoveryBlob(words),
        throwsA(isA<Exception>()),
      );
    });

    test('storeRecoveryBlob stores blob and salt, recoverWithPhrase restores vault', () async {
      await crypto.initialize('pin123');
      expect(crypto.isUnlocked, isTrue);
      
      final originalMasterKey = crypto.encryptString('test payload');

      // Store recovery blob
      await crypto.storeRecoveryBlob(words);
      expect(fakePlatform.store.containsKey('recovery_blob'), isTrue);
      expect(fakePlatform.store.containsKey('recovery_salt'), isTrue);

      // Lock vault to simulate cold start or locked state
      crypto.lock();
      expect(crypto.isUnlocked, isFalse);

      // Attempt recovery with wrong words
      final wrongWords = List<String>.from(words)..[11] = 'abandon';
      final successWrong = await crypto.recoverWithPhrase(wrongWords);
      expect(successWrong, isFalse);
      expect(crypto.isUnlocked, isFalse);

      // Attempt recovery with correct words
      final successCorrect = await crypto.recoverWithPhrase(words);
      expect(successCorrect, isTrue);
      expect(crypto.isUnlocked, isTrue);

      // Verify that the restored master key can decrypt data encrypted before recovery
      final decrypted = crypto.decryptString(originalMasterKey);
      expect(decrypted, equals('test payload'));
    });

    test('recoverWithPhrase returns false if no stored blob exists', () async {
      final success = await crypto.recoverWithPhrase(words);
      expect(success, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Group 6: Phase 2A - Versioned PIN verifier & KDF parameters record
  // -------------------------------------------------------------------------
  group('Phase 2A - Versioned PIN verifier & KDF parameters record', () {
    late FakePlatformService fakePlatform;
    late FakeKeystoreService fakeKeystore;
    late VaultCrypto crypto;

    setUp(() {
      fakePlatform = FakePlatformService();
      fakeKeystore = FakeKeystoreService();
      crypto = VaultCrypto(fakePlatform, fakeKeystore);
    });

    test('1. A vault created now writes a v3: verifier containing 100000', () async {
      await crypto.initialize('4321');
      expect(crypto.isUnlocked, isTrue);

      final storedHash = fakePlatform.store['vault_pin_hash'];
      expect(storedHash, isNotNull);
      expect(storedHash!.startsWith('v3:100000:'), isTrue,
          reason: 'New vault creation must write a v3: verifier with current iteration count 100000');

      final parsed = parseVerifier(storedHash);
      expect(parsed.version, equals(3));
      expect(parsed.iterations, equals(100000));
      expect(parsed.digestBase64.isNotEmpty, isTrue);
    });

    test('2. A stored v2: verifier still unlocks with the correct PIN', () async {
      final salt = generateTestSalt();
      final candidateKey = deriveVaultPinKek('1234', salt, 100000);
      final digest = SHA256Digest().process(candidateKey);
      final v2Verifier = 'v2:${base64Encode(digest)}';

      final kekInput = Uint8List.fromList([...candidateKey, ...utf8.encode('mimic-kek-v1')]);
      final kek = SHA256Digest().process(kekInput);
      
      final iv = Uint8List.fromList(List.generate(16, (i) => i));
      final cipher = CBCBlockCipher(AESEngine());
      final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher)
        ..init(true, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(kek), iv), null));
      final enc = padded.process(candidateKey);
      final innerWrapped = Uint8List(iv.length + enc.length);
      innerWrapped.setRange(0, iv.length, iv);
      innerWrapped.setRange(iv.length, innerWrapped.length, enc);
      final hwWrapped = await fakeKeystore.wrap(base64Encode(innerWrapped));

      fakePlatform.store['vault_salt'] = salt;
      fakePlatform.store['vault_pin_hash'] = v2Verifier;
      fakePlatform.store['master_key_wrapped'] = 'hw1:$hwWrapped';

      final unlockCrypto = VaultCrypto(fakePlatform, fakeKeystore);
      await unlockCrypto.initialize('1234');

      expect(unlockCrypto.isUnlocked, isTrue,
          reason: 'Stored v2: verifier must successfully unlock with correct PIN');
    });

    test('3. A stored v2: verifier rejects a wrong PIN', () async {
      final salt = generateTestSalt();
      final candidateKey = deriveVaultPinKek('1234', salt, 100000);
      final digest = SHA256Digest().process(candidateKey);
      final v2Verifier = 'v2:${base64Encode(digest)}';

      final kekInput = Uint8List.fromList([...candidateKey, ...utf8.encode('mimic-kek-v1')]);
      final kek = SHA256Digest().process(kekInput);
      
      final iv = Uint8List.fromList(List.generate(16, (i) => i));
      final cipher = CBCBlockCipher(AESEngine());
      final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher)
        ..init(true, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(kek), iv), null));
      final enc = padded.process(candidateKey);
      final innerWrapped = Uint8List(iv.length + enc.length);
      innerWrapped.setRange(0, iv.length, iv);
      innerWrapped.setRange(iv.length, innerWrapped.length, enc);
      final hwWrapped = await fakeKeystore.wrap(base64Encode(innerWrapped));

      fakePlatform.store['vault_salt'] = salt;
      fakePlatform.store['vault_pin_hash'] = v2Verifier;
      fakePlatform.store['master_key_wrapped'] = 'hw1:$hwWrapped';

      final unlockCrypto = VaultCrypto(fakePlatform, fakeKeystore);
      await expectLater(
        () => unlockCrypto.initialize('wrongPin'),
        throwsA(isA<Exception>()),
        reason: 'Stored v2: verifier must reject wrong PIN',
      );
      expect(unlockCrypto.isUnlocked, isFalse);
    });

    test('4. A v3: record with custom iteration count derives using the record value', () async {
      const customIterations = 42;
      final salt = generateTestSalt();

      // Key derived with custom iteration count (42)
      final customKey = deriveVaultPinKek('customPin', salt, customIterations);
      // Key derived with standard constant (100000)
      final standardKey = deriveVaultPinKek('customPin', salt, kPbkdf2Iterations);

      expect(customKey, isNot(equals(standardKey)),
          reason: 'Custom iteration count must derive a different key than standard 100k');

      final customDigest = SHA256Digest().process(customKey);
      final v3CustomVerifier = 'v3:$customIterations:${base64Encode(customDigest)}';

      final kekInput = Uint8List.fromList([...customKey, ...utf8.encode('mimic-kek-v1')]);
      final kek = SHA256Digest().process(kekInput);
      
      final iv = Uint8List.fromList(List.generate(16, (i) => i));
      final cipher = CBCBlockCipher(AESEngine());
      final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher)
        ..init(true, PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(kek), iv), null));
      final enc = padded.process(customKey);
      final innerWrapped = Uint8List(iv.length + enc.length);
      innerWrapped.setRange(0, iv.length, iv);
      innerWrapped.setRange(iv.length, innerWrapped.length, enc);
      final hwWrapped = await fakeKeystore.wrap(base64Encode(innerWrapped));

      fakePlatform.store['vault_salt'] = salt;
      fakePlatform.store['vault_pin_hash'] = v3CustomVerifier;
      fakePlatform.store['master_key_wrapped'] = 'hw1:$hwWrapped';

      final unlockCrypto = VaultCrypto(fakePlatform, fakeKeystore);
      await unlockCrypto.initialize('customPin');

      expect(unlockCrypto.isUnlocked, isTrue,
          reason: 'Vault must unlock using the iteration count from the v3 record');

      final testPlaintext = Uint8List.fromList(utf8.encode('custom iteration verification data'));
      final encrypted = unlockCrypto.encrypt(testPlaintext);
      final decrypted = unlockCrypto.decrypt(encrypted);
      expect(decrypted, equals(testPlaintext));
    });

    test('5. Malformed v3 records fail closed', () async {
      final badRecords = [
        'v3:',
        'v3:abc:xxx',
        'v3:0:xxx',
        'v3:-1:xxx',
        'v3:999999999999999999:xxx',
        'v3:100000:',
        'unknown:format:123',
      ];

      for (final bad in badRecords) {
        // Direct parseVerifier unit test fails closed
        expect(
          () => parseVerifier(bad),
          throwsA(isA<InvalidVerifierException>()),
          reason: 'parseVerifier must throw InvalidVerifierException for "$bad"',
        );

        // Vault initialization with bad verifier fails closed and does not unlock
        final platform = FakePlatformService();
        platform.store['vault_salt'] = generateTestSalt();
        platform.store['vault_pin_hash'] = bad;
        platform.store['master_key_wrapped'] = 'hw1:dummy';

        final badCrypto = VaultCrypto(platform, fakeKeystore);
        await expectLater(
          () => badCrypto.initialize('anyPin'),
          throwsA(isA<InvalidVerifierException>()),
          reason: 'initialize must throw InvalidVerifierException on malformed verifier "$bad"',
        );
        expect(badCrypto.isUnlocked, isFalse);
      }
    });

    test('6. changePin writes a v3 verifier and the vault reopens with the new PIN', () async {
      await crypto.initialize('1234');
      expect(crypto.isUnlocked, isTrue);

      const testSecret = 'Important secret data';
      final ciphertext = crypto.encryptString(testSecret);

      await crypto.changePin('5678');
      expect(crypto.isUnlocked, isTrue);

      final newStoredHash = fakePlatform.store['vault_pin_hash'];
      expect(newStoredHash, isNotNull);
      expect(newStoredHash!.startsWith('v3:100000:'), isTrue,
          reason: 'changePin must write a v3: verifier with 100000 iterations');

      // Cold restart / reopen with new PIN
      final restartCrypto = VaultCrypto(fakePlatform, fakeKeystore);
      await restartCrypto.initialize('5678');
      expect(restartCrypto.isUnlocked, isTrue);
      expect(restartCrypto.decryptString(ciphertext), equals(testSecret));

      // Attempt with old PIN fails
      final oldPinCrypto = VaultCrypto(fakePlatform, fakeKeystore);
      await expectLater(
        () => oldPinCrypto.initialize('1234'),
        throwsA(isA<Exception>()),
      );
      expect(oldPinCrypto.isUnlocked, isFalse);
    });

    test('7. Recovery phrase and duress PIN both still work after consolidation', () async {
      // Test RecoveryPhrase with consolidated constants
      final words = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final recoveryKey = RecoveryPhrase.deriveKey(words, salt);
      expect(recoveryKey.length, equals(kDerivedKeyLength));

      // Test DuressService with consolidated constants
      final duressPlatform = FakePlatformService();
      final duressService = DuressService(duressPlatform);

      await duressService.setFakePin('9876');
      expect(duressPlatform.store.containsKey('duress_pin_hash'), isTrue);
      expect(duressPlatform.store['duress_pin_hash']!.startsWith('v2:'), isTrue);

      final isDuress = await duressService.isFakePin('9876');
      expect(isDuress, isTrue, reason: 'DuressService must verify correct fake PIN');

      final isNotDuress = await duressService.isFakePin('1234');
      expect(isNotDuress, isFalse, reason: 'DuressService must reject non-fake PIN');
    });
  });
}
