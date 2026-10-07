// test/vault/services/media_integrity_service_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/media_integrity_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';

class _FakeKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {}
  @override
  Future<String> wrap(String base64Data) async => 'hw1:$base64Data';
  @override
  Future<String> unwrap(String base64Data) async =>
      base64Data.startsWith('hw1:') ? base64Data.substring(4) : base64Data;
  @override
  Future<void> deleteKey() async {}
}

class _FakePlatformService implements PlatformService {
  final Directory vaultDir;
  final Map<String, String> secureStorage = {};
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
  Future<Uint8List?> readEncryptedFile(String path) async {
    final file = await resolveVaultFile(path);
    if (await file.exists()) return await file.readAsBytes();
    return null;
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    final file = await resolveVaultFile(path);
    await file.writeAsBytes(data);
  }

  @override
  Future<void> secureDelete(String key) async => secureStorage.remove(key);

  @override
  Future<String?> secureRead(String key) async => secureStorage[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(secureStorage);

  @override
  Future<void> secureWrite(String key, String value) async => secureStorage[key] = value;
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
  late _FakeKeystoreService keystore;
  late VaultCrypto crypto;
  late _FakeFileVaultService fileVault;
  late _FakeVideoVaultService videoVault;
  late _FakeDocumentVaultService docVault;
  late MediaIntegrityService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mimic_integrity_test_');
    vaultDir = Directory(p.join(tempRoot.path, 'vault_files'));
    await vaultDir.create(recursive: true);

    platform = _FakePlatformService(vaultDir);
    keystore = _FakeKeystoreService();
    crypto = VaultCrypto(platform, keystore);
    await crypto.initialize('1234');

    fileVault = _FakeFileVaultService();
    videoVault = _FakeVideoVaultService();
    docVault = _FakeDocumentVaultService();

    service = MediaIntegrityService(platform, crypto, fileVault, videoVault, docVault);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('F10: Mid-File Integrity Verification', () {
    test('healthy c3 blob verifies as healthy', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final encrypted = await crypto.encryptSystem(plaintext);

      final file = File(p.join(vaultDir.path, 'valid-c3-blob'));
      await file.writeAsBytes(encrypted);

      final report = await service.checkBlob('valid-c3-blob');
      expect(report.status, equals(BlobIntegrityStatus.healthy));
      expect(report.isHealthy, isTrue);
      expect(report.fileSizeBytes, equals(encrypted.length));
    });

    test('tampered c3 blob with single bit flipped in ciphertext fails with tamperedOrCorrupted', () async {
      final plaintext = Uint8List.fromList([10, 20, 30, 40, 50]);
      final encrypted = await crypto.encryptSystem(plaintext);

      // Flip bit at offset 60 (well into ciphertext payload, after 56-byte header)
      final tampered = Uint8List.fromList(encrypted);
      tampered[58] ^= 0x01;

      final file = File(p.join(vaultDir.path, 'tampered-c3-blob'));
      await file.writeAsBytes(tampered);

      final report = await service.checkBlob('tampered-c3-blob');
      expect(report.status, equals(BlobIntegrityStatus.tamperedOrCorrupted));
      expect(report.isHealthy, isFalse);
    });

    test('truncated c3 blob fails verification', () async {
      final plaintext = Uint8List.fromList(List.generate(100, (i) => i));
      final encrypted = await crypto.encryptSystem(plaintext);

      // Truncate last 20 bytes
      final truncated = encrypted.sublist(0, encrypted.length - 20);

      final file = File(p.join(vaultDir.path, 'truncated-c3-blob'));
      await file.writeAsBytes(truncated);

      final report = await service.checkBlob('truncated-c3-blob');
      expect(report.status, equals(BlobIntegrityStatus.tamperedOrCorrupted));
      expect(report.isHealthy, isFalse);
    });

    test('healthy cbcV1 blob with 16-byte aligned payload verifies as healthy', () async {
      // 8 bytes magic + 16 bytes IV + 32 bytes ciphertext (multiple of 16)
      final cbcBlob = Uint8List(24 + 32);
      cbcBlob.setRange(0, 8, kMediaMagicV1);
      // Fill random IV and dummy blocks
      for (int i = 8; i < cbcBlob.length; i++) {
        cbcBlob[i] = i & 0xFF;
      }

      final file = File(p.join(vaultDir.path, 'valid-cbc-blob'));
      await file.writeAsBytes(cbcBlob);

      final report = await service.checkBlob('valid-cbc-blob');
      expect(report.status, equals(BlobIntegrityStatus.healthy));
      expect(report.isHealthy, isTrue);
    });

    test('truncated cbcV1 blob (misaligned payload) fails with truncatedPayload', () async {
      // 8 bytes magic + 16 bytes IV + 25 bytes ciphertext (25 % 16 != 0)
      final badCbcBlob = Uint8List(24 + 25);
      badCbcBlob.setRange(0, 8, kMediaMagicV1);

      final file = File(p.join(vaultDir.path, 'bad-cbc-blob'));
      await file.writeAsBytes(badCbcBlob);

      final report = await service.checkBlob('bad-cbc-blob');
      expect(report.status, equals(BlobIntegrityStatus.truncatedPayload));
      expect(report.isHealthy, isFalse);
    });

    test('missing file reports fileNotFound', () async {
      final report = await service.checkBlob('does-not-exist');
      expect(report.status, equals(BlobIntegrityStatus.fileNotFound));
      expect(report.isHealthy, isFalse);
    });

    test('file smaller than 8 bytes reports fileTooShort', () async {
      final tinyFile = File(p.join(vaultDir.path, 'tiny-file'));
      await tinyFile.writeAsBytes([1, 2, 3]);

      final report = await service.checkBlob('tiny-file');
      expect(report.status, equals(BlobIntegrityStatus.fileTooShort));
      expect(report.isHealthy, isFalse);
    });

    test('locked vault reports vaultLocked for c3 blobs', () async {
      final encrypted = await crypto.encryptSystem(Uint8List.fromList([1, 2, 3, 4]));
      final file = File(p.join(vaultDir.path, 'c3-locked'));
      await file.writeAsBytes(encrypted);

      crypto.lock();

      final report = await service.checkBlob('c3-locked');
      expect(report.status, equals(BlobIntegrityStatus.vaultLocked));
    });

    test('verifyAllMedia sweeps all categories and produces accurate summary', () async {
      // 1 healthy photo
      final photoEncrypted = await crypto.encryptSystem(Uint8List.fromList([10, 20, 30]));
      await File(p.join(vaultDir.path, 'photo-1')).writeAsBytes(photoEncrypted);
      fileVault.photos = [
        PhotoMeta(id: 'photo-1', mimeType: 'image/jpeg', size: 3, createdAt: DateTime.now())
      ];

      // 1 corrupted video (tampered bit)
      final videoEncrypted = await crypto.encryptSystem(Uint8List.fromList([40, 50, 60]));
      final tamperedVideo = Uint8List.fromList(videoEncrypted);
      tamperedVideo[57] ^= 0xFF;
      await File(p.join(vaultDir.path, 'video-2')).writeAsBytes(tamperedVideo);
      videoVault.videos = [
        VideoMeta(id: 'video-2', mimeType: 'video/mp4', durationS: 10, size: 3, createdAt: DateTime.now())
      ];

      // 1 missing document
      docVault.documents = [
        DocumentMeta(id: 'doc-3', fileName: 'missing.pdf', fileType: 'pdf', sizeBytes: 100, addedAt: DateTime.now())
      ];

      final summary = await service.verifyAllMedia();

      expect(summary.totalChecked, equals(3));
      expect(summary.healthyCount, equals(1));
      expect(summary.corruptedCount, equals(2));
      expect(summary.hasIssues, isTrue);
      expect(summary.issues.length, equals(2));

      final issueIds = summary.issues.map((i) => i.id).toList();
      expect(issueIds, containsAll(['video-2', 'doc-3']));
    });
  });
}
