// test/vault/crypto/crypto_isolate_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/crypto_isolate.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

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

    test('T-CANCEL-ENTRY: a cancel already pending aborts the decrypt before any isolate work', () async {
      final original = generateRandomBytes(64 * 1024);
      final src = createTempFile('cancel_src.bin', original);
      final encrypted = createTempFile('cancel_enc.bin');
      final decrypted = createTempFile('cancel_dec.bin');
      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      await expectLater(
        cryptoIsolateDecryptFile(
          key: testKey,
          srcPath: encrypted.path,
          destPath: decrypted.path,
          shouldAbort: () => true,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('T-CANCEL-MIDFLIGHT: a cancel arriving mid-decrypt kills the worker and surfaces OperationCancelledException', () async {
      // 12 MB of ciphertext: far more decrypt work than the 5 ms abort-poll
      // interval, so the kill lands long before the worker could finish.
      // One random page tiled over the buffer — this test only needs real
      // decrypt work, not unique plaintext.
      final page = generateRandomBytes(64 * 1024);
      final original = Uint8List(12 * 1024 * 1024);
      for (var i = 0; i < original.length; i += page.length) {
        original.setRange(i,
            i + page.length > original.length ? original.length : i + page.length,
            page);
      }
      final src = createTempFile('cancelmid_src.bin', original);
      final encrypted = createTempFile('cancelmid_enc.bin');
      final decrypted = createTempFile('cancelmid_dec.bin');
      await cryptoIsolateEncryptFile(
        key: testKey,
        iv: testIv,
        srcPath: src.path,
        destPath: encrypted.path,
      );

      await expectLater(
        cryptoIsolateDecryptFile(
          key: testKey,
          srcPath: encrypted.path,
          destPath: decrypted.path,
          shouldAbort: () => true,
          abortPollInterval: const Duration(milliseconds: 5),
        ),
        throwsA(isA<OperationCancelledException>()),
        reason:
            'the worker is a raw Isolate.spawn, so a cancel must kill it mid-file instead of waiting it out',
      );
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

      await expectLater(
        vaultCrypto.encryptStreamSystem(src, enc),
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
    test('T-WIRE-V1: a v1 blob decrypts through the delegated isolate path byte-identically', () async {
      const size = 128 * 1024 + 37;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 23 + 11) & 0xFF;
      }

      final src = createTempFile('wire_v1_src.bin', pattern);
      final enc = createTempFile('wire_v1_enc.bin');
      final dec = createTempFile('wire_v1_dec.bin');

      // Pre-existing inline expectation: encryptStreamSystem -> decryptStreamSystem
      // round-trips. The type 1 branch now delegates to the background isolate;
      // the recovered bytes must not change.
      await vaultCrypto.encryptStreamSystem(src, enc);
      await vaultCrypto.decryptStreamSystem(enc, dec);

      expect(dec.readAsBytesSync(), equals(pattern),
          reason: 'Delegated v1 decryption must be byte-identical to the inline expectation');
    });

    test('T-WIRE-C2: a c2 blob decrypts through the delegated isolate path byte-identically', () async {
      // Crosses several 64 KB chunk boundaries and ends mid-block.
      const size = 2 * 1024 * 1024 + 13;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 19 + 23) & 0xFF;
      }

      final src = createTempFile('wire_c2_src.bin', pattern);
      final enc = createTempFile('wire_c2_enc.bin');
      final dec = createTempFile('wire_c2_dec.bin');

      // Pre-existing inline expectation: CTR payload written by
      // encryptStreamSystemCtr round-trips byte-for-byte through full-file decrypt.
      await vaultCrypto.encryptStreamSystemCtr(src, enc);
      await vaultCrypto.decryptStreamSystem(enc, dec);

      expect(dec.readAsBytesSync(), equals(pattern),
          reason: 'Delegated c2 decryption must be byte-identical to the inline expectation');
    });

    test('T-CHANGEPIN-WIRE: isolate decrypt recovers plaintext after changePin (DEK, not PIN KEK)', () async {
      const size = 64 * 1024 + 21;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 29 + 31) & 0xFF;
      }

      // Fresh provision under a first pin, independent of the setUp fixture.
      final freshVault = VaultCrypto(FakePlatformService(), FakeKeystoreService());
      await freshVault.initialize('111111');

      final src = createTempFile('changepin_wire_src.bin', pattern);
      final enc = createTempFile('changepin_wire_enc.bin');
      final dec = createTempFile('changepin_wire_dec.bin');

      // Blob keyed by the live master DEK before the swap.
      await freshVault.encryptStreamSystem(src, enc);

      // changePin rewraps the SAME DEK under a new PIN KEK; _derivedKey itself is
      // unchanged. Any delegation that passes a freshly derived PIN key instead of
      // the DEK produces garbage or a padding failure right here.
      await freshVault.changePin('222222');

      await freshVault.decryptStreamSystem(enc, dec);

      expect(dec.readAsBytesSync(), equals(pattern),
          reason: 'After changePin the DEK still decrypts the blob; handing a freshly derived PIN KEK to the isolate would corrupt this round trip');
    });

    test('T-LOCKED-DECRYPT: decryptStreamSystem on a locked vault throws before any isolate work', () async {
      final v1Src = createTempFile('locked_v1_src.bin', [1, 2, 3, 4, 5, 6, 7, 8]);
      final v1Blob = createTempFile('locked_v1_blob.bin');
      await vaultCrypto.encryptStreamSystem(v1Src, v1Blob);

      final c2Src = createTempFile('locked_c2_src.bin', List.generate(40, (i) => i));
      final c2Blob = createTempFile('locked_c2_blob.bin');
      await vaultCrypto.encryptStreamSystemCtr(c2Src, c2Blob);

      vaultCrypto.lock();

      final decV1 = File(p.join(tempDir.path, 'locked_v1_out.bin'));
      await expectLater(
        vaultCrypto.decryptStreamSystem(v1Blob, decV1),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Vault is locked'))),
        reason: 'Type 1 branch must reject a locked vault before delegating to the isolate',
      );

      final decC2 = File(p.join(tempDir.path, 'locked_c2_out.bin'));
      await expectLater(
        vaultCrypto.decryptStreamSystem(c2Blob, decC2),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Vault is locked'))),
        reason: 'Type 3 branch must reject a locked vault before delegating to the isolate',
      );

      expect(decV1.existsSync(), isFalse,
          reason: 'No destination file should be created by the locked-vault guard');
      expect(decC2.existsSync(), isFalse,
          reason: 'No destination file should be created by the locked-vault guard');
    });

    test('T-WIRE-CTR-ENC: encryptStreamSystemCtr writes a c2 blob through the isolate that round-trips and seeks', () async {
      // Crosses several 64 KB chunk boundaries and ends mid-block.
      const size = 2 * 1024 * 1024 + 29;
      final pattern = Uint8List(size);
      for (int i = 0; i < size; i++) {
        pattern[i] = (i * 31 + 7) & 0xFF;
      }

      final src = createTempFile('wire_ctrenc_src.bin', pattern);
      final enc = createTempFile('wire_ctrenc_enc.bin');
      await vaultCrypto.encryptStreamSystemCtr(src, enc);

      // Header layout: c2 magic + IV + payload, nothing else.
      final encBytes = enc.readAsBytesSync();
      expect(encBytes.length, 24 + size,
          reason: 'c2 blob must be exactly magic(8) + IV(16) + payload');
      expect(encBytes.sublist(0, 8), equals(kMediaMagicCtrV2),
          reason: 'c2 stream encryption must start with the MVKEYc2 magic');

      // Full-file round trip through decryptStreamSystem.
      final dec = createTempFile('wire_ctrenc_dec.bin');
      await vaultCrypto.decryptStreamSystem(enc, dec);
      expect(dec.readAsBytesSync(), equals(pattern),
          reason: 'Isolate-written c2 blob must round-trip byte-for-byte');

      // Seek path: a mid-file, unaligned range must return exactly the
      // matching slice of the original pattern.
      final range = await vaultCrypto.decryptRangeSystem(File(enc.path), 1000, 5000);
      expect(range, equals(pattern.sublist(1000, 6000)),
          reason: 'decryptRangeSystem must seek correctly into an isolate-written c2 blob');
    });

    test('T-KEYSURVIVES-CTR: the live master key still works after a CTR encryption', () async {
      final first = generateRandomBytes(64 * 1024 + 13);
      final srcA = createTempFile('ks_ctr_src_a.bin', first);
      final encA = createTempFile('ks_ctr_enc_a.bin');
      final decA = createTempFile('ks_ctr_dec_a.bin');
      await vaultCrypto.encryptStreamSystemCtr(srcA, encA);
      await vaultCrypto.decryptStreamSystem(encA, decA);
      expect(decA.readAsBytesSync(), equals(first));

      // Second call proves the worker zeroed its COPY of the key, not the
      // live DEK held by VaultCrypto.
      final second = generateRandomBytes(32 * 1024 + 5);
      final srcB = createTempFile('ks_ctr_src_b.bin', second);
      final encB = createTempFile('ks_ctr_enc_b.bin');
      final decB = createTempFile('ks_ctr_dec_b.bin');
      await vaultCrypto.encryptStreamSystemCtr(srcB, encB);
      await vaultCrypto.decryptStreamSystem(encB, decB);
      expect(decB.readAsBytesSync(), equals(second),
          reason: 'Second CTR encryption must succeed, proving the live DEK survived the worker key-zeroing');
    });

    test('T-LOCKED-CTR-ENC: encryptStreamSystemCtr on a locked vault fails before any isolate work and leaves no file', () async {
      vaultCrypto.lock();

      final src = createTempFile('locked_ctr_src.bin', [9, 8, 7, 6]);
      final enc = File(p.join(tempDir.path, 'locked_ctr_enc.bin'));

      await expectLater(
        vaultCrypto.encryptStreamSystemCtr(src, enc),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Vault is locked'))),
        reason: 'Locked vault must throw before spawning the isolate',
      );

      expect(enc.existsSync(), isFalse,
          reason: 'No destination file should be left behind on locked-vault failure');
    });

    test('T-CTR-ENC-DETERMINISTIC: the same key and IV produce byte-identical c2 output across two spawns', () async {
      final plaintext = generateRandomBytes(3 * 64 * 1024 + 11);
      final src = createTempFile('det_ctr_src.bin', plaintext);
      final outA = createTempFile('det_ctr_a.bin');
      final outB = createTempFile('det_ctr_b.bin');

      await cryptoIsolateEncryptFileCtr(key: testKey, iv: testIv, srcPath: src.path, destPath: outA.path);
      await cryptoIsolateEncryptFileCtr(key: testKey, iv: testIv, srcPath: src.path, destPath: outB.path);

      expect(outB.readAsBytesSync(), equals(outA.readAsBytesSync()),
          reason: 'The IV must be transported into the worker, not regenerated: identical key+IV in, identical bytes out');
    });

    test('T-CTR-ENC-ERROR: a failing CTR encrypt rethrows instead of hanging and leaves no partial output', () async {
      final missing = File(p.join(tempDir.path, 'does_not_exist.bin'));
      final out = createTempFile('err_ctr_out.bin');

      await expectLater(
        cryptoIsolateEncryptFileCtr(key: testKey, iv: testIv, srcPath: missing.path, destPath: out.path),
        throwsA(isA<Exception>()),
        reason: 'Worker failure must surface on the caller side',
      );
      expect(out.existsSync(), isFalse,
          reason: 'The worker must delete the partial destination on failure');
    });

    test('T-WIRE-C1: a manually built c1 blob decrypts through the delegated isolate path byte-identically, locked or not', () async {
      final rawStoredKey = await platformService.secureRead('system_key');
      final Uint8List systemKey;
      if (rawStoredKey != null) {
        systemKey = base64Decode(rawStoredKey);
      } else {
        systemKey = generateRandomBytes(32);
        await platformService.secureWrite('system_key', base64Encode(systemKey));
        await platformService.secureWrite('system_key_provisioned', 'true');
      }

      final plaintext = generateRandomBytes(128 * 1024 + 23);
      final iv = generateRandomBytes(16);
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

      final c1Blob = Uint8List(8 + 16 + ciphertext.length);
      c1Blob.setRange(0, 8, kMediaMagicCtrV1);
      c1Blob.setRange(8, 24, iv);
      c1Blob.setRange(24, c1Blob.length, ciphertext);
      final c1File = createTempFile('wire_c1_blob.bin', c1Blob);

      // Unlocked first: the delegated c1 path must be byte-identical.
      final dec = createTempFile('wire_c1_dec.bin');
      await vaultCrypto.decryptStreamSystem(c1File, dec);
      expect(dec.readAsBytesSync(), equals(plaintext),
          reason: 'Delegated c1 decryption must be byte-identical to the inline expectation');

      // Then locked: _getSystemKey() is readable while locked, and the c1
      // branch has never had a lock check — preserved behavior (see C10).
      vaultCrypto.lock();
      final decLocked = createTempFile('wire_c1_dec_locked.bin');
      await vaultCrypto.decryptStreamSystem(c1File, decLocked);
      expect(decLocked.readAsBytesSync(), equals(plaintext),
          reason: 'c1 decryption while locked must keep working exactly as before');
    });
  });
}

