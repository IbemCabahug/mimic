// test/vault/export/vault_export_import_test.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/export/vault_exporter.dart';
import 'package:mimic/vault/export/vault_importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late String downloadsPath;
  late String dbDirPath;

  final Map<String, String> secureStorageData = {};

  final List<String> recoveryWords = [
    'abandon', 'abandon', 'abandon', 'abandon',
    'abandon', 'abandon', 'abandon', 'abandon',
    'abandon', 'abandon', 'abandon', 'about'
  ];

  setUpAll(() {
    // Initialize sqflite FFI – provides a real SQLite engine on Windows/macOS/Linux
    // without needing the Android/iOS method channel plugin.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Intercept flutter_secure_storage method channel
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
        .setMockMethodCallHandler((MethodCall methodCall) async {
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
    });

    // Intercept path_provider method channel
    // These paths are set in setUp() before each test runs.
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return appDocsPath;
      }
      if (methodCall.method == 'getDownloadsDirectory') {
        return downloadsPath;
      }
      if (methodCall.method == 'getExternalStorageDirectory') {
        return downloadsPath;
      }
      return null;
    });
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mimic_backup_test');
    appDocsPath = '${tempDir.path}/app_docs';
    downloadsPath = '${tempDir.path}/downloads';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(downloadsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();

    // Point sqflite's getDatabasesPath to our temp directory so that
    // VaultExporter/VaultImporter create real SQLite databases there.
    await databaseFactory.setDatabasesPath(dbDirPath);

    // Initialize VaultCrypto with AndroidPlatformService to use the
    // secure storage mock channel.
    final platformService = AndroidPlatformService();
    VaultCrypto(platformService); // registers VaultCrypto.instance
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Vault Export & Import Tests', () {
    // ─────────────────────────────────────────────────────────────────
    //  Validation-only tests (no database interaction needed)
    // ─────────────────────────────────────────────────────────────────

    test('validateFile rejects short file', () async {
      final file = File('$downloadsPath/short.mimic');
      await file.writeAsBytes([0x4D, 0x4D]);
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('File too short'));
    });

    test('validateFile rejects wrong magic header', () async {
      final file = File('$downloadsPath/wrong_magic.mimic');
      final bytes = List<int>.filled(50, 0);
      await file.writeAsBytes(bytes);
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('Magic header mismatch'));
    });

    test('validateFile rejects wrong version', () async {
      final file = File('$downloadsPath/wrong_version.mimic');
      final bytes = List<int>.filled(50, 0);
      bytes[0] = 0x4D; bytes[1] = 0x4D; bytes[2] = 0x49; bytes[3] = 0x43; // MMIC
      bytes[4] = 0x02; // version 2
      await file.writeAsBytes(bytes);
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('Unsupported backup version'));
    });

    test('validateFile rejects checksum mismatch', () async {
      final file = File('$downloadsPath/checksum_mismatch.mimic');
      final bytes = List<int>.filled(50, 0);
      bytes[0] = 0x4D; bytes[1] = 0x4D; bytes[2] = 0x49; bytes[3] = 0x43; // MMIC
      bytes[4] = 0x01; // version 1
      // Checksum bytes [5..37] left as zeros
      // Payload has some dummy bytes
      bytes[45] = 0xAA;
      await file.writeAsBytes(bytes);
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('checksum mismatch'));
    });

    // ─────────────────────────────────────────────────────────────────
    //  Full round-trip: export → validate → import
    // ─────────────────────────────────────────────────────────────────

    test('Full Export and Import Round-Trip', () async {
      // 1. Initialise VaultCrypto and store recovery blob
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      // 2. Seed real SQLite databases that VaultExporter will read
      final notesDbPath = '$dbDirPath/vault_notes.db';
      final notesDb = await openDatabase(
        notesDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notes(
              id TEXT PRIMARY KEY,
              title TEXT,
              encryptedBody TEXT,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
        },
      );

      final encryptedBody = VaultCrypto.instance.encryptString('Note Body Content');
      final now = DateTime.now().toIso8601String();
      await notesDb.insert('notes', {
        'id': 'note1',
        'title': 'Secret Note',
        'encryptedBody': encryptedBody,
        'created_at': now,
        'updated_at': now,
      });
      await notesDb.close();

      final photosDbPath = '$dbDirPath/vault_files.db';
      final photosDb = await openDatabase(
        photosDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE photos(
              id TEXT PRIMARY KEY,
              mimeType TEXT,
              size INTEGER,
              createdAt TEXT
            )
          ''');
        },
      );
      await photosDb.insert('photos', {
        'id': 'photo1',
        'mimeType': 'image/jpeg',
        'size': 1024,
        'createdAt': now,
      });
      await photosDb.close();

      // Write a mock encrypted photo file to the app-docs directory
      final photoFile = File('$appDocsPath/photo1');
      await photoFile.writeAsBytes(utf8.encode('photo_bytes'));

      // 3. Perform export
      final exportedFile = await VaultExporter.buildExportFile();
      expect(await exportedFile.exists(), isTrue);

      // Verify the exported file validation
      final validation = await VaultImporter.validateFile(exportedFile);
      expect(validation.isValid, isTrue);

      // 4. Clear data to simulate a fresh state / new device
      secureStorageData.clear();

      // Delete the database files
      if (await File(notesDbPath).exists()) await File(notesDbPath).delete();
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();

      // Delete the photo file
      if (await photoFile.exists()) await photoFile.delete();

      // Reinitialize VaultCrypto to locked state
      final platformService = AndroidPlatformService();
      VaultCrypto(platformService);

      // 5. Perform import
      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(importSuccess, isTrue);

      // Verify VaultCrypto is now unlocked and can decrypt data
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      // Verify notes database was restored
      final restoredNotesDb = await openDatabase(notesDbPath);
      final restoredNotes = await restoredNotesDb.query('notes');
      await restoredNotesDb.close();

      expect(restoredNotes.length, equals(1));
      expect(restoredNotes[0]['id'], equals('note1'));
      expect(restoredNotes[0]['title'], equals('Secret Note'));

      // Verify decryption works with the imported key
      final noteDecrypted = VaultCrypto.instance.decryptString(
        restoredNotes[0]['encryptedBody'] as String,
      );
      expect(noteDecrypted, equals('Note Body Content'));

      // Verify photos database was restored
      final restoredPhotosDb = await openDatabase(photosDbPath);
      final restoredPhotos = await restoredPhotosDb.query('photos');
      await restoredPhotosDb.close();

      expect(restoredPhotos.length, equals(1));
      expect(restoredPhotos[0]['id'], equals('photo1'));

      // Verify the encrypted file was restored on disk
      expect(await photoFile.exists(), isTrue);
      expect(utf8.decode(await photoFile.readAsBytes()), equals('photo_bytes'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────
    //  Wrong recovery phrase must fail without overwriting existing data
    // ─────────────────────────────────────────────────────────────────

    test('Import fails with wrong recovery phrase without modifying existing data', () async {
      // 1. Setup a vault with data and export it
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      final notesDbPath = '$dbDirPath/vault_notes.db';
      final notesDb = await openDatabase(
        notesDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notes(
              id TEXT PRIMARY KEY,
              title TEXT,
              encryptedBody TEXT,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
        },
      );
      final now = DateTime.now().toIso8601String();
      await notesDb.insert('notes', {
        'id': 'original_note',
        'title': 'Original Note',
        'encryptedBody': 'mangled_body',
        'created_at': now,
        'updated_at': now,
      });
      await notesDb.close();

      // Export the backup
      final backupFile = await VaultExporter.buildExportFile();

      // Update the note to represent the current "active" vault state
      final activeDb = await openDatabase(notesDbPath);
      await activeDb.update(
        'notes',
        {'title': 'Active Vault Note', 'encryptedBody': 'active_body'},
        where: 'id = ?',
        whereArgs: ['original_note'],
      );
      await activeDb.close();

      // 2. Attempt import with wrong phrase (last word changed)
      final wrongWords = List<String>.from(recoveryWords)..[11] = 'abandon';
      final importSuccess = await VaultImporter.importWithPhrase(backupFile, wrongWords);
      expect(importSuccess, isFalse);

      // 3. Verify that existing active note was NOT overwritten or deleted
      final checkDb = await openDatabase(notesDbPath);
      final notes = await checkDb.query('notes');
      await checkDb.close();

      expect(notes.length, equals(1));
      expect(notes[0]['title'], equals('Active Vault Note'),
          reason: 'Existing active vault data must not be affected by failed recovery phrase import');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
