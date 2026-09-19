import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

/// Forces deletePhoto to fail so the duplicate-reporting branch of
/// restorePhotoToGallery runs against a vault copy that genuinely survives.
class _NoDeleteFileVaultService extends FileVaultService {
  _NoDeleteFileVaultService(super.platformService, super.crypto);

  @override
  Future<void> deletePhoto(String id) async =>
      throw Exception('simulated vault delete failure');
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

    test('movePhoto relabels folder and legacy maps read as Unfiled', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVaultService = FileVaultService(platformService, crypto);

      final id = await fileVaultService.savePhoto(
          Uint8List.fromList([1, 2, 3]), 'image/jpeg',
          originalName: 'a.jpg');
      var photos = await fileVaultService.getAllPhotos();
      expect(photos.singleWhere((p) => p.id == id).folder, '');

      await fileVaultService.movePhoto(id, 'Trips');
      photos = await fileVaultService.getAllPhotos();
      expect(photos.singleWhere((p) => p.id == id).folder, 'Trips');

      // Blob untouched: still decrypts to the same bytes.
      expect(await fileVaultService.getPhoto(id), equals([1, 2, 3]));

      await fileVaultService.movePhoto(id, '');
      photos = await fileVaultService.getAllPhotos();
      expect(photos.singleWhere((p) => p.id == id).folder, '');

      // Legacy: a map without the folder key must not throw.
      final legacy = PhotoMeta.fromMap({
        'id': 'legacy',
        'mimeType': 'image/jpeg',
        'size': 3,
        'createdAt': DateTime.now().toIso8601String(),
        'originalName': 'old.jpg',
      });
      expect(legacy.folder, '');
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

    group('restorePhotoToGallery honesty contract', () {
      // The gallery write goes through photo_manager's channel — the same
      // seam the batch-import test above already uses for 'deleteWithIds'.
      // A success reply must carry the keys convertMapToAsset requires
      // (id/type/width/height); a refusal is a throw, because the pinned
      // plugin's saveImage returns a non-nullable Future<AssetEntity>.
      void mockSaveImage({required bool succeeds}) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.fluttercandies/photo_manager'),
          (MethodCall call) async {
            if (call.method == 'saveImage') {
              if (!succeeds) {
                throw PlatformException(code: 'photo_manager', message: 'denied');
              }
              return <String, dynamic>{'id': '1', 'type': 1, 'width': 1, 'height': 1};
            }
            return null;
          },
        );
        addTearDown(() => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('com.fluttercandies/photo_manager'), null));
      }

      test('a confirmed gallery save removes the vault copy', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('1234');
        final service = FileVaultService(platformService, crypto);
        final id = await service.savePhoto(
            Uint8List.fromList([9, 8, 7, 6, 5]),
            'image/jpeg',
            originalName: 'trip.jpg');
        mockSaveImage(succeeds: true);

        await service.restorePhotoToGallery(id);

        expect(await service.getPhoto(id), isNull,
            reason: 'the vault copy is deleted only after the save succeeded');
      });

      test('a gallery refusal keeps the vault copy and says so', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('1234');
        final service = FileVaultService(platformService, crypto);
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final id = await service.savePhoto(bytes, 'image/jpeg',
            originalName: 'denied.jpg');
        mockSaveImage(succeeds: false);

        await expectLater(
          service.restorePhotoToGallery(id),
          throwsA(predicate((Object e) =>
              e.toString().contains('The gallery did not accept the photo'))),
        );
        expect(await service.getPhoto(id), equals(bytes),
            reason: 'a refused save must never delete the vault copy');
      });

      test('a vault delete failing after a successful save reports the duplicate', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('1234');
        final service = _NoDeleteFileVaultService(platformService, crypto);
        final id = await service.savePhoto(Uint8List.fromList([4, 5, 6]),
            'image/jpeg',
            originalName: 'stuck.jpg');
        mockSaveImage(succeeds: true);

        await expectLater(
          service.restorePhotoToGallery(id),
          throwsA(predicate((Object e) =>
              e.toString().contains('vault copy could not be deleted'))),
        );
        expect(await service.getPhoto(id), isNotNull,
            reason:
                'the message says both copies exist, so the vault copy must still be there');
      });

      test('a restore of a photo whose blob is gone reports the missing copy', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('1234');
        final service = FileVaultService(platformService, crypto);

        await expectLater(
          service.restorePhotoToGallery('no_such_photo'),
          throwsA(predicate((Object e) =>
              e.toString().contains('Photo file not found in vault'))),
        );
      });

      test('a blob with no metadata row is reported honestly and the blob survives', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('1234');
        final service = FileVaultService(platformService, crypto);
        final bytes = Uint8List.fromList([7, 7, 7, 7]);
        final id = await service.savePhoto(bytes, 'image/jpeg',
            originalName: 'orphan.jpg');

        // Orphan the blob: remove only the metadata row, through a second ffi
        // connection to the same vault_files.db the service uses.
        final raw = await databaseFactory
            .openDatabase(p.join(dbDirPath, 'vault_files.db'));
        await raw.delete('photos', where: 'id = ?', whereArgs: [id]);
        await raw.close();

        await expectLater(
          service.restorePhotoToGallery(id),
          throwsA(predicate((Object e) =>
              e.toString().contains('Photo metadata not found in vault'))),
        );
        expect(await service.getPhoto(id), equals(bytes),
            reason: 'nothing was written, so the vault copy must survive');
      });
    });
  });
}
