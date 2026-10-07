// test/vault/services/orphan_detection_service_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/orphan_detection_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';

class _FakePlatformService implements PlatformService {
  final Directory vaultDir;
  bool web = false;

  _FakePlatformService(this.vaultDir);

  @override
  bool isWeb() => web;

  @override
  Future<File> resolveVaultFile(String path) async {
    return File(p.join(vaultDir.path, path));
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = await resolveVaultFile(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    final file = await resolveVaultFile(path);
    await file.writeAsBytes(data);
  }

  @override
  Future<void> secureDelete(String key) async {}

  @override
  Future<String?> secureRead(String key) async => null;

  @override
  Future<Map<String, String>> secureReadAll() async => {};

  @override
  Future<void> secureWrite(String key, String value) async {}
}

class _FakeFileVaultService extends Fake implements FileVaultService {
  List<PhotoMeta> photos = [];
  @override
  Future<List<PhotoMeta>> getAllPhotos() async => photos;
}

class _FakeVideoVaultService extends Fake implements VideoVaultService {
  List<VideoMeta> videos = [];
  @override
  Future<List<VideoMeta>> getAllVideos() async => videos;
}

class _FakeDocumentVaultService extends Fake implements DocumentVaultService {
  List<DocumentMeta> documents = [];
  @override
  Future<List<DocumentMeta>> listDocuments() async => documents;
}

void main() {
  late Directory tempRoot;
  late Directory vaultDir;
  late _FakePlatformService platform;
  late _FakeFileVaultService fileVault;
  late _FakeVideoVaultService videoVault;
  late _FakeDocumentVaultService docVault;
  late OrphanDetectionService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mimic_orphan_test_');
    vaultDir = Directory(p.join(tempRoot.path, 'vault_files'));
    await vaultDir.create(recursive: true);

    platform = _FakePlatformService(vaultDir);
    fileVault = _FakeFileVaultService();
    videoVault = _FakeVideoVaultService();
    docVault = _FakeDocumentVaultService();

    service = OrphanDetectionService(platform, fileVault, videoVault, docVault);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('F11: Orphan Detection Service', () {
    test('empty vault reports zero files and zero orphans', () async {
      final result = await service.scanOrphans();

      expect(result.totalFilesOnDisk, equals(0));
      expect(result.trackedFilesOnDisk, equals(0));
      expect(result.unreferencedBlobs, isEmpty);
      expect(result.staleTempFiles, isEmpty);
      expect(result.missingDatabaseIds, isEmpty);
      expect(result.unreferencedBytes, equals(0));
      expect(result.staleTempBytes, equals(0));
      expect(result.hasOrphans, isFalse);
    });

    test('healthy vault with all files matching database IDs reports no orphans', () async {
      final photoId = 'photo-uuid-1';
      final videoId = 'video-uuid-2';
      final docId = 'doc-uuid-3';

      fileVault.photos = [
        PhotoMeta(
          id: photoId,
          mimeType: 'image/jpeg',
          size: 1024,
          createdAt: DateTime.now(),
        )
      ];
      videoVault.videos = [
        VideoMeta(
          id: videoId,
          mimeType: 'video/mp4',
          durationS: 30,
          size: 2048,
          createdAt: DateTime.now(),
        )
      ];
      docVault.documents = [
        DocumentMeta(
          id: docId,
          fileName: 'notes.pdf',
          fileType: 'pdf',
          sizeBytes: 4096,
          addedAt: DateTime.now(),
        )
      ];

      // Write matching files on disk.
      await File(p.join(vaultDir.path, photoId)).writeAsBytes(Uint8List(100));
      await File(p.join(vaultDir.path, videoId)).writeAsBytes(Uint8List(200));
      await File(p.join(vaultDir.path, docId)).writeAsBytes(Uint8List(300));

      final result = await service.scanOrphans();

      expect(result.totalFilesOnDisk, equals(3));
      expect(result.trackedFilesOnDisk, equals(3));
      expect(result.unreferencedBlobs, isEmpty);
      expect(result.staleTempFiles, isEmpty);
      expect(result.missingDatabaseIds, isEmpty);
      expect(result.hasOrphans, isFalse);
    });

    test('detects unreferenced blobs that have no DB rows (ghost files)', () async {
      final activePhotoId = 'active-photo-id';
      fileVault.photos = [
        PhotoMeta(
          id: activePhotoId,
          mimeType: 'image/jpeg',
          size: 50,
          createdAt: DateTime.now(),
        )
      ];

      // Active file
      await File(p.join(vaultDir.path, activePhotoId)).writeAsBytes(Uint8List(50));

      // Ghost files (interrupted import where DB write never happened)
      final ghostId1 = 'ghost-blob-1111';
      final ghostId2 = 'ghost-blob-2222';
      await File(p.join(vaultDir.path, ghostId1)).writeAsBytes(Uint8List(120));
      await File(p.join(vaultDir.path, ghostId2)).writeAsBytes(Uint8List(180));

      final result = await service.scanOrphans();

      expect(result.totalFilesOnDisk, equals(3));
      expect(result.trackedFilesOnDisk, equals(1));
      expect(result.unreferencedBlobs.length, equals(2));
      expect(result.unreferencedBytes, equals(300));
      expect(result.staleTempFiles, isEmpty);
      expect(result.hasOrphans, isTrue);

      final unreferencedNames = result.unreferencedBlobs.map((f) => p.basename(f.path)).toList();
      expect(unreferencedNames, containsAll([ghostId1, ghostId2]));
    });

    test('classifies temp files correctly based on staleness grace period', () async {
      final oldTempFile = File(p.join(vaultDir.path, 'video-123_import_plain_99999'));
      await oldTempFile.writeAsBytes(Uint8List(500));

      // Artificially age the file to 10 minutes ago
      final tenMinutesAgo = DateTime.now().subtract(const Duration(minutes: 10));
      await oldTempFile.setLastModified(tenMinutesAgo);

      // Fresh temp file (e.g. active import started 5 seconds ago)
      final freshTempFile = File(p.join(vaultDir.path, 'video-456_import_ctr_88888'));
      await freshTempFile.writeAsBytes(Uint8List(300));

      final result = await service.scanOrphans(
        tempGracePeriod: const Duration(minutes: 5),
      );

      // Only the old temp file is classified as a stale orphan
      expect(result.staleTempFiles.length, equals(1));
      expect(p.basename(result.staleTempFiles.first.path), equals('video-123_import_plain_99999'));
      expect(result.staleTempBytes, equals(500));

      // The fresh temp file is not treated as unreferenced blob because it is recognized as temp,
      // but is currently within grace period.
      expect(result.unreferencedBlobs, isEmpty);
    });

    test('detects missing database records whose file was deleted from disk', () async {
      fileVault.photos = [
        PhotoMeta(
          id: 'missing-photo-id',
          mimeType: 'image/png',
          size: 999,
          createdAt: DateTime.now(),
        )
      ];

      // Do NOT create file on disk
      final result = await service.scanOrphans();

      expect(result.totalFilesOnDisk, equals(0));
      expect(result.trackedFilesOnDisk, equals(0));
      expect(result.missingDatabaseIds, contains('missing-photo-id'));
    });

    test('purgeOrphans safely deletes unreferenced and stale temp files while preserving active files', () async {
      final activeId = 'active-keep-me';
      fileVault.photos = [
        PhotoMeta(
          id: activeId,
          mimeType: 'image/png',
          size: 100,
          createdAt: DateTime.now(),
        )
      ];

      final activeFile = File(p.join(vaultDir.path, activeId));
      await activeFile.writeAsBytes(Uint8List(100));

      final ghostFile = File(p.join(vaultDir.path, 'ghost-orphan-id'));
      await ghostFile.writeAsBytes(Uint8List(250));

      final staleTemp = File(p.join(vaultDir.path, '_tmp_upload_file.part'));
      await staleTemp.writeAsBytes(Uint8List(150));
      await staleTemp.setLastModified(DateTime.now().subtract(const Duration(minutes: 15)));

      // Perform purge
      final purgeResult = await service.purgeOrphans(
        tempGracePeriod: const Duration(minutes: 5),
      );

      expect(purgeResult.deletedCount, equals(2));
      expect(purgeResult.reclaimedBytes, equals(400)); // 250 + 150
      expect(purgeResult.failedDeletions, isEmpty);

      // Active file MUST survive
      expect(await activeFile.exists(), isTrue);

      // Orphans must be deleted
      expect(await ghostFile.exists(), isFalse);
      expect(await staleTemp.exists(), isFalse);

      // Subsequent scan must be clean
      final rescan = await service.scanOrphans();
      expect(rescan.totalOrphansCount, equals(0));
      expect(rescan.trackedFilesOnDisk, equals(1));
    });

    test('selective purge: purge only unreferenced blobs without deleting temp files', () async {
      final ghostFile = File(p.join(vaultDir.path, 'ghost-1'));
      await ghostFile.writeAsBytes(Uint8List(200));

      final staleTemp = File(p.join(vaultDir.path, 'vid_import_plain_111'));
      await staleTemp.writeAsBytes(Uint8List(300));
      await staleTemp.setLastModified(DateTime.now().subtract(const Duration(minutes: 10)));

      final purgeResult = await service.purgeOrphans(
        deleteUnreferenced: true,
        deleteStaleTemp: false,
        tempGracePeriod: const Duration(minutes: 5),
      );

      expect(purgeResult.deletedCount, equals(1));
      expect(purgeResult.reclaimedBytes, equals(200));
      expect(await ghostFile.exists(), isFalse);
      expect(await staleTemp.exists(), isTrue);
    });

    test('web target gracefully returns empty scan', () async {
      platform.web = true;
      final result = await service.scanOrphans();
      expect(result.totalFilesOnDisk, equals(0));
      expect(result.hasOrphans, isFalse);
    });
  });
}
