import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/storage_optimizer_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> secureRead(String key) async => _storage[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(_storage);

  @override
  Future<void> secureWrite(String key, String value) async => _storage[key] = value;

  @override
  Future<void> secureDelete(String key) async => _storage.remove(key);

  @override
  Future<void> deleteFile(String path) async {}

  @override
  bool isWeb() => false;

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

class FakeKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async => base64Data;

  @override
  Future<String> unwrap(String base64Data) async => base64Data;

  @override
  Future<void> deleteKey() async {}
}

class FakeFileVaultService extends FileVaultService {
  final List<PhotoMeta> photos = [];
  final List<String> deletedIds = [];

  FakeFileVaultService(super.platformService, super.crypto);

  @override
  Future<List<PhotoMeta>> getAllPhotos() async => photos;

  @override
  Future<Uint8List?> readFile(String id) async => null;

  @override
  Future<void> updatePhotoHash(String id, String hash) async {}

  @override
  Future<void> deletePhoto(String id) async {
    deletedIds.add(id);
    photos.removeWhere((p) => p.id == id);
  }
}

class FakeVideoVaultService extends VideoVaultService {
  final List<VideoMeta> videos = [];
  final List<String> deletedIds = [];

  FakeVideoVaultService(super.platformService, super.crypto);

  @override
  Future<List<VideoMeta>> getAllVideos() async => videos;

  @override
  Future<Uint8List?> getVideo(String id) async => null;

  @override
  Future<void> updateVideoHash(String id, String hash) async {}

  @override
  Future<void> deleteVideo(String id) async {
    deletedIds.add(id);
    videos.removeWhere((v) => v.id == id);
  }
}

class FakeDocumentVaultService extends DocumentVaultService {
  final List<DocumentMeta> docs = [];
  final List<String> deletedIds = [];

  FakeDocumentVaultService(super.platformService, super.crypto);

  @override
  Future<List<DocumentMeta>> listDocuments() async => docs;

  @override
  Future<void> deleteDocument(String id) async {
    deletedIds.add(id);
    docs.removeWhere((d) => d.id == id);
  }
}

void main() {
  group('StorageOptimizerService Tests', () {
    late FakePlatformService fakePlatform;
    late VaultCrypto crypto;
    late FakeFileVaultService fakePhotos;
    late FakeVideoVaultService fakeVideos;
    late FakeDocumentVaultService fakeDocs;
    late StorageOptimizerService optimizer;

    setUp(() async {
      fakePlatform = FakePlatformService();
      crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto.initialize('1234');

      fakePhotos = FakeFileVaultService(fakePlatform, crypto);
      fakeVideos = FakeVideoVaultService(fakePlatform, crypto);
      fakeDocs = FakeDocumentVaultService(fakePlatform, crypto);
      optimizer = StorageOptimizerService(
        fileVaultService: fakePhotos,
        videoVaultService: fakeVideos,
        docVaultService: fakeDocs,
      );
    });

    test('analyzeVault returns empty report when vault has no items', () async {
      final report = await optimizer.analyzeVault();
      expect(report.totalBytes, equals(0));
      expect(report.photoCount, equals(0));
      expect(report.videoCount, equals(0));
      expect(report.docCount, equals(0));
      expect(report.largeFiles, isEmpty);
      expect(report.duplicateGroups, isEmpty);
      expect(report.potentialDuplicateSavings, equals(0));
    });

    test('analyzeVault computes sizes and detects large files & duplicates', () async {
      fakePhotos.photos.addAll([
        PhotoMeta(
          id: 'p1',
          mimeType: 'image/jpeg',
          size: 5 * 1024 * 1024,
          createdAt: DateTime.now(),
          originalName: 'IMG_001.jpg',
        ),
        // Duplicate of IMG_001.jpg
        PhotoMeta(
          id: 'p2',
          mimeType: 'image/jpeg',
          size: 5 * 1024 * 1024,
          createdAt: DateTime.now(),
          originalName: 'IMG_001.jpg',
        ),
      ]);

      fakeVideos.videos.addAll([
        VideoMeta(
          id: 'v1',
          originalName: 'Vacation_4K.mp4',
          size: 35 * 1024 * 1024, // 35 MB (> 20 MB threshold)
          createdAt: DateTime.now(),
          mimeType: 'video/mp4',
          durationS: 12,
        ),
      ]);

      fakeDocs.docs.addAll([
        DocumentMeta(
          id: 'd1',
          fileName: 'Manual.pdf',
          fileType: 'application/pdf',
          sizeBytes: 1024 * 1024,
          addedAt: DateTime.now(),
        ),
      ]);

      final report = await optimizer.analyzeVault(largeFileThreshold: 20 * 1024 * 1024);

      expect(report.photoCount, equals(2));
      expect(report.videoCount, equals(1));
      expect(report.docCount, equals(1));
      expect(report.photosBytes, equals(10 * 1024 * 1024));
      expect(report.videosBytes, equals(35 * 1024 * 1024));
      expect(report.docsBytes, equals(1 * 1024 * 1024));
      expect(report.totalBytes, equals(46 * 1024 * 1024));

      // Large files
      expect(report.largeFiles.length, equals(1));
      expect(report.largeFiles.first.id, equals('v1'));
      expect(report.largeFiles.first.name, equals('Vacation_4K.mp4'));

      // Duplicates
      expect(report.duplicateGroups.length, equals(1));
      expect(report.duplicateGroups.first.files.length, equals(2));
      expect(report.potentialDuplicateSavings, equals(5 * 1024 * 1024));
    });

    test('deleteOptimizableFile deletes the file from correct vault service', () async {
      fakePhotos.photos.add(
        PhotoMeta(
          id: 'p_dup',
          mimeType: 'image/png',
          size: 2048,
          createdAt: DateTime.now(),
          originalName: 'dup.png',
        ),
      );

      final fileToDelete = OptimizableFile(
        id: 'p_dup',
        name: 'dup.png',
        sizeBytes: 2048,
        type: VaultMediaType.photo,
        createdAt: DateTime.now(),
      );

      await optimizer.deleteOptimizableFile(fileToDelete);
      expect(fakePhotos.deletedIds, contains('p_dup'));
      expect(fakePhotos.photos, isEmpty);
    });

    test('deleteOptimizableFiles batch deletes files and returns count', () async {
      fakePhotos.photos.addAll([
        PhotoMeta(
          id: 'p_batch_1',
          mimeType: 'image/png',
          size: 1024,
          createdAt: DateTime.now(),
          originalName: 'batch1.png',
        ),
        PhotoMeta(
          id: 'p_batch_2',
          mimeType: 'image/png',
          size: 1024,
          createdAt: DateTime.now(),
          originalName: 'batch2.png',
        ),
      ]);

      final files = [
        OptimizableFile(
          id: 'p_batch_1',
          name: 'batch1.png',
          sizeBytes: 1024,
          type: VaultMediaType.photo,
          createdAt: DateTime.now(),
        ),
        OptimizableFile(
          id: 'p_batch_2',
          name: 'batch2.png',
          sizeBytes: 1024,
          type: VaultMediaType.photo,
          createdAt: DateTime.now(),
        ),
      ];

      final count = await optimizer.deleteOptimizableFiles(files);
      expect(count, equals(2));
      expect(fakePhotos.deletedIds, containsAll(['p_batch_1', 'p_batch_2']));
      expect(fakePhotos.photos, isEmpty);
    });

    test('DuplicateGroup and StorageOptimizationReport getters identify duplicate copies correctly', () {
      final f1 = OptimizableFile(id: '1', name: 'a.png', sizeBytes: 100, type: VaultMediaType.photo, createdAt: DateTime.now());
      final f2 = OptimizableFile(id: '2', name: 'a.png', sizeBytes: 100, type: VaultMediaType.photo, createdAt: DateTime.now());
      final f3 = OptimizableFile(id: '3', name: 'a.png', sizeBytes: 100, type: VaultMediaType.photo, createdAt: DateTime.now());

      final group = DuplicateGroup(key: 'key', sizeBytes: 100, files: [f1, f2, f3]);
      expect(group.originalFile.id, equals('1'));
      expect(group.duplicateCopies.map((f) => f.id), equals(['2', '3']));

      const report = StorageOptimizationReport(
        photosBytes: 300,
        videosBytes: 0,
        docsBytes: 0,
        totalBytes: 300,
        photoCount: 3,
        videoCount: 0,
        docCount: 0,
        largeFiles: [],
        duplicateGroups: [],
      );
      final reportWithGroup = StorageOptimizationReport(
        photosBytes: 300,
        videosBytes: 0,
        docsBytes: 0,
        totalBytes: 300,
        photoCount: 3,
        videoCount: 0,
        docCount: 0,
        largeFiles: const [],
        duplicateGroups: [group],
      );
      expect(reportWithGroup.allDuplicateCopies.map((f) => f.id), equals(['2', '3']));
    });

    test('analyzeVault detects 3 duplicate photos with varying filenames without reading file bytes', () async {
      final now = DateTime.now();
      fakePhotos.photos.addAll([
        PhotoMeta(
          id: 'photo_1',
          mimeType: 'image/jpeg',
          size: 2450123,
          createdAt: now.subtract(const Duration(minutes: 5)),
          originalName: 'IMG_2026.jpg',
        ),
        PhotoMeta(
          id: 'photo_2',
          mimeType: 'image/jpeg',
          size: 2450123,
          createdAt: now.subtract(const Duration(minutes: 3)),
          originalName: 'IMG_2026 (1).jpg',
        ),
        PhotoMeta(
          id: 'photo_3',
          mimeType: 'image/jpeg',
          size: 2450123,
          createdAt: now.subtract(const Duration(minutes: 1)),
          originalName: 'Photo_photo_3',
        ),
        // A unique photo that should NOT be in any duplicate group
        PhotoMeta(
          id: 'photo_unique',
          mimeType: 'image/jpeg',
          size: 3100000,
          createdAt: now,
          originalName: 'unique.jpg',
        ),
      ]);

      final report = await optimizer.analyzeVault();
      expect(report.photoCount, equals(4));
      expect(report.duplicateGroups.length, equals(1));

      final dupGroup = report.duplicateGroups.first;
      expect(dupGroup.files.length, equals(3));
      // Oldest photo is the protected original
      expect(dupGroup.originalFile.id, equals('photo_1'));
      // The other two are marked as duplicate copies
      expect(dupGroup.duplicateCopies.map((f) => f.id).toList(), equals(['photo_2', 'photo_3']));
      expect(report.potentialDuplicateSavings, equals(2 * 2450123));
    });

    test('analyzeVault correctly handles explicit content hashes', () async {
      final now = DateTime.now();
      fakePhotos.photos.addAll([
        PhotoMeta(
          id: 'p_hash_1',
          mimeType: 'image/jpeg',
          size: 1000,
          createdAt: now.subtract(const Duration(seconds: 10)),
          contentHash: 'hash_abc',
        ),
        PhotoMeta(
          id: 'p_hash_2',
          mimeType: 'image/jpeg',
          size: 1000,
          createdAt: now,
          contentHash: 'hash_abc',
        ),
      ]);

      final report = await optimizer.analyzeVault();
      expect(report.duplicateGroups.length, equals(1));
      expect(report.duplicateGroups.first.files.length, equals(2));
      expect(report.duplicateGroups.first.originalFile.id, equals('p_hash_1'));
    });
  });
}
