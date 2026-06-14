import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      final crypto = VaultCrypto(platformService);
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
      final crypto = VaultCrypto(platformService);
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
  });
}
