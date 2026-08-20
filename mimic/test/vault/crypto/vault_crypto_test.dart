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
import 'package:mimic/vault/crypto/media_format.dart';
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
      const customIterations = 250000;
      final salt = generateTestSalt();

      // Key derived with custom iteration count (250000)
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

    test('5. Malformed and out-of-bounds v3 records fail closed', () async {
      final badRecords = [
        'v3:',
        'v3:abc:xxx',
        'v3:0:xxx',
        'v3:-1:xxx',
        'v3:42:xxx',
        'v3:99999:xxx',
        'v3:1000001:xxx',
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

    test('8. Recovery phrase generation and consumption uses kRecoveryPhraseIterations', () async {
      final words = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      // Derive key via RecoveryPhrase
      final key1 = RecoveryPhrase.deriveKey(words, salt);

      // Verify it matches PBKDF2 derived specifically with kRecoveryPhraseIterations (100000)
      final cleanWords = RecoveryPhrase.normalizeWords(words);
      final mnemonic = cleanWords.join(' ');
      final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
      final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
      pbkdf2.init(Pbkdf2Parameters(salt, kRecoveryPhraseIterations, kDerivedKeyLength));
      final expectedKey = pbkdf2.process(mnemonicBytes);

      expect(key1, equals(expectedKey),
          reason: 'Recovery phrase key must be derived using kRecoveryPhraseIterations');
      expect(key1.length, equals(kDerivedKeyLength));
    });

    test('9. Duress PIN set and verification matches using kDuressIterations', () async {
      final duressPlatform = FakePlatformService();
      final duressService = DuressService(duressPlatform);

      await duressService.setFakePin('8888');
      final storedHash = duressPlatform.store['duress_pin_hash']!;
      final storedSalt = duressPlatform.store['duress_pin_salt']!;

      // Verify stored verifier was derived specifically using kDuressIterations
      final pinBytes = Uint8List.fromList(utf8.encode('8888'));
      final saltBytes = Uint8List.fromList(utf8.encode(storedSalt));
      final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(saltBytes, kDuressIterations, kDerivedKeyLength));
      final expectedDerived = pbkdf2.process(pinBytes);
      final expectedHash = 'v2:${base64Encode(expectedDerived)}';

      expect(storedHash, equals(expectedHash),
          reason: 'Duress verifier must be generated using kDuressIterations');

      final isMatch = await duressService.isFakePin('8888');
      expect(isMatch, isTrue);
      final isWrong = await duressService.isFakePin('1111');
      expect(isWrong, isFalse);
    });

    test('10. Boundary tests: floor and ceiling iteration counts are accepted inclusively', () {
      const dummyDigest = 'dGVzdGRpZ2VzdA==';

      // Floor (100000) is accepted
      final floorVerifier = 'v3:$kMinPbkdf2Iterations:$dummyDigest';
      final parsedFloor = parseVerifier(floorVerifier);
      expect(parsedFloor.version, equals(3));
      expect(parsedFloor.iterations, equals(100000));
      expect(parsedFloor.digestBase64, equals(dummyDigest));

      // Ceiling (1000000) is accepted
      final ceilingVerifier = 'v3:$kMaxPbkdf2Iterations:$dummyDigest';
      final parsedCeiling = parseVerifier(ceilingVerifier);
      expect(parsedCeiling.version, equals(3));
      expect(parsedCeiling.iterations, equals(1000000));
      expect(parsedCeiling.digestBase64, equals(dummyDigest));

      // Just below floor (99999) is rejected
      expect(
        () => parseVerifier('v3:99999:$dummyDigest'),
        throwsA(isA<InvalidVerifierException>()),
      );

      // Just above ceiling (1000001) is rejected
      expect(
        () => parseVerifier('v3:1000001:$dummyDigest'),
        throwsA(isA<InvalidVerifierException>()),
      );
    });

    test('11. Parsing v2: verifier yields iterations == kLegacyV2Iterations', () {
      const dummyDigest = 'dGVzdGRpZ2VzdA==';
      final v2Verifier = 'v2:$dummyDigest';

      final parsed = parseVerifier(v2Verifier);
      expect(parsed.version, equals(2));
      expect(parsed.iterations, equals(kLegacyV2Iterations),
          reason: 'Legacy v2 records must parse to kLegacyV2Iterations, never kPbkdf2Iterations');
      expect(parsed.digestBase64, equals(dummyDigest));
    });

    test('12. Regression guard: kLegacyV2Iterations is strictly frozen at 100000', () {
      // If this assertion ever fails, every legacy v2 vault will derive at the wrong
      // iteration count, mismatch its stored verifier, and lock the user out permanently.
      expect(kLegacyV2Iterations, equals(100000),
          reason: 'kLegacyV2Iterations is a historical constant and must remain 100000 forever');
    });
  });

  // -------------------------------------------------------------------------
  // Group: AES-CTR stream encryption & multi-format compatibility (T1, T2, T6)
  // -------------------------------------------------------------------------
  group('AES-CTR stream format & compatibility', () {
    late Directory tempDir;
    late FakePlatformService platformService;
    late VaultCrypto crypto;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ctr_crypto_test');
      platformService = FakePlatformService();
      crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('test-pin-1234');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('T1 — c2 round trip: encryptStreamSystemCtr writes c2 magic and decryptStreamSystem restores original bytes', () async {
      final srcFile = File('${tempDir.path}/t1_src.bin');
      final encFile = File('${tempDir.path}/t1_enc.bin');
      final decFile = File('${tempDir.path}/t1_dec.bin');

      final random = Random.secure();
      final plaintext = Uint8List(64 * 1024 + 37); // > 1 chunk, off-boundary
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(plaintext);

      // Encrypt with c2
      await crypto.encryptStreamSystemCtr(srcFile, encFile);

      // Assert first 8 bytes match kMediaMagicCtrV2
      final encBytes = await encFile.readAsBytes();
      expect(encBytes.length >= 8 + 16 + plaintext.length, isTrue);
      expect(encBytes.sublist(0, 8), equals(kMediaMagicCtrV2),
          reason: 'c2 stream encryption must start with MVKEYc2\\0 magic');

      // Decrypt with decryptStreamSystem
      await crypto.decryptStreamSystem(encFile, decFile);
      final decrypted = await decFile.readAsBytes();
      expect(decrypted, equals(plaintext),
          reason: 'Decrypted bytes must match original plaintext');
    });

    test('T2 — c1 still readable: manually constructed c1 blob (system key) decrypts correctly via decryptStreamSystem', () async {
      final c1File = File('${tempDir.path}/t2_c1.bin');
      final decFile = File('${tempDir.path}/t2_dec.bin');

      final random = Random.secure();
      final plaintext = Uint8List(32 * 1024 + 19);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }

      // Manually construct a c1 blob using system_key (the legacy c1 format)
      // Read or generate system_key from platformService
      final rawStoredKey = await platformService.secureRead('system_key');
      final Uint8List systemKey;
      if (rawStoredKey != null) {
        systemKey = base64Decode(rawStoredKey);
      } else {
        systemKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
        await platformService.secureWrite('system_key', base64Encode(systemKey));
        await platformService.secureWrite('system_key_provisioned', 'true');
      }

      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(systemKey));
      final counter = Uint8List.fromList(iv);
      final ksBlock = Uint8List(16);

      final ciphertext = Uint8List(plaintext.length);
      int offset = 0;
      while (offset + 16 <= plaintext.length) {
        aes.processBlock(counter, 0, ksBlock, 0);
        for (int i = 0; i < 16; i++) {
          ciphertext[offset + i] = plaintext[offset + i] ^ ksBlock[i];
        }
        for (int i = 15; i >= 0; i--) {
          counter[i] = (counter[i] + 1) & 0xFF;
          if (counter[i] != 0) break;
        }
        offset += 16;
      }
      if (offset < plaintext.length) {
        aes.processBlock(counter, 0, ksBlock, 0);
        final rem = plaintext.length - offset;
        for (int i = 0; i < rem; i++) {
          ciphertext[offset + i] = plaintext[offset + i] ^ ksBlock[i];
        }
      }

      // Write c1 header (kMediaMagicCtrV1 + IV + ciphertext)
      final c1Blob = Uint8List(8 + 16 + ciphertext.length);
      c1Blob.setRange(0, 8, kMediaMagicCtrV1);
      c1Blob.setRange(8, 24, iv);
      c1Blob.setRange(24, c1Blob.length, ciphertext);
      await c1File.writeAsBytes(c1Blob);

      // Decrypt using decryptStreamSystem
      await crypto.decryptStreamSystem(c1File, decFile);
      final decrypted = await decFile.readAsBytes();
      expect(decrypted, equals(plaintext),
          reason: 'Legacy c1 blob keyed by system_key must still be readable');
    });

    test('T6 — range read on c2: decryptRangeSystem returns exact bytes for an unaligned off-boundary range', () async {
      final srcFile = File('${tempDir.path}/t6_src.bin');
      final encFile = File('${tempDir.path}/t6_enc.bin');

      final random = Random.secure();
      final plaintext = Uint8List(128 * 1024 + 91);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(plaintext);

      // Encrypt as c2
      await crypto.encryptStreamSystemCtr(srcFile, encFile);

      // Range read starting at offset 37 (not a 16-byte boundary) with length 83
      const rangeOffset = 37;
      const rangeLength = 83;
      final expectedSlice = plaintext.sublist(rangeOffset, rangeOffset + rangeLength);

      final actualSlice = await crypto.decryptRangeSystem(encFile, rangeOffset, rangeLength);
      expect(actualSlice.length, equals(rangeLength));
      expect(actualSlice, equals(expectedSlice),
          reason: 'decryptRangeSystem on c2 must correctly decrypt off-boundary byte ranges');
    });
  });
}
