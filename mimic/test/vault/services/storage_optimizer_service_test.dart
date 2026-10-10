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
  });
}
