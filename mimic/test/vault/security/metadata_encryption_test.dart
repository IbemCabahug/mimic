import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/services/notes_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late String dbDirPath;

  final Map<String, String> secureStorageData = {};
  final Map<String, Object> sharedPrefsData = {};

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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') {
          return sharedPrefsData;
        }
        if (methodCall.method == 'setString') {
          final key = methodCall.arguments['key'] as String;
          final value = methodCall.arguments['value'] as String;
          sharedPrefsData[key] = value;
          return true;
        }
        if (methodCall.method == 'remove') {
          final key = methodCall.arguments['key'] as String;
          sharedPrefsData.remove(key);
          return true;
        }
        if (methodCall.method == 'clear') {
          sharedPrefsData.clear();
          return true;
        }
        return null;
      },
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('metadata_encryption_test');
    appDocsPath = '${tempDir.path}/app_docs';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    sharedPrefsData.clear();
    SharedPreferences.setMockInitialValues({});
    await databaseFactory.setDatabasesPath(dbDirPath);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SEC-06: Metadata Encryption in SQLite and Secure Storage', () {
    test('NotesService encrypts note title in SQLite and decrypts on read', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('123456');
      final notesService = NotesService(platform, crypto);

      final note = Note(
        id: 'note-1',
        title: 'Secret Offshore Account',
        encryptedBody: 'Account #123456789',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await notesService.addNote(note);

      // Verify raw SQLite row
      final db = await openDatabase(p.join(dbDirPath, 'vault_notes.db'));
      final rows = await db.query('notes', where: 'id = ?', whereArgs: ['note-1']);
      expect(rows, hasLength(1));
      final rawRow = rows.first;

      final storedTitle = rawRow['title'] as String;
      expect(storedTitle.contains('Secret Offshore Account'), isFalse,
          reason: 'Plaintext title must never appear in SQLite');
      expect(crypto.decryptString(storedTitle), equals('Secret Offshore Account'));
      await db.close();

      // Read back through NotesService
      final notes = await notesService.getAllNotes();
      expect(notes.firstWhere((n) => n.id == 'note-1').title, equals('Secret Offshore Account'));

      // Test legacy plaintext fallback: insert plaintext title directly
      final db2 = await openDatabase(p.join(dbDirPath, 'vault_notes.db'));
      await db2.insert('notes', {
        'id': 'legacy-note',
        'title': 'Legacy Unencrypted Title',
        'encryptedBody': crypto.encryptString('Legacy content'),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await db2.close();

      final notesWithLegacy = await notesService.getAllNotes();
      expect(notesWithLegacy.firstWhere((n) => n.id == 'legacy-note').title,
          equals('Legacy Unencrypted Title'));

      // Test restoreNotes upgrades cleartext title to encrypted
      await notesService.restoreNotes([
        {
          'id': 'restored-legacy-note',
          'title': 'Restored Plaintext Title',
          'encryptedBody': crypto.encryptString('Restored content'),
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        }
      ]);
      final db3 = await openDatabase(p.join(dbDirPath, 'vault_notes.db'));
      final restoredRows = await db3.query('notes', where: 'id = ?', whereArgs: ['restored-legacy-note']);
      final restoredTitle = restoredRows.first['title'] as String;
      expect(restoredTitle.contains('Restored Plaintext Title'), isFalse);
      expect(crypto.decryptString(restoredTitle), equals('Restored Plaintext Title'));
      await db3.close();
    });

    test('FileVaultService encrypts originalName in SQLite and decrypts on read', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('123456');
      final fileVault = FileVaultService(platform, crypto);

      final photoBytes = Uint8List.fromList([10, 20, 30, 40]);
      final photoId = await fileVault.savePhoto(photoBytes, 'image/jpeg',
          originalName: 'passport_scan_2026.jpg');

      // Verify raw SQLite row
      final db = await openDatabase(p.join(dbDirPath, 'vault_files.db'));
      final rows = await db.query('photos', where: 'id = ?', whereArgs: [photoId]);
      expect(rows, hasLength(1));
      final rawRow = rows.first;

      final storedName = rawRow['originalName'] as String;
      expect(storedName.contains('passport_scan_2026.jpg'), isFalse,
          reason: 'Plaintext filename must never appear in SQLite');
      expect(crypto.decryptString(storedName), equals('passport_scan_2026.jpg'));
      await db.close();

      // Read back through FileVaultService
      final photos = await fileVault.getAllPhotos();
      expect(photos.firstWhere((p) => p.id == photoId).originalName,
          equals('passport_scan_2026.jpg'));

      // Test legacy plaintext fallback: insert plaintext filename directly
      final db2 = await openDatabase(p.join(dbDirPath, 'vault_files.db'));
      await db2.insert('photos', {
        'id': 'legacy-photo',
        'mimeType': 'image/png',
        'size': 1234,
        'createdAt': DateTime.now().toIso8601String(),
        'originalName': 'legacy_cleartext_photo.png',
        'folder': '',
      });
      await db2.close();

      final photosWithLegacy = await fileVault.getAllPhotos();
      expect(photosWithLegacy.firstWhere((p) => p.id == 'legacy-photo').originalName,
          equals('legacy_cleartext_photo.png'));

      // Test restorePhotos upgrades cleartext filename to encrypted
      await fileVault.restorePhotos([
        {
          'id': 'restored-photo',
          'mimeType': 'image/jpeg',
          'size': 5678,
          'createdAt': DateTime.now().toIso8601String(),
          'originalName': 'restored_cleartext.jpg',
          'folder': '',
        }
      ]);
      final db3 = await openDatabase(p.join(dbDirPath, 'vault_files.db'));
      final restoredRows = await db3.query('photos', where: 'id = ?', whereArgs: ['restored-photo']);
      final restoredName = restoredRows.first['originalName'] as String;
      expect(restoredName.contains('restored_cleartext.jpg'), isFalse);
      expect(crypto.decryptString(restoredName), equals('restored_cleartext.jpg'));
      await db3.close();
    });

    test('VideoVaultService encrypts originalName in SQLite and decrypts on read', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('123456');
      final videoVault = VideoVaultService(platform, crypto);

      final videoBytes = Uint8List.fromList([50, 60, 70, 80]);
      final videoId = await videoVault.saveVideo(videoBytes, 'video/mp4', 60,
          originalName: 'cctv_evidence_confidential.mp4');

      // Verify raw SQLite row
      final db = await openDatabase(p.join(dbDirPath, 'vault_videos.db'));
      final rows = await db.query('videos', where: 'id = ?', whereArgs: [videoId]);
      expect(rows, hasLength(1));
      final rawRow = rows.first;

      final storedName = rawRow['originalName'] as String;
      expect(storedName.contains('cctv_evidence_confidential.mp4'), isFalse,
          reason: 'Plaintext video name must never appear in SQLite');
      expect(crypto.decryptString(storedName), equals('cctv_evidence_confidential.mp4'));
      await db.close();

      // Read back through VideoVaultService
      final videos = await videoVault.getAllVideos();
      expect(videos.firstWhere((v) => v.id == videoId).originalName,
          equals('cctv_evidence_confidential.mp4'));

      // Test legacy plaintext fallback: insert plaintext filename directly
      final db2 = await openDatabase(p.join(dbDirPath, 'vault_videos.db'));
      await db2.insert('videos', {
        'id': 'legacy-video',
        'mimeType': 'video/mp4',
        'size': 4321,
        'durationS': 15,
        'createdAt': DateTime.now().toIso8601String(),
        'originalName': 'legacy_cleartext_video.mp4',
        'folder': '',
      });
      await db2.close();

      final videosWithLegacy = await videoVault.getAllVideos();
      expect(videosWithLegacy.firstWhere((v) => v.id == 'legacy-video').originalName,
          equals('legacy_cleartext_video.mp4'));

      // Test restoreVideos upgrades cleartext filename to encrypted
      await videoVault.restoreVideos([
        {
          'id': 'restored-video',
          'mimeType': 'video/mp4',
          'size': 8765,
          'durationS': 30,
          'createdAt': DateTime.now().toIso8601String(),
          'originalName': 'restored_cleartext.mp4',
          'folder': '',
        }
      ]);
      final db3 = await openDatabase(p.join(dbDirPath, 'vault_videos.db'));
      final restoredRows = await db3.query('videos', where: 'id = ?', whereArgs: ['restored-video']);
      final restoredName = restoredRows.first['originalName'] as String;
      expect(restoredName.contains('restored_cleartext.mp4'), isFalse);
      expect(crypto.decryptString(restoredName), equals('restored_cleartext.mp4'));
      await db3.close();
    });

    test('DocumentVaultService encrypts fileName, purges SharedPreferences copy, and decrypts on read', () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('123456');
      final docVault = DocumentVaultService(platform, crypto);

      final srcFile = File(p.join(tempDir.path, 'contract.pdf'));
      await srcFile.writeAsBytes([1, 2, 3, 4]);

      final docId = await docVault.saveDocumentFromFile(srcFile, 'pdf',
          originalName: 'contract_confidential_2026.pdf');

      // Verify secure storage contains encrypted fileName
      final rawSecure = secureStorageData['vault_documents_meta'];
      expect(rawSecure, isNotNull);
      expect(rawSecure!.contains('contract_confidential_2026.pdf'), isFalse,
          reason: 'Plaintext document filename must never appear in secure storage');

      final List<dynamic> decodedList = jsonDecode(rawSecure);
      final rawDoc = decodedList.firstWhere((d) => d['id'] == docId);
      final encryptedFileName = rawDoc['fileName'] as String;
      expect(crypto.decryptString(encryptedFileName), equals('contract_confidential_2026.pdf'));

      // Verify unencrypted SharedPreferences copy is NOT present
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('vault_documents_meta'), isFalse,
          reason: 'Document metadata must not be duplicated into unencrypted SharedPreferences');

      // Read back through DocumentVaultService
      final docs = await docVault.listDocuments();
      expect(docs.firstWhere((d) => d.id == docId).fileName,
          equals('contract_confidential_2026.pdf'));

      // Test legacy migration from SharedPreferences
      secureStorageData.remove('vault_documents_meta');
      await prefs.setString(
        'vault_documents_meta',
        jsonEncode([
          {
            'id': 'legacy-doc',
            'fileName': 'old_unencrypted_tax.pdf',
            'fileType': 'pdf',
            'sizeBytes': 100,
            'addedAt': DateTime.now().toIso8601String(),
            'isTextNote': 0,
            'folder': '',
          }
        ]),
      );

      final migratedDocs = await docVault.listDocuments();
      expect(migratedDocs.firstWhere((d) => d.id == 'legacy-doc').fileName,
          equals('old_unencrypted_tax.pdf'));

      // Verify it was migrated to secure storage with encryption and pruned from prefs
      expect(prefs.containsKey('vault_documents_meta'), isFalse,
          reason: 'Legacy prefs copy must be purged after migration');
      final migratedRaw = secureStorageData['vault_documents_meta'];
      expect(migratedRaw, isNotNull);
      expect(migratedRaw!.contains('old_unencrypted_tax.pdf'), isFalse,
          reason: 'Migrated document filename must now be encrypted');
    });
  });
}
