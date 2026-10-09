import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/models/vault_tag.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/notes_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:path/path.dart' as p;
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
    tempDir = Directory.systemTemp.createTempSync('locator_test');
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

  group('VaultTag Helper Tests', () {
    test('normalize adds # prefix and cleans string', () {
      expect(VaultTags.normalize('Work'), '#Work');
      expect(VaultTags.normalize('#tax2026'), '#tax2026');
      expect(VaultTags.normalize('  receipts  '), '#receipts');
      expect(VaultTags.normalize(''), '');
      expect(VaultTags.normalize('#'), '');
      expect(VaultTags.normalize('###family'), '#family');
    });

    test('parseList parses comma-separated strings and lists', () {
      expect(VaultTags.parseList('tag1, tag2, #tag3'), ['#tag1', '#tag2', '#tag3']);
      expect(VaultTags.parseList(['tag1', '#tag2']), ['#tag1', '#tag2']);
      expect(VaultTags.parseList(null), <String>[]);
      expect(VaultTags.parseList(''), <String>[]);
    });
  });

  group('Smart Locator Service Integration Tests', () {
    test('FileVaultService updates tags and caption with encrypted storage', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('1234');
      final service = FileVaultService(platform, crypto);

      final photoBytes = Uint8List.fromList([1, 2, 3, 4]);
      final id = await service.savePhoto(photoBytes, 'image/jpeg', originalName: 'license.jpg');

      // Update tags and caption
      await service.updatePhotoDetails(
        id,
        tags: ['#ID', '#Important'],
        caption: 'Driver License Renewal',
      );

      final photos = await service.getAllPhotos();
      final photo = photos.firstWhere((p) => p.id == id);

      expect(photo.tags, ['#ID', '#Important']);
      expect(photo.caption, 'Driver License Renewal');
      expect(photo.originalName, 'license.jpg');

      // Verify raw SQLite database row contains encrypted ciphertext, not plaintext caption
      final db = await databaseFactory.openDatabase(p.join(dbDirPath, 'vault_files.db'));
      final rows = await db.query('photos', where: 'id = ?', whereArgs: [id]);
      expect(rows, isNotEmpty);
      final rawRow = rows.first;
      final rawCaption = rawRow['caption'] as String?;
      expect(rawCaption, isNotNull);
      expect(rawCaption, isNot(equals('Driver License Renewal')),
          reason: 'SEC-06: caption must be encrypted in database');
      await db.close();
    });

    test('VideoVaultService updates tags and caption with encrypted storage', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('1234');
      final service = VideoVaultService(platform, crypto);

      // Create a test video file
      final videoFile = File('${tempDir.path}/test.mp4');
      await videoFile.writeAsBytes([5, 6, 7, 8]);

      final videoId = await service.saveVideoFromFile(
        videoFile,
        'video/mp4',
        1,
        originalName: 'test.mp4',
      );

      await service.updateVideoDetails(
        videoId,
        tags: ['#Family', '#Vacation'],
        caption: 'Beach vacation sunset',
      );

      final videos = await service.getAllVideos();
      final video = videos.firstWhere((v) => v.id == videoId);

      expect(video.tags, ['#Family', '#Vacation']);
      expect(video.caption, 'Beach vacation sunset');

      // Verify raw SQLite database row contains encrypted caption
      final db = await databaseFactory.openDatabase(p.join(dbDirPath, 'vault_videos.db'));
      final rows = await db.query('videos', where: 'id = ?', whereArgs: [videoId]);
      final rawCaption = rows.first['caption'] as String?;
      expect(rawCaption, isNotNull);
      expect(rawCaption, isNot(equals('Beach vacation sunset')));
      await db.close();
    });

    test('DocumentVaultService updates tags and caption with encrypted storage', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('1234');
      final service = DocumentVaultService(platform, crypto);

      final docFile = File('${tempDir.path}/lease.pdf');
      await docFile.writeAsBytes([9, 10, 11, 12]);

      final docId = await service.saveDocumentFromFile(
        docFile,
        'pdf',
        originalName: 'lease.pdf',
      );

      await service.updateDocumentDetails(
        docId,
        tags: ['#Contract', '#Legal'],
        caption: 'Apartment lease 2026',
      );

      final docs = await service.listDocuments();
      final updated = docs.firstWhere((d) => d.id == docId);

      expect(updated.tags, ['#Contract', '#Legal']);
      expect(updated.caption, 'Apartment lease 2026');

      // Verify raw secure storage entry contains encrypted caption and tags (SEC-06)
      final rawMetaJson = secureStorageData['vault_documents_meta'];
      expect(rawMetaJson, isNotNull);
      final List<dynamic> decoded = jsonDecode(rawMetaJson!);
      final storedDoc = decoded.firstWhere((e) => e['id'] == docId);
      final rawCaption = storedDoc['caption'] as String?;
      expect(rawCaption, isNotNull);
      expect(rawCaption, isNot(equals('Apartment lease 2026')),
          reason: 'SEC-06: caption must be encrypted in secure storage');
      final rawTags = storedDoc['tags'] as String?;
      expect(rawTags, isNotNull);
      expect(rawTags, isNot(contains('#Contract')),
          reason: 'SEC-06: tags must be encrypted in secure storage');
    });

    test('NotesService persists tags correctly', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('1234');
      final service = NotesService(platform, crypto);

      final now = DateTime.now();
      final note = Note(
        id: 'note-1',
        title: 'Secret Codes',
        encryptedBody: 'Backup codes 1234',
        createdAt: now,
        updatedAt: now,
        tags: ['#Crypto', '#Important'],
      );

      await service.addNote(note);

      final notes = await service.getAllNotes();
      expect(notes.first.tags, ['#Crypto', '#Important']);

      // Update tags via updateNote
      final updated = note.copyWith(tags: ['#Crypto', '#Important', '#Work']);
      await service.updateNote(updated);

      final reloaded = await service.getAllNotes();
      expect(reloaded.first.tags, ['#Crypto', '#Important', '#Work']);
    });
  });
}
