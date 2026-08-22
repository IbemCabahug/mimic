// test/vault/crypto/crypto_isolate_test.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/crypto_isolate.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
import 'package:path/path.dart' as p;

class FakePlatformService implements PlatformService {
  final Map<String, String> _store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => _store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(_store);

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

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

void main() {
  late Directory tempDir;
  late FakePlatformService platformService;
  late FakeKeystoreService keystoreService;
  late VaultCrypto vaultCrypto;
  late Uint8List testKey;
  late Uint8List testIv;

  // Copied from test/vault_crypto_streaming_test.dart:55-66
  File createTempFile(String name, [List<int>? data]) {
    final file = File(p.join(tempDir.path, name));
    if (data != null) {
      file.writeAsBytesSync(data);
    }
    return file;
  }

  Uint8List generateRandomBytes(int length) {
    final rand = Random();
    return Uint8List.fromList(List.generate(length, (_) => rand.nextInt(256)));
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crypto_isolate_test_');
    platformService = FakePlatformService();
    keystoreService = FakeKeystoreService();
    vaultCrypto = VaultCrypto(platformService, keystoreService);
    await vaultCrypto.initialize('1234');

    final salt = await platformService.secureRead('vault_salt');
    testKey = deriveVaultPinKek('1234', salt!);
    testIv = generateRandomBytes(16);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('CryptoIsolate Format Compatibility & Hardening', () {
    test('isolate ciphertext decrypts with the existing decrypt path', () async {
      final original = generateRandomBytes(128 * 1024 + 37);
      final src = createTempFile('iso_src.bin', original);
      final encrypted = createTempFile('iso_enc.bin');
      final decrypted = createTempFile('iso_dec.bin');

      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      // Decrypt using existing production streaming path
      await vaultCrypto.decryptStreamSystem(encrypted, decrypted);

      final decryptedBytes = decrypted.readAsBytesSync();
      expect(decryptedBytes, original,
          reason: 'Decrypted bytes from existing path must match original');
    });

    test('existing ciphertext decrypts after an isolate round trip', () async {
      final original = generateRandomBytes(95 * 1024 + 11);
      final src = createTempFile('prod_src.bin', original);
      final encrypted = createTempFile('prod_enc.bin');
      final decrypted = createTempFile('prod_dec.bin');

      // Encrypt using existing production streaming path
      await vaultCrypto.encryptStreamSystem(src, encrypted);

      // Decrypt using new isolate path
      await cryptoIsolateDecryptFile(
        key: testKey,
        srcPath: encrypted.path,
        destPath: decrypted.path,
      );

      final decryptedBytes = decrypted.readAsBytesSync();
      expect(decryptedBytes, original,
          reason: 'Decrypted bytes from isolate path must match original');
    });

    test('a file whose size is not a multiple of the block size round-trips', () async {
      // 64KB + 13 bytes to cross chunk boundary with uneven leftover carry
      final original = generateRandomBytes(64 * 1024 + 13);
      final src = createTempFile('leftover_src.bin', original);
      final encrypted = createTempFile('leftover_enc.bin');
      final decrypted = createTempFile('leftover_dec.bin');

      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      await cryptoIsolateDecryptFile(
        key: testKey,
        srcPath: encrypted.path,
        destPath: decrypted.path,
      );

      expect(decrypted.readAsBytesSync(), original,
          reason: 'Non-block-aligned file must round-trip byte-identical');
    });

    test('the worker rethrows on the caller side', () async {
      final nonExistentSrcPath = p.join(tempDir.path, 'missing_file.bin');
      final destPath = p.join(tempDir.path, 'out.bin');

      expect(
        () async => await cryptoIsolateEncryptFile(
          key: testKey,
          iv: testIv,
          srcPath: nonExistentSrcPath,
          destPath: destPath,
        ),
        throwsA(isA<Exception>()),
        reason: 'Worker isolate error must cross boundary and be rethrown on caller side',
      );
    });

    test('the emitted progress counts never exceed the file size and end at it', () async {
      final fileSize = 200 * 1024; // 200 KB
      final original = generateRandomBytes(fileSize);
      final src = createTempFile('progress_src.bin', original);
      final encrypted = createTempFile('progress_enc.bin');

      final progressPort = ReceivePort();
      final progressEvents = <int>[];
      final progressSubscription = progressPort.listen((event) {
        if (event is int) {
          progressEvents.add(event);
        }
      });

      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
        progressPort: progressPort.sendPort,
      );

      await progressSubscription.cancel();
      progressPort.close();

      expect(progressEvents, isNotEmpty,
          reason: 'Progress events should have been emitted');
      for (final count in progressEvents) {
        expect(count, lessThanOrEqualTo(fileSize),
            reason: 'Emitted count must never exceed file size');
      }
      expect(progressEvents.last, equals(fileSize),
          reason: 'Final progress event must match total file size');
    });

    test('a legacy-format blob fed to cryptoIsolateDecryptFile fails with unsupportedFormat and not corrupted', () async {
      // Legacy format: 16-byte IV followed by CBC ciphertext (no MVKEYv1\0 header)
      final original = generateRandomBytes(128);
      final legacyCipher = createTempFile('legacy_blob.bin');
      final legacyDecrypted = createTempFile('legacy_dec.bin');

      // Encrypt with legacy core stream (which writes IV + ciphertext without magic header)
      final src = createTempFile('legacy_src.bin', original);
      await vaultCrypto.encryptStream(src, legacyCipher);

      // Attempt to decrypt with cryptoIsolateDecryptFile
      try {
        await cryptoIsolateDecryptFile(
          key: testKey,
          srcPath: legacyCipher.path,
          destPath: legacyDecrypted.path,
        );
        fail('Should have thrown UnsupportedMediaFormatException');
      } catch (e) {
        expect(e, isA<UnsupportedMediaFormatException>(),
            reason: 'Legacy format blob must throw UnsupportedMediaFormatException');
        expect(e, isNot(isA<CorruptedMediaFileException>()),
            reason: 'Legacy format blob must NOT be classified as corrupted');
      }
    });

    test('truncating a valid v1 file mid-block throws CorruptedMediaFileException', () async {
      final original = generateRandomBytes(64 * 1024 + 32);
      final src = createTempFile('trunc_src.bin', original);
      final encrypted = createTempFile('trunc_enc.bin');
      final decrypted = createTempFile('trunc_dec.bin');

      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      // Truncate the encrypted file mid-block (chop 7 bytes off the end)
      final encBytes = encrypted.readAsBytesSync();
      final truncatedBytes = encBytes.sublist(0, encBytes.length - 7);
      encrypted.writeAsBytesSync(truncatedBytes);

      expect(
        () async => await cryptoIsolateDecryptFile(
          key: testKey,
          srcPath: encrypted.path,
          destPath: decrypted.path,
        ),
        throwsA(isA<CorruptedMediaFileException>()),
        reason: 'Truncating mid-block must throw typed CorruptedMediaFileException',
      );
    });

    test('cryptoIsolateEncryptFile does not mutate or zero caller key buffer', () async {
      final original = generateRandomBytes(64 * 1024 + 19);
      final src = createTempFile('key_guard_src.bin', original);
      final encrypted = createTempFile('key_guard_enc.bin');

      final callerKey = Uint8List.fromList(testKey);
      final salt = await platformService.secureRead('vault_salt');
      final expectedKey = deriveVaultPinKek('1234', salt!);

      await cryptoIsolateEncryptFile(
        key: callerKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      expect(callerKey, equals(expectedKey),
          reason: 'Caller key buffer must remain intact and non-zero after isolate encryption');
    });

    test('cryptoIsolateDecryptFile does not mutate or zero caller key buffer', () async {
      final original = generateRandomBytes(64 * 1024 + 23);
      final src = createTempFile('dec_key_guard_src.bin', original);
      final encrypted = createTempFile('dec_key_guard_enc.bin');
      final decrypted = createTempFile('dec_key_guard_dec.bin');

      final encryptKey = Uint8List.fromList(testKey);
      await cryptoIsolateEncryptFile(
        key: encryptKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      final callerKey = Uint8List.fromList(testKey);
      final salt = await platformService.secureRead('vault_salt');
      final expectedKey = deriveVaultPinKek('1234', salt!);

      await cryptoIsolateDecryptFile(
        key: callerKey,
        srcPath: encrypted.path,
        destPath: decrypted.path,
      );

      expect(callerKey, equals(expectedKey),
          reason: 'Caller key buffer must remain intact and non-zero after isolate decryption');
    });

    test('T-EQ: encryptStreamSystem and the background worker produce byte-identical output for the same key and IV', () async {
      // Deterministic 3 MB + 13 bytes pattern (not a multiple of 16)
      const size = 3 * 1024 * 1024 + 13;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 31 + 17) & 0xFF;
      }

      final src = createTempFile('t_eq_src.bin', pattern);
      final fileA = createTempFile('t_eq_file_a.bin');
      final fileB = createTempFile('t_eq_file_b.bin');

      // Output A from existing encryptStreamSystem
      await vaultCrypto.encryptStreamSystem(src, fileA);

      final bytesA = fileA.readAsBytesSync();
      expect(bytesA.length, greaterThanOrEqualTo(24));
      // Extract IV that encryptStreamSystem wrote at bytes 8..24
      final ivFromA = bytesA.sublist(8, 24);

      // Output B from cryptoIsolateEncryptFile with the same key and IV
      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: ivFromA,
        srcPath: src.path,
        destPath: fileB.path,
      );

      final bytesB = fileB.readAsBytesSync();

      expect(bytesB.length, equals(bytesA.length),
          reason: 'File lengths must match exactly (File A: ${bytesA.length}, File B: ${bytesB.length})');

      int firstDiff = -1;
      final minLen = bytesA.length < bytesB.length ? bytesA.length : bytesB.length;
      for (int i = 0; i < minLen; i++) {
        if (bytesA[i] != bytesB[i]) {
          firstDiff = i;
          break;
        }
      }

      if (firstDiff != -1 || bytesA.length != bytesB.length) {
        final hexA = bytesA.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final hexB = bytesB.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        fail('Mismatch at byte offset $firstDiff (len A: ${bytesA.length}, len B: ${bytesB.length}).\nFile A (first 32B): $hexA\nFile B (first 32B): $hexB');
      }

      expect(bytesB, equals(bytesA),
          reason: 'encryptStreamSystem and background worker must produce byte-identical output');
    });

    test('T-RT: a blob written by the background worker is readable by the existing main-thread decrypt path', () async {
      const size = 3 * 1024 * 1024 + 13;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 37 + 19) & 0xFF;
      }

      final src = createTempFile('t_rt_src.bin', pattern);
      final encrypted = createTempFile('t_rt_enc.bin');
      final decrypted = createTempFile('t_rt_dec.bin');

      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      // Decrypt using existing main-thread streaming decrypt path (decryptStreamSystem)
      await vaultCrypto.decryptStreamSystem(encrypted, decrypted);

      final decryptedBytes = decrypted.readAsBytesSync();
      expect(decryptedBytes, equals(pattern),
          reason: 'Decrypted bytes from existing decryptStreamSystem must equal original bytes');
    });

    test('T-EQ16: byte-identical output when the source length is an exact multiple of 16', () async {
      // Deterministic exactly 1 MB pattern (1,048,576 bytes, exact multiple of 16)
      const size = 1024 * 1024;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 29 + 13) & 0xFF;
      }

      final src = createTempFile('t_eq16_src.bin', pattern);
      final fileA = createTempFile('t_eq16_file_a.bin');
      final fileB = createTempFile('t_eq16_file_b.bin');

      // Output A from existing encryptStreamSystem
      await vaultCrypto.encryptStreamSystem(src, fileA);

      final bytesA = fileA.readAsBytesSync();
      expect(bytesA.length, greaterThanOrEqualTo(24));
      final ivFromA = bytesA.sublist(8, 24);

      // Output B from cryptoIsolateEncryptFile with the same key and IV
      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: ivFromA,
        srcPath: src.path,
        destPath: fileB.path,
      );

      final bytesB = fileB.readAsBytesSync();

      expect(bytesB.length, equals(bytesA.length),
          reason: 'File lengths must match exactly (File A: ${bytesA.length}, File B: ${bytesB.length})');

      int firstDiff = -1;
      final minLen = bytesA.length < bytesB.length ? bytesA.length : bytesB.length;
      for (int i = 0; i < minLen; i++) {
        if (bytesA[i] != bytesB[i]) {
          firstDiff = i;
          break;
        }
      }

      if (firstDiff != -1 || bytesA.length != bytesB.length) {
        final hexA = bytesA.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final hexB = bytesB.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        fail('Mismatch at byte offset $firstDiff (len A: ${bytesA.length}, len B: ${bytesB.length}).\nFile A (first 32B): $hexA\nFile B (first 32B): $hexB');
      }

      expect(bytesB, equals(bytesA),
          reason: 'encryptStreamSystem and background worker must produce byte-identical output for length multiple of 16');
    });

    test('T-EQSMALL: byte-identical output for a file smaller than one 64 KB read buffer', () async {
      // Deterministic exactly 100 bytes pattern (< 64 KB buffer)
      const size = 100;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 43 + 7) & 0xFF;
      }

      final src = createTempFile('t_eqsmall_src.bin', pattern);
      final fileA = createTempFile('t_eqsmall_file_a.bin');
      final fileB = createTempFile('t_eqsmall_file_b.bin');

      // Output A from existing encryptStreamSystem
      await vaultCrypto.encryptStreamSystem(src, fileA);

      final bytesA = fileA.readAsBytesSync();
      expect(bytesA.length, greaterThanOrEqualTo(24));
      final ivFromA = bytesA.sublist(8, 24);

      // Output B from cryptoIsolateEncryptFile with the same key and IV
      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: ivFromA,
        srcPath: src.path,
        destPath: fileB.path,
      );

      final bytesB = fileB.readAsBytesSync();

      expect(bytesB.length, equals(bytesA.length),
          reason: 'File lengths must match exactly (File A: ${bytesA.length}, File B: ${bytesB.length})');

      int firstDiff = -1;
      final minLen = bytesA.length < bytesB.length ? bytesA.length : bytesB.length;
      for (int i = 0; i < minLen; i++) {
        if (bytesA[i] != bytesB[i]) {
          firstDiff = i;
          break;
        }
      }

      if (firstDiff != -1 || bytesA.length != bytesB.length) {
        final hexA = bytesA.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final hexB = bytesB.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        fail('Mismatch at byte offset $firstDiff (len A: ${bytesA.length}, len B: ${bytesB.length}).\nFile A (first 32B): $hexA\nFile B (first 32B): $hexB');
      }

      expect(bytesB, equals(bytesA),
          reason: 'encryptStreamSystem and background worker must produce byte-identical output for file < 64KB');
    });

    test('T-KEYSURVIVES: the live master key still works after an encryption', () async {
      final originalA = generateRandomBytes(64 * 1024 + 17);
      final srcA = createTempFile('key_surv_src_a.bin', originalA);
      final encA = createTempFile('key_surv_enc_a.bin');
      final decA = createTempFile('key_surv_dec_a.bin');

      // First call
      await vaultCrypto.encryptStreamSystem(srcA, encA);
      await vaultCrypto.decryptStreamSystem(encA, decA);
      expect(decA.readAsBytesSync(), equals(originalA),
          reason: 'First encryption and decryption must succeed');

      // Second call on a different file - proves _derivedKey was not zeroed
      final originalB = generateRandomBytes(32 * 1024 + 9);
      final srcB = createTempFile('key_surv_src_b.bin', originalB);
      final encB = createTempFile('key_surv_enc_b.bin');
      final decB = createTempFile('key_surv_dec_b.bin');

      await vaultCrypto.encryptStreamSystem(srcB, encB);
      await vaultCrypto.decryptStreamSystem(encB, decB);
      expect(decB.readAsBytesSync(), equals(originalB),
          reason: 'Second encryption after first must succeed, proving live master key survived');
    });

    test('T-LOCKED: encryptStreamSystem on a locked vault fails as before and leaves no file', () async {
      vaultCrypto.lock();

      final src = createTempFile('locked_src.bin', [1, 2, 3, 4]);
      final enc = File(p.join(tempDir.path, 'locked_enc.bin'));

      expect(
        () async => await vaultCrypto.encryptStreamSystem(src, enc),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Vault is locked'))),
        reason: 'Locked vault must throw Exception("Vault is locked")',
      );

      expect(enc.existsSync(), isFalse,
          reason: 'No destination file should be left behind on locked vault failure');
    });

    test('T-POSTSWAP-RT: a file encrypted by the new encryptStreamSystem is readable by decryptStreamSystem', () async {
      const size = 2 * 1024 * 1024 + 7;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 19 + 23) & 0xFF;
      }

      final src = createTempFile('postswap_src.bin', pattern);
      final enc = createTempFile('postswap_enc.bin');
      final dec = createTempFile('postswap_dec.bin');

      await vaultCrypto.encryptStreamSystem(src, enc);
      await vaultCrypto.decryptStreamSystem(enc, dec);

      expect(dec.readAsBytesSync(), equals(pattern),
          reason: 'Round trip through new encryptStreamSystem and decryptStreamSystem must match byte-for-byte');
    });
  });
}

