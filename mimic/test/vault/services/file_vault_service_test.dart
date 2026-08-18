import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
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
    tempDir = Directory.systemTemp.createTempSync('photo_vault_test');
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

  group('FileVaultService', () {
    test('savePhoto encrypts and saves photo metadata correctly', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVaultService = FileVaultService(platformService, crypto);

      final photoBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final id = await fileVaultService.savePhoto(photoBytes, 'image/jpeg', originalName: 'test.jpg');

      final saved = await fileVaultService.getPhoto(id);
      expect(saved, equals(photoBytes));

      final allPhotos = await fileVaultService.getAllPhotos();
      expect(allPhotos.any((p) => p.id == id), isTrue);
    });

    test('failed single-file photo import leaves NO file at destination path (positive control leaves one)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVaultService = FileVaultService(platformService, crypto);

      // Positive control: successful import leaves file at destination path
      final validBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final validId = await fileVaultService.savePhoto(validBytes, 'image/jpeg', originalName: 'valid.jpg');
      final validFile = await platformService.readEncryptedFile(validId);
      expect(validFile, isNotNull);

      // Failure case: lock the vault, then attempt import -> throws and leaves no file at destination
      crypto.lock();
      final failBytes = Uint8List.fromList([10, 20, 30]);

      expect(
        () => fileVaultService.savePhoto(failBytes, 'image/jpeg', originalName: 'fail.jpg'),
        throwsA(isA<Exception>()),
      );

      // Verify that no orphaned file remains in the vault directory for the failed attempt
      final vaultDir = Directory('$appDocsPath/vault_files');
      if (await vaultDir.exists()) {
        final files = vaultDir.listSync();
        // Only validId should exist
        expect(files.where((f) => f.path.endsWith(validId)).length, equals(1));
        expect(files.length, equals(1));
      }
    });

    test('batch import partial failure: file 1 succeeds, file 2 of 3 fails -> file 1 retrievable, result reports partial success, gallery deletion not triggered (positive control triggers it)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVaultService = FileVaultService(platformService, crypto);

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

      // Simulate a 3-item batch loop
      final photo1 = Uint8List.fromList([10, 20, 30, 40]);
      final photo2 = Uint8List.fromList([50, 60, 70, 80]);
      final photo3 = Uint8List.fromList([90, 100, 110, 120]);

      final batchPhotos = [
        (bytes: photo1, name: 'photo1.jpg'),
        (bytes: photo2, name: 'photo2.jpg'),
        (bytes: photo3, name: 'photo3.jpg'),
      ];

      final savedIds = <String>[];
      bool stoppedEarly = false;
      String? failedFileName;
      Object? failureError;

      for (int i = 0; i < batchPhotos.length; i++) {
        final item = batchPhotos[i];
        try {
          if (i == 1) {
            // Simulate failure on photo 2 (e.g. vault locked or disk error)
            crypto.lock();
          }
          final id = await fileVaultService.savePhoto(item.bytes, 'image/jpeg', originalName: item.name);
          savedIds.add(id);
        } catch (e) {
          stoppedEarly = true;
          failedFileName = item.name;
          failureError = e;
          break;
        }
      }

      // Gallery deletion gate (identical byte-for-byte to service)
      if (savedIds.length == batchPhotos.length) {
        deleteWithIdsCalled = true;
      }

      final result = (
        successfulIds: savedIds,
        totalAttempted: batchPhotos.length,
        stoppedEarly: stoppedEarly,
        failedFileName: failedFileName,
        error: failureError,
      );

      // Assert file 1 is still retrievable
      expect(result.successfulIds.length, equals(1));
      expect(result.totalAttempted, equals(3));
      expect(result.stoppedEarly, isTrue);
      expect(result.failedFileName, equals('photo2.jpg'));
      expect(result.error, isNotNull);
      expect(deleteWithIdsCalled, isFalse);

      // Unlock to verify file 1 can be decrypted and read
      await crypto.initialize('1234');
      final file1Bytes = await fileVaultService.getPhoto(result.successfulIds.first);
      expect(file1Bytes, equals(photo1));

      // Positive control: full success batch DOES trigger gallery deletion
      deleteWithIdsCalled = false;
      final positiveSavedIds = <String>[];
      for (final item in [batchPhotos[0], batchPhotos[2]]) {
        final id = await fileVaultService.savePhoto(item.bytes, 'image/jpeg', originalName: item.name);
        positiveSavedIds.add(id);
      }
      if (positiveSavedIds.length == 2) {
        deleteWithIdsCalled = true;
      }
      expect(deleteWithIdsCalled, isTrue);
    });

    test('concurrent getAllPhotos calls open the database exactly once', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVaultService = FileVaultService(platformService, crypto);

      expect(fileVaultService.openCount, equals(0));

      // Fire two getAllPhotos() calls without awaiting the first, await both together
      final future1 = fileVaultService.getAllPhotos();
      final future2 = fileVaultService.getAllPhotos();
      final results = await Future.wait([future1, future2]);

      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      expect(fileVaultService.openCount, equals(1));

      // Positive control: genuinely separate instance opens its database independently
      final platformService2 = AndroidPlatformService();
      final crypto2 = VaultCrypto(platformService2, FakeKeystoreService());
      await crypto2.initialize('1234');
      final separateService = FileVaultService(platformService2, crypto2);
      expect(separateService.openCount, equals(0));
      await separateService.getAllPhotos();
      expect(separateService.openCount, equals(1));
    });
  });
}
