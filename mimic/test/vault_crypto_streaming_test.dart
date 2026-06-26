import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:path/path.dart' as p;

class FakePlatformService implements PlatformService {
  final Map<String, String> _secureStorage = {};
  final Map<String, Uint8List> _files = {};

  @override
  bool isWeb() => false;

  @override
  Future<void> secureWrite(String key, String value) async => _secureStorage[key] = value;
  @override
  Future<String?> secureRead(String key) async => _secureStorage[key];
  @override
  Future<void> secureDelete(String key) async => _secureStorage.remove(key);
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async => _files[path] = data;
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => _files[path];
  @override
  Future<void> deleteFile(String path) async => _files.remove(path);

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();

  Future<void> writeJson(String path, Map<String, dynamic> data) async {}
  Future<Map<String, dynamic>?> readJson(String path) async => null;
  Future<void> updateConfig(String key, dynamic value) async {}
  Future<Map<String, dynamic>?> readConfig() async => null;
}

void main() {
  late VaultCrypto vaultCrypto;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_crypto_stream_test');
    vaultCrypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
    await vaultCrypto.initialize('1234');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

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

  group('VaultCrypto Streaming', () {
    test('encryptStream and decryptStream round-trip', () async {
      final sizes = [0, 15, 16, 17, 4096, 1024 * 1024, 5 * 1024 * 1024];
      for (final size in sizes) {
        final original = generateRandomBytes(size);
        final src = createTempFile('src_\$size.bin', original);
        final encrypted = createTempFile('enc_\$size.bin');
        final decrypted = createTempFile('dec_\$size.bin');

        await vaultCrypto.encryptStream(src, encrypted);
        await vaultCrypto.decryptStream(encrypted, decrypted);

        final resultBytes = decrypted.readAsBytesSync();
        expect(resultBytes, original, reason: 'Failed for size \$size');
      }
    });

    test('encryptStreamSystem and decryptStreamSystem round-trip', () async {
      final sizes = [0, 15, 16, 17, 4096, 1024 * 1024];
      for (final size in sizes) {
        final original = generateRandomBytes(size);
        final src = createTempFile('src_sys_\$size.bin', original);
        final encrypted = createTempFile('enc_sys_\$size.bin');
        final decrypted = createTempFile('dec_sys_\$size.bin');

        await vaultCrypto.encryptStreamSystem(src, encrypted);
        await vaultCrypto.decryptStreamSystem(encrypted, decrypted);

        final resultBytes = decrypted.readAsBytesSync();
        expect(resultBytes, original, reason: 'Failed for system size \$size');
      }
    });

    test('CROSS-COMPAT core: stream -> in-memory', () async {
      final original = generateRandomBytes(1024);
      final src = createTempFile('cross_src.bin', original);
      final encrypted = createTempFile('cross_enc.bin');

      await vaultCrypto.encryptStream(src, encrypted);
      final decryptedBytes = vaultCrypto.decrypt(encrypted.readAsBytesSync());
      expect(decryptedBytes, original);
    });

    test('CROSS-COMPAT core: in-memory -> stream', () async {
      final original = generateRandomBytes(1024);
      final encryptedBytes = vaultCrypto.encrypt(original);
      final encrypted = createTempFile('cross_enc2.bin', encryptedBytes);
      final decrypted = createTempFile('cross_dec2.bin');

      await vaultCrypto.decryptStream(encrypted, decrypted);
      expect(decrypted.readAsBytesSync(), original);
    });

    test('CROSS-COMPAT system: stream -> in-memory', () async {
      final original = generateRandomBytes(1024);
      final src = createTempFile('cross_sys_src.bin', original);
      final encrypted = createTempFile('cross_sys_enc.bin');

      await vaultCrypto.encryptStreamSystem(src, encrypted);
      final decryptedBytes = await vaultCrypto.decryptSystem(encrypted.readAsBytesSync());
      expect(decryptedBytes, original);
    });

    test('CROSS-COMPAT system: in-memory -> stream', () async {
      final original = generateRandomBytes(1024);
      final encryptedBytes = await vaultCrypto.encryptSystem(original);
      final encrypted = createTempFile('cross_sys_enc2.bin', encryptedBytes);
      final decrypted = createTempFile('cross_sys_dec2.bin');

      await vaultCrypto.decryptStreamSystem(encrypted, decrypted);
      expect(decrypted.readAsBytesSync(), original);
    });

    test('decryptStreamSystem falls back correctly on legacy blob', () async {
      // Logic for testing legacy blob.
    });

    group('CTR Streaming & Range', () {
      test('1. CTR round-trip: non-multiple of 16 size (no padding)', () async {
        final original = generateRandomBytes(70001);
        final src = createTempFile('ctr_src.bin', original);
        final encrypted = createTempFile('ctr_enc.bin');
        final decrypted = createTempFile('ctr_dec.bin');

        await vaultCrypto.encryptStreamSystemCtr(src, encrypted);
        await vaultCrypto.decryptStreamSystem(encrypted, decrypted);

        final resultBytes = decrypted.readAsBytesSync();
        expect(resultBytes.length, original.length);
        expect(resultBytes, original);
      });

      test('2. RANGE CORRECTNESS', () async {
        final original = generateRandomBytes(200 * 1024 + 57);
        final src = createTempFile('range_src.bin', original);
        final encrypted = createTempFile('range_enc.bin');
        await vaultCrypto.encryptStreamSystemCtr(src, encrypted);

        Future<void> assertRange(int offset, int len) async {
          final rangeBytes = await vaultCrypto.decryptRangeSystem(encrypted, offset, len);
          final expected = original.sublist(offset, min(offset + len, original.length));
          expect(rangeBytes, expected, reason: 'Failed at offset $offset len $len');
        }

        await assertRange(0, 100); // offset 0
        await assertRange(17, 50); // NOT a multiple of 16
        await assertRange(15, 34); // spanning several block boundaries
        await assertRange(1024, 1); // length 1
        await assertRange(original.length - 1, 10); // final byte
        await assertRange(0, original.length); // full range
      });

      test('3. Regression: CBC round-trip via router & range fallback', () async {
        final original = generateRandomBytes(10000);
        final src = createTempFile('cbc_src.bin', original);
        final encrypted = createTempFile('cbc_enc.bin');
        final decrypted = createTempFile('cbc_dec.bin');

        await vaultCrypto.encryptStreamSystem(src, encrypted);
        await vaultCrypto.decryptStreamSystem(encrypted, decrypted);
        expect(decrypted.readAsBytesSync(), original);

        final rangeBytes = await vaultCrypto.decryptRangeSystem(encrypted, 50, 100);
        expect(rangeBytes, original.sublist(50, 150));
      });

      test('4. Empty-plaintext edge case for CTR', () async {
        final original = Uint8List(0);
        final src = createTempFile('empty_ctr_src.bin', original);
        final encrypted = createTempFile('empty_ctr_enc.bin');
        final decrypted = createTempFile('empty_ctr_dec.bin');

        await vaultCrypto.encryptStreamSystemCtr(src, encrypted);
        await vaultCrypto.decryptStreamSystem(encrypted, decrypted);
        expect(decrypted.readAsBytesSync(), original);
        
        final rangeBytes = await vaultCrypto.decryptRangeSystem(encrypted, 0, 10);
        expect(rangeBytes, Uint8List(0));
      });
    });
  });
}
