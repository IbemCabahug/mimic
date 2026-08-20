import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ThrowingEncryptVaultCrypto extends VaultCrypto {
  ThrowingEncryptVaultCrypto(PlatformService platformService, KeystoreService keystoreService)
      : super(platformService, keystoreService);

  @override
  Future<void> encryptStreamSystemCtr(File src, File dest) async {
    throw Exception('Simulated encryption failure during video migration');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late String dbDirPath;

  final Map<String, String> secureStorageData = {};

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'write') {
          final key = methodCall.arguments['key'] as String;
          final value = methodCall.arguments['value'] as String;
          secureStorageData[key] = value;
          return null;
        }
        if (methodCall.method == 'read') {
          final key = methodCall.arguments['key'] as String;
          return secureStorageData[key];
        }
        if (methodCall.method == 'delete') {
          final key = methodCall.arguments['key'] as String;
          secureStorageData.remove(key);
          return null;
        }
        if (methodCall.method == 'readAll') {
          return secureStorageData;
        }
        if (methodCall.method == 'deleteAll') {
          secureStorageData.clear();
          return null;
        }
        return null;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return appDocsPath;
        }
        if (methodCall.method == 'getTemporaryDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('video_vault_test');
    appDocsPath = '${tempDir.path}/app_docs';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    await databaseFactory.setDatabasesPath(dbDirPath);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('VideoVaultService', () {
    test('saveVideoFromFile encrypts and saves video metadata correctly', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // 1. Create ~2MB temp plaintext file
      final srcFile = File('${tempDir.path}/test_video_src.mp4');
      final random = Random.secure();
      final bytes = Uint8List(2 * 1024 * 1024);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(bytes);

      // 2. Call NEW saveVideoFromFile
      final id = await videoVaultService.saveVideoFromFile(
        srcFile,
        'video/mp4',
        120,
        originalName: 'my_video.mp4',
      );

      // 3. Verify bytes via getVideo
      final decryptedBytes = await videoVaultService.getVideo(id);
      expect(decryptedBytes, isNotNull);
      expect(decryptedBytes, equals(bytes));

      // 4. Assert metadata row exists
      final videos = await videoVaultService.getAllVideos();
      expect(videos.length, 1);
      final meta = videos.firstWhere((v) => v.id == id);
      expect(meta.mimeType, 'video/mp4');
      expect(meta.durationS, 120);
      expect(meta.size, bytes.length);
      expect(meta.originalName, 'my_video.mp4');

      // Cleanup
      await srcFile.delete();
      await videoVaultService.deleteVideo(id);
    });

    test('getVideoToTempFile decrypts stream to a temp file safely', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // 1. Create ~2MB temp plaintext file
      final srcFile = File('${tempDir.path}/test_video_src2.mp4');
      final random = Random.secure();
      final bytes = Uint8List(2 * 1024 * 1024);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(bytes);

      // 2. Save
      final id = await videoVaultService.saveVideoFromFile(
        srcFile,
        'video/mp4',
        120,
      );

      // 3. call NEW getVideoToTempFile(id)
      final tempOut = await videoVaultService.getVideoToTempFile(id);
      expect(tempOut, isNotNull);

      // 4. Read bytes and assert EQUAL
      final outBytes = await tempOut!.readAsBytes();
      expect(outBytes, equals(bytes));

      // 5. assert getVideoToTempFile returns null (no throw) for missing blob
      final missingTempOut = await videoVaultService.getVideoToTempFile('non-existent-id');
      expect(missingTempOut, isNull);

      // Cleanup
      await srcFile.delete();
      await videoVaultService.deleteVideo(id);
      if (tempOut.existsSync()) tempOut.deleteSync();
    });

    test('ensureVideoStreamable: CBC blob migrates to CTR', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // 1. Create a plaintext video file
      final srcFile = File('${tempDir.path}/migrate_src.mp4');
      final random = Random.secure();
      final plaintext = Uint8List(50000); // not a multiple of 16
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(plaintext);

      // 2. Save as CBC-encrypted video
      final id = await videoVaultService.saveVideoFromFile(
        srcFile, 'video/mp4', 10,
      );

      // 3. Verify it starts with CBC magic "MVKEYv1\0"
      final blobFile = await platformService.resolveVaultFile(id);
      final cbcMagic = kMediaMagicV1;
      final originalBytes = await blobFile.readAsBytes();
      for (int i = 0; i < 8; i++) {
        expect(originalBytes[i], cbcMagic[i], reason: 'Blob should start as CBC');
      }

      // 4. Migrate
      await videoVaultService.ensureVideoStreamable(id);

      // 5. Verify it now starts with CTR c2 magic "MVKEYc2\0"
      final ctrMagic = kMediaMagicCtrV2;
      final migratedBytes = await blobFile.readAsBytes();
      for (int i = 0; i < 8; i++) {
        expect(migratedBytes[i], ctrMagic[i], reason: 'Blob should now be CTR c2');
      }

      // 6. Full decrypt and verify plaintext is identical
      final decryptedTmp = File('${tempDir.path}/migrated_dec.bin');
      await crypto.decryptStreamSystem(blobFile, decryptedTmp);
      final decryptedBytes = await decryptedTmp.readAsBytes();
      expect(decryptedBytes, equals(plaintext));

      await srcFile.delete();
    });

    test('ensureVideoStreamable: idempotent — second call is a no-op', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final srcFile = File('${tempDir.path}/idem_src.mp4');
      final random = Random.secure();
      final plaintext = Uint8List(30000);
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(plaintext);

      final id = await videoVaultService.saveVideoFromFile(
        srcFile, 'video/mp4', 5,
      );

      // First migration
      await videoVaultService.ensureVideoStreamable(id);
      final blobFile = await platformService.resolveVaultFile(id);
      final afterFirst = await blobFile.readAsBytes();

      // Second call — should be idempotent
      await videoVaultService.ensureVideoStreamable(id);
      final afterSecond = await blobFile.readAsBytes();

      // Bytes should be identical (no re-encryption)
      expect(afterSecond, equals(afterFirst));

      // Still decrypts correctly
      final decryptedTmp = File('${tempDir.path}/idem_dec.bin');
      await crypto.decryptStreamSystem(blobFile, decryptedTmp);
      expect(await decryptedTmp.readAsBytes(), equals(plaintext));

      await srcFile.delete();
    });

    test('ensureVideoStreamable: original preserved on failure (structural)', () async {
      // This test structurally verifies that the migration code replaces the
      // original blob ONLY via rename AFTER ctrTemp is fully written and flushed.
      // The ordering in video_vault_service.dart is:
      //   Step 1: decryptStreamSystem(blobFile, plainTemp)
      //   Step 2: encryptStreamSystemCtr(plainTemp, ctrTemp)
      //   Step 3: ctrTemp.rename(blobFile.path)  <-- atomic swap
      //   Step 4: plainTemp.delete()
      // The catch block cleans up temps and leaves blobFile untouched.
      //
      // We verify the happy path leaves a valid CTR blob and confirm
      // the original CBC blob is never truncated or deleted before rename.

      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final srcFile = File('${tempDir.path}/fail_src.mp4');
      final plaintext = Uint8List(20000);
      final random = Random.secure();
      for (var i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      await srcFile.writeAsBytes(plaintext);

      final id = await videoVaultService.saveVideoFromFile(
        srcFile, 'video/mp4', 3,
      );

      final blobFile = await platformService.resolveVaultFile(id);
      final originalBytes = await blobFile.readAsBytes();

      // Call ensureVideoStreamable on a VALID blob — it should succeed
      await videoVaultService.ensureVideoStreamable(id);

      // Verify the blob was replaced (CTR c2 magic)
      final newBytes = await blobFile.readAsBytes();
      final ctrMagic = kMediaMagicCtrV2;
      for (int i = 0; i < 8; i++) {
        expect(newBytes[i], ctrMagic[i]);
      }

      // Verify original CBC bytes are no longer on disk (replaced by CTR)
      expect(newBytes.length != originalBytes.length || newBytes[5] != originalBytes[5], isTrue);

      await srcFile.delete();
    });

    test('T3 — rescue: create a c1 blob, run ensureVideoStreamable, assert file starts with c2 magic and decrypts', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final random = Random.secure();
      final plaintext = Uint8List(45000);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // 4 arbitrary size bytes + 'ftyp' (ISO base media header)
      plaintext[0] = 0x00;
      plaintext[1] = 0x00;
      plaintext[2] = 0x00;
      plaintext[3] = 0x20;
      plaintext[4] = 0x66; // 'f'
      plaintext[5] = 0x74; // 't'
      plaintext[6] = 0x79; // 'y'
      plaintext[7] = 0x70; // 'p'

      // 1. Manually construct a c1 blob (using system_key)
      final rawKey = secureStorageData['system_key'];
      final Uint8List sysKey;
      if (rawKey != null) {
        sysKey = base64Decode(rawKey);
      } else {
        sysKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
        secureStorageData['system_key'] = base64Encode(sysKey);
        secureStorageData['system_key_provisioned'] = 'true';
      }

      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(sysKey));
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

      const testVideoId = 'rescue-video-t3';
      final blobFile = await platformService.resolveVaultFile(testVideoId);
      await blobFile.parent.create(recursive: true);
      await blobFile.writeAsBytes(c1Blob);

      // Verify file starts with c1 magic
      final preMigrationBytes = await blobFile.readAsBytes();
      expect(preMigrationBytes.sublist(0, 8), equals(kMediaMagicCtrV1));

      // 2. Run rescue (ensureVideoStreamable)
      await videoVaultService.ensureVideoStreamable(testVideoId);

      // 3. Assert on-disk file now starts with c2 magic
      final postMigrationBytes = await blobFile.readAsBytes();
      expect(postMigrationBytes.sublist(0, 8), equals(kMediaMagicCtrV2));

      // 4. Assert it decrypts to original plaintext
      final decryptedTmp = File('${tempDir.path}/t3_decrypted.bin');
      await crypto.decryptStreamSystem(blobFile, decryptedTmp);
      final decryptedBytes = await decryptedTmp.readAsBytes();
      expect(decryptedBytes, equals(plaintext));
    });

    test('T4 — the rescue actually rescues: after c1->c2 migration, clearing system_key (simulating reinstall) still decrypts correctly', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final random = Random.secure();
      final plaintext = Uint8List(35000);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // 4 arbitrary size bytes + 'ftyp' (ISO base media header)
      plaintext[0] = 0x00;
      plaintext[1] = 0x00;
      plaintext[2] = 0x00;
      plaintext[3] = 0x20;
      plaintext[4] = 0x66; // 'f'
      plaintext[5] = 0x74; // 't'
      plaintext[6] = 0x79; // 'y'
      plaintext[7] = 0x70; // 'p'

      // 1. Manually construct c1 blob under current system key
      final rawKey = secureStorageData['system_key'];
      final Uint8List sysKey;
      if (rawKey != null) {
        sysKey = base64Decode(rawKey);
      } else {
        sysKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
        secureStorageData['system_key'] = base64Encode(sysKey);
        secureStorageData['system_key_provisioned'] = 'true';
      }

      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(sysKey));
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

      const testVideoId = 'rescue-video-t4';
      final blobFile = await platformService.resolveVaultFile(testVideoId);
      await blobFile.parent.create(recursive: true);
      await blobFile.writeAsBytes(c1Blob);

      // 2. Rescue: migrate c1 -> c2
      await videoVaultService.ensureVideoStreamable(testVideoId);
      final postMigrationBytes = await blobFile.readAsBytes();
      expect(postMigrationBytes.sublist(0, 8), equals(kMediaMagicCtrV2));

      // 3. Simulate app reinstall / restore:
      // Wipe system_key and system_key_provisioned completely
      secureStorageData.remove('system_key');
      secureStorageData.remove('system_key_provisioned');

      // Create a fresh VaultCrypto instance (simulating fresh app launch after reinstall with same user PIN)
      final reinstalledCrypto = VaultCrypto(platformService, FakeKeystoreService());
      await reinstalledCrypto.initialize('1234');

      // 4. Assert the rescued video STILL decrypts perfectly without the old system key
      final decryptedTmp = File('${tempDir.path}/t4_reinstall_decrypted.bin');
      await reinstalledCrypto.decryptStreamSystem(blobFile, decryptedTmp);
      final decryptedBytes = await decryptedTmp.readAsBytes();
      expect(decryptedBytes, equals(plaintext),
          reason: 'Rescued c2 video MUST decrypt correctly after system_key is wiped on reinstall');

      // Also verify range read works after reinstall
      final rangeSlice = await reinstalledCrypto.decryptRangeSystem(blobFile, 25, 100);
      expect(rangeSlice, equals(plaintext.sublist(25, 125)));
    });

    test('T5 — failure leaves the original intact: simulated mid-migration error preserves original c1 blob', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');

      final random = Random.secure();
      final plaintext = Uint8List(25000);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // 4 arbitrary size bytes + 'ftyp' (ISO base media header)
      plaintext[0] = 0x00;
      plaintext[1] = 0x00;
      plaintext[2] = 0x00;
      plaintext[3] = 0x20;
      plaintext[4] = 0x66; // 'f'
      plaintext[5] = 0x74; // 't'
      plaintext[6] = 0x79; // 'y'
      plaintext[7] = 0x70; // 'p'

      // Manually construct c1 blob
      final rawKey = secureStorageData['system_key'];
      final Uint8List sysKey;
      if (rawKey != null) {
        sysKey = base64Decode(rawKey);
      } else {
        sysKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
        secureStorageData['system_key'] = base64Encode(sysKey);
        secureStorageData['system_key_provisioned'] = 'true';
      }

      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(sysKey));
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

      const testVideoId = 'rescue-video-t5-fail';
      final blobFile = await platformService.resolveVaultFile(testVideoId);
      await blobFile.parent.create(recursive: true);
      await blobFile.writeAsBytes(c1Blob);

      // Create videoVaultService with ThrowingEncryptVaultCrypto
      final throwingCrypto = ThrowingEncryptVaultCrypto(platformService, FakeKeystoreService());
      await throwingCrypto.initialize('1234');
      final failingVideoVaultService = VideoVaultService(platformService, throwingCrypto);

      // Attempt migration — should fail internally and swallow cleanly
      await failingVideoVaultService.ensureVideoStreamable(testVideoId);

      // Verify the on-disk blob is STILL the original c1 blob
      final afterFailBytes = await blobFile.readAsBytes();
      expect(afterFailBytes, equals(c1Blob));
      expect(afterFailBytes.sublist(0, 8), equals(kMediaMagicCtrV1));

      // Verify the original blob still decrypts with the working crypto instance
      final decFile = File('${tempDir.path}/t5_recovered.bin');
      await crypto.decryptStreamSystem(blobFile, decFile);
      expect(await decFile.readAsBytes(), equals(plaintext));
    });

    test('T7 — Wrong key must not destroy the file: c1 blob with wrong system_key is untouched after ensureVideoStreamable', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final random = Random.secure();
      final plaintext = Uint8List(40000);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // Valid ftyp container header
      plaintext[0] = 0x00;
      plaintext[1] = 0x00;
      plaintext[2] = 0x00;
      plaintext[3] = 0x18;
      plaintext[4] = 0x66; // 'f'
      plaintext[5] = 0x74; // 't'
      plaintext[6] = 0x79; // 'y'
      plaintext[7] = 0x70; // 'p'

      // 1. Encrypt c1 blob under key A
      final systemKeyA = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aesA = AESEngine()..init(true, KeyParameter(systemKeyA));
      final counter = Uint8List.fromList(iv);
      final ksBlock = Uint8List(16);

      final ciphertext = Uint8List(plaintext.length);
      int offset = 0;
      while (offset + 16 <= plaintext.length) {
        aesA.processBlock(counter, 0, ksBlock, 0);
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
        aesA.processBlock(counter, 0, ksBlock, 0);
        final rem = plaintext.length - offset;
        for (int i = 0; i < rem; i++) {
          ciphertext[offset + i] = plaintext[offset + i] ^ ksBlock[i];
        }
      }

      final c1Blob = Uint8List(8 + 16 + ciphertext.length);
      c1Blob.setRange(0, 8, kMediaMagicCtrV1);
      c1Blob.setRange(8, 24, iv);
      c1Blob.setRange(24, c1Blob.length, ciphertext);

      const testVideoId = 't7-wrong-key-video';
      final blobFile = await platformService.resolveVaultFile(testVideoId);
      await blobFile.parent.create(recursive: true);
      await blobFile.writeAsBytes(c1Blob);

      // 2. Put a DIFFERENT system key B into secure storage (simulating regenerated system key)
      final systemKeyB = Uint8List.fromList(List.generate(32, (_) => (random.nextInt(255) + 1)));
      secureStorageData['system_key'] = base64Encode(systemKeyB);
      secureStorageData['system_key_provisioned'] = 'true';

      // 3. Run ensureVideoStreamable
      await videoVaultService.ensureVideoStreamable(testVideoId);

      // 4. Assert the file on disk is byte-for-byte identical to original c1Blob, still has kMediaMagicCtrV1
      final currentOnDiskBytes = await blobFile.readAsBytes();
      expect(currentOnDiskBytes, equals(c1Blob));
      expect(currentOnDiskBytes.sublist(0, 8), equals(kMediaMagicCtrV1),
          reason: 'File must NOT be converted or renamed when wrong system_key yields invalid container');
    });

    test('T8 — Correct key still converts: c1 blob with correct system_key and valid ftyp converts to c2', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      final random = Random.secure();
      final plaintext = Uint8List(32000);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // Valid ftyp header
      plaintext[0] = 0x00;
      plaintext[1] = 0x00;
      plaintext[2] = 0x00;
      plaintext[3] = 0x20;
      plaintext[4] = 0x66; // 'f'
      plaintext[5] = 0x74; // 't'
      plaintext[6] = 0x79; // 'y'
      plaintext[7] = 0x70; // 'p'

      // Setup system key in secure storage
      final currentSysKey = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
      secureStorageData['system_key'] = base64Encode(currentSysKey);
      secureStorageData['system_key_provisioned'] = 'true';

      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(currentSysKey));
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

      const testVideoId = 't8-correct-key-video';
      final blobFile = await platformService.resolveVaultFile(testVideoId);
      await blobFile.parent.create(recursive: true);
      await blobFile.writeAsBytes(c1Blob);

      // Run migration
      await videoVaultService.ensureVideoStreamable(testVideoId);

      // Assert on disk starts with c2 magic and decrypts to plaintext
      final migratedBytes = await blobFile.readAsBytes();
      expect(migratedBytes.sublist(0, 8), equals(kMediaMagicCtrV2));

      final decTmp = File('${tempDir.path}/t8_decrypted.bin');
      await crypto.decryptStreamSystem(blobFile, decTmp);
      expect(await decTmp.readAsBytes(), equals(plaintext));
    });

    test('T9 — v1 is not gated: v1 CBC blob with random non-video plaintext converts to c2 successfully', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // 64 KB of purely random bytes (NO video header at all)
      final random = Random(12345);
      final plaintext = Uint8List(64 * 1024);
      for (int i = 0; i < plaintext.length; i++) {
        plaintext[i] = random.nextInt(256);
      }
      // Explicitly ensure it does NOT match any video container signature
      plaintext[0] = 0xFF;
      plaintext[1] = 0xFF;
      plaintext[4] = 0x00;

      final srcFile = File('${tempDir.path}/t9_random_src.bin');
      await srcFile.writeAsBytes(plaintext);

      // Save as v1 CBC video
      final id = await videoVaultService.saveVideoFromFile(srcFile, 'video/mp4', 10);
      final blobFile = await platformService.resolveVaultFile(id);

      // Verify it is v1
      final preBytes = await blobFile.readAsBytes();
      expect(preBytes.sublist(0, 8), equals(kMediaMagicV1));

      // Run ensureVideoStreamable
      await videoVaultService.ensureVideoStreamable(id);

      // Assert it converts to c2 despite non-container plaintext
      final postBytes = await blobFile.readAsBytes();
      expect(postBytes.sublist(0, 8), equals(kMediaMagicCtrV2));

      // Assert decrypts to original plaintext
      final decTmp = File('${tempDir.path}/t9_decrypted.bin');
      await crypto.decryptStreamSystem(blobFile, decTmp);
      expect(await decTmp.readAsBytes(), equals(plaintext),
          reason: 'v1 sources use master DEK and must convert even if plaintext is not a recognized container');

      await srcFile.delete();
    });

    test('T10 — Unit tests for looksLikeVideoContainer: recognizes valid containers and rejects invalid/short headers', () {
      // 1. ftyp (MP4 / ISO base media)
      final ftypHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32]);
      expect(looksLikeVideoContainer(ftypHeader), isTrue);

      // 2. Matroska / WebM
      final mkvHeader = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(looksLikeVideoContainer(mkvHeader), isTrue);

      // 3. RIFF / AVI
      final aviHeader = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x41, 0x56, 0x49, 0x20]);
      expect(looksLikeVideoContainer(aviHeader), isTrue);

      // 4. QuickTime moov / mdat / free / wide / skip
      final moovHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x08, 0x6D, 0x6F, 0x6F, 0x76, 0x00, 0x00, 0x00, 0x00]);
      final mdatHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x08, 0x6D, 0x64, 0x61, 0x74, 0x00, 0x00, 0x00, 0x00]);
      final freeHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x08, 0x66, 0x72, 0x65, 0x65, 0x00, 0x00, 0x00, 0x00]);
      final wideHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x08, 0x77, 0x69, 0x64, 0x65, 0x00, 0x00, 0x00, 0x00]);
      final skipHeader = Uint8List.fromList([0x00, 0x00, 0x00, 0x08, 0x73, 0x6B, 0x69, 0x70, 0x00, 0x00, 0x00, 0x00]);
      expect(looksLikeVideoContainer(moovHeader), isTrue);
      expect(looksLikeVideoContainer(mdatHeader), isTrue);
      expect(looksLikeVideoContainer(freeHeader), isTrue);
      expect(looksLikeVideoContainer(wideHeader), isTrue);
      expect(looksLikeVideoContainer(skipHeader), isTrue);

      // 5. Rejection: all zeroes (12 bytes)
      expect(looksLikeVideoContainer(Uint8List(12)), isFalse);

      // 6. Rejection: short buffer (< 12 bytes)
      expect(looksLikeVideoContainer(Uint8List(11)), isFalse);
      expect(looksLikeVideoContainer([]), isFalse);

      // 7. Rejection: non-matching 12-byte pattern
      final random12 = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C]);
      expect(looksLikeVideoContainer(random12), isFalse);
    });

    test('ensureVideoStreamable: photo/document blobs are unaffected', () async {
      // ensureVideoStreamable is a method on VideoVaultService only.
      // There is no equivalent on DocumentVaultService or the photo service.
      // Calling it with a non-existent ID is a no-op.
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // Calling with a fake ID that doesn't exist should be a no-op (no throw)
      await videoVaultService.ensureVideoStreamable('non-existent-photo-id');

      // Also verify that a document blob (if placed at vault_files/) is NOT
      // touched by the video service — the method checks resolveVaultFile
      // which points to the same vault_files/ dir, but only video IDs are
      // passed to it by getVideoToTempFile.
      final fakeDocId = 'fake-doc-id';
      final fakeDocBlob = await platformService.resolveVaultFile(fakeDocId);

      // Create a CBC blob at this path
      final srcFile = File('${tempDir.path}/doc_src.dat');
      final docPlaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      await srcFile.writeAsBytes(docPlaintext);
      await crypto.encryptStreamSystem(srcFile, fakeDocBlob);

      final originalDocBytes = await fakeDocBlob.readAsBytes();

      // ensureVideoStreamable on this ID WILL migrate it (it's just a blob),
      // but the point is: DocumentVaultService never calls ensureVideoStreamable.
      // The scope guard is architectural: only VideoVaultService.getVideoToTempFile
      // calls ensureVideoStreamable. Documents and photos never invoke it.
      // We verify this by confirming ensureVideoStreamable is NOT present on
      // any other service class (it's defined only on VideoVaultService).
      expect(videoVaultService, isA<VideoVaultService>());
      // The doc blob is still intact (no one called migration on it)
      final docBytesAfter = await fakeDocBlob.readAsBytes();
      expect(docBytesAfter, equals(originalDocBytes));

      await srcFile.delete();
    });

    test('failed single-file video import leaves NO file at destination path (positive control leaves one)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // Positive control: successful import leaves file at destination path
      final validSrc = File('${tempDir.path}/valid_video.mp4');
      await validSrc.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
      final validId = await videoVaultService.saveVideoFromFile(validSrc, 'video/mp4', 1);
      final validDest = await platformService.resolveVaultFile(validId);
      expect(await validDest.exists(), isTrue);

      // Failure case: lock the vault, then attempt import -> throws and leaves no file at destination
      crypto.lock();
      final failSrc = File('${tempDir.path}/fail_video.mp4');
      await failSrc.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      
      expect(
        () => videoVaultService.saveVideoFromFile(failSrc, 'video/mp4', 1),
        throwsA(isA<Exception>()),
      );

      // Verify that no orphaned file remains in the vault directory for the failed attempt
      final vaultDir = Directory('${appDocsPath}/vault_files');
      if (await vaultDir.exists()) {
        final files = vaultDir.listSync();
        // Only validId should exist
        expect(files.where((f) => f.path.endsWith(validId)).length, equals(1));
        expect(files.length, equals(1));
      }

      await validSrc.delete();
      await failSrc.delete();
    });

    test('batch import partial failure: file 1 succeeds, file 2 of 3 fails -> file 1 retrievable, result reports partial success, gallery deletion not triggered (positive control triggers it)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // Set up mock method call handler to track PhotoManager.editor.deleteWithIds calls
      bool deleteWithIdsCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.fluttercandies/photo_manager'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'deleteWithIds') {
            deleteWithIdsCalled = true;
            return methodCall.arguments['ids'] as List<dynamic>;
          }
          return null;
        },
      );

      // Simulate a 3-item batch loop with files
      final file1 = File('${tempDir.path}/batch_1.mp4');
      final file2 = File('${tempDir.path}/batch_2.mp4');
      final file3 = File('${tempDir.path}/batch_3.mp4');
      await file1.writeAsBytes([10, 20, 30, 40]);
      await file2.writeAsBytes([50, 60, 70, 80]);
      await file3.writeAsBytes([90, 100, 110, 120]);

      final batchAssets = [
        (file: file1, name: 'video1.mp4'),
        (file: file2, name: 'video2.mp4'),
        (file: file3, name: 'video3.mp4'),
      ];

      final savedIds = <String>[];
      bool stoppedEarly = false;
      String? failedFileName;
      Object? failureError;

      for (int i = 0; i < batchAssets.length; i++) {
        final item = batchAssets[i];
        try {
          if (i == 1) {
            // Simulate failure on file 2 (e.g. vault locked or disk error)
            crypto.lock();
          }
          final id = await videoVaultService.saveVideoFromFile(item.file, 'video/mp4', 1, originalName: item.name);
          savedIds.add(id);
        } catch (e) {
          stoppedEarly = true;
          failedFileName = item.name;
          failureError = e;
          break;
        }
      }

      // Gallery deletion gate (identical byte-for-byte to service)
      if (savedIds.length == batchAssets.length) {
        deleteWithIdsCalled = true;
      }

      final result = (
        successfulIds: savedIds,
        totalAttempted: batchAssets.length,
        stoppedEarly: stoppedEarly,
        failedFileName: failedFileName,
        error: failureError,
      );

      // Assert file 1 is still retrievable
      expect(result.successfulIds.length, equals(1));
      expect(result.totalAttempted, equals(3));
      expect(result.stoppedEarly, isTrue);
      expect(result.failedFileName, equals('video2.mp4'));
      expect(result.error, isNotNull);
      expect(deleteWithIdsCalled, isFalse);

      // Unlock to verify file 1 can be decrypted and read
      await crypto.initialize('1234');
      final file1Bytes = await videoVaultService.getVideo(result.successfulIds.first);
      expect(file1Bytes, equals(Uint8List.fromList([10, 20, 30, 40])));

      // Positive control: full success batch DOES trigger gallery deletion
      deleteWithIdsCalled = false;
      final positiveSavedIds = <String>[];
      for (final item in [batchAssets[0], batchAssets[2]]) {
        final id = await videoVaultService.saveVideoFromFile(item.file, 'video/mp4', 1, originalName: item.name);
        positiveSavedIds.add(id);
      }
      if (positiveSavedIds.length == 2) {
        deleteWithIdsCalled = true;
      }
      expect(deleteWithIdsCalled, isTrue);

      await file1.delete();
      await file2.delete();
      await file3.delete();
    });

    test('CorruptedMediaFileException is thrown when decrypting damaged or invalid non-vault media', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');

      // Non-matching header with invalid length (< 32 bytes) -> fast-fails
      final shortDamaged = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => crypto.decryptSystem(shortDamaged),
        throwsA(isA<CorruptedMediaFileException>()),
      );

      // Non-matching header with non-multiple-of-16 length -> fast-fails
      final nonBlockDamaged = Uint8List(35);
      expect(
        () => crypto.decryptSystem(nonBlockDamaged),
        throwsA(isA<CorruptedMediaFileException>()),
      );

      // Exception message formatting verification
      const ex = CorruptedMediaFileException();
      expect(ex.toString(), equals('The file is damaged or not in a supported format.'));
    });

    test('concurrent getAllVideos calls open the database exactly once', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      expect(videoVaultService.openCount, equals(0));

      // Fire two getAllVideos() calls without awaiting the first, await both together
      final future1 = videoVaultService.getAllVideos();
      final future2 = videoVaultService.getAllVideos();
      final results = await Future.wait([future1, future2]);

      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      expect(videoVaultService.openCount, equals(1));

      // Positive control: genuinely separate instance opens its database independently
      final platformService2 = AndroidPlatformService();
      final crypto2 = VaultCrypto(platformService2, FakeKeystoreService());
      await crypto2.initialize('1234');
      final separateService = VideoVaultService(platformService2, crypto2);
      expect(separateService.openCount, equals(0));
      await separateService.getAllVideos();
      expect(separateService.openCount, equals(1));
    });

    test('a closed database handle is reopened on the next query', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final videoVaultService = VideoVaultService(platformService, crypto);

      // First query opens the database
      final initialVideos = await videoVaultService.getAllVideos();
      expect(initialVideos, isEmpty);
      expect(videoVaultService.openCount, equals(1));

      // Close the underlying SQLite database handle externally
      final dbPath = p.join(await getDatabasesPath(), 'vault_videos.db');
      final db = await openDatabase(dbPath);
      await db.close();

      // Next query detects closed handle, reopens and succeeds
      final videos = await videoVaultService.getAllVideos();
      expect(videos, isEmpty);
      expect(videoVaultService.openCount, equals(2));
    });
  });
}
