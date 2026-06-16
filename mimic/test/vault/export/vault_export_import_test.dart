// test/vault/export/vault_export_import_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/export/vault_exporter.dart';
import 'package:mimic/vault/export/vault_importer.dart';
import 'package:mimic/vault/export/mimic_v2_format.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    // Intercept path_provider method channel
    // These paths are set in setUp() before each test runs.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return appDocsPath;
        }
        if (methodCall.method == 'getDownloadsDirectory') {
          return downloadsPath;
        }
        if (methodCall.method == 'getExternalStorageDirectory') {
          return downloadsPath;
        }
        if (methodCall.method == 'getTemporaryDirectory') {
          return appDocsPath;
        }
        return null;
      },
    );
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
    SharedPreferences.setMockInitialValues({});

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

  // Helper: build a minimal v1 .mimic file in-test
  Uint8List _buildV1File(Map<String, dynamic> payload) {
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final checksum = sha256.convert(jsonBytes).bytes;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final tsData = ByteData(8);
    tsData.setInt64(0, nowMs, Endian.big);

    final builder = BytesBuilder(copy: false);
    builder.add([0x4D, 0x4D, 0x49, 0x43]); // MMIC magic
    builder.addByte(0x01);                   // v1
    builder.add(checksum);                   // 32B SHA-256
    builder.add(tsData.buffer.asUint8List()); // 8B timestamp
    builder.add(jsonBytes);                  // JSON payload
    return builder.toBytes();
  }

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
      bytes[4] = 0xFF; // unknown version (not 0x01 or 0x02)
      await file.writeAsBytes(bytes);
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('Unsupported backup version'));
    });

    test('validateFile rejects checksum mismatch (v1)', () async {
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

    test('validateFile accepts v2 file with valid header', () async {
      // Build a minimal valid v2 file
      final file = File('$downloadsPath/valid_v2.mimic');
      final sink = file.openWrite();
      final writer = MimicV2Writer(sink);
      writer.writeHeader(0, Uint8List.fromList(utf8.encode('{}')));
      await writer.finish();
      await sink.close();
      
      final result = await VaultImporter.validateFile(file);
      expect(result.isValid, isTrue);
    });

    // ─────────────────────────────────────────────────────────────────
    //  V2 Full round-trip: export → validate → import
    // ─────────────────────────────────────────────────────────────────

    test('Full Export and Import Round-Trip (v2)', () async {
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

      final videosDbPath = '$dbDirPath/vault_videos.db';
      final videosDb = await openDatabase(
        videosDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE videos(
              id TEXT PRIMARY KEY,
              mimeType TEXT,
              size INTEGER,
              durationS INTEGER,
              createdAt TEXT,
              originalName TEXT
            )
          ''');
        },
      );
      await videosDb.insert('videos', {
        'id': 'video1',
        'mimeType': 'video/mp4',
        'size': 2048,
        'durationS': 120,
        'createdAt': now,
        'originalName': 'test.mp4',
      });
      await videosDb.close();

      secureStorageData['vault_documents_meta'] = jsonEncode([
        {
          'id': 'doc1',
          'originalName': 'secret.pdf',
          'mimeType': 'application/pdf',
          'size': 1024,
          'createdAt': now,
        }
      ]);

      // Write mock encrypted files to the app-docs directory
      final photoFile = File('$appDocsPath/vault_files/photo1');
      final videoFile = File('$appDocsPath/vault_files/video1');
      final docFile = File('$appDocsPath/vault_files/doc1');
      await Directory('$appDocsPath/vault_files').create(recursive: true);
      await photoFile.writeAsBytes(utf8.encode('photo_bytes'));
      await videoFile.writeAsBytes(utf8.encode('video_bytes'));
      await docFile.writeAsBytes(utf8.encode('doc_bytes'));

      // 3. Perform export
      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      // Verify the exported file is v2 format
      final exportBytes = await exportedFile.readAsBytes();
      expect(exportBytes[4], equals(kMimicVersionV2), reason: 'Export should produce v2 format');

      // Verify the exported file validation
      final validation = await VaultImporter.validateFile(exportedFile);
      expect(validation.isValid, isTrue);

      // 4. Clear data to simulate a fresh state / new device
      secureStorageData.clear();

      // Delete the database files
      if (await File(notesDbPath).exists()) await File(notesDbPath).delete();
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();
      if (await File(videosDbPath).exists()) await File(videosDbPath).delete();

      // Delete the encrypted files
      if (await photoFile.exists()) await photoFile.delete();
      if (await videoFile.exists()) await videoFile.delete();
      if (await docFile.exists()) await docFile.delete();

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

      // Verify videos database was restored
      final restoredVideosDb = await openDatabase(videosDbPath);
      final restoredVideos = await restoredVideosDb.query('videos');
      await restoredVideosDb.close();

      expect(restoredVideos.length, equals(1));
      expect(restoredVideos[0]['id'], equals('video1'));

      // Verify documents metadata was restored
      expect(secureStorageData['vault_documents_meta'], isNotNull);

      // Verify the encrypted files were restored on disk
      expect(await photoFile.exists(), isTrue);
      expect(utf8.decode(await photoFile.readAsBytes()), equals('photo_bytes'));
      expect(await videoFile.exists(), isTrue);
      expect(utf8.decode(await videoFile.readAsBytes()), equals('video_bytes'));
      expect(await docFile.exists(), isTrue);
      expect(utf8.decode(await docFile.readAsBytes()), equals('doc_bytes'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────
    //  Corruption safety: flip one byte → import throws, vault untouched
    // ─────────────────────────────────────────────────────────────────

    test('V2 Corruption safety: flip byte -> import throws, vault_files untouched', () async {
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

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
      final now = DateTime.now().toIso8601String();
      await photosDb.insert('photos', {
        'id': 'photo_corrupt_test',
        'mimeType': 'image/jpeg',
        'size': 100,
        'createdAt': now,
      });
      await photosDb.close();

      await Directory('$appDocsPath/vault_files').create(recursive: true);
      final photoFile = File('$appDocsPath/vault_files/photo_corrupt_test');
      await photoFile.writeAsBytes(utf8.encode('original_photo_bytes'));

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());

      // Now set up "existing" vault state that should NOT be overwritten
      await photoFile.writeAsBytes(utf8.encode('existing_vault_data'));
      final existingContent = await photoFile.readAsBytes();

      // Corrupt the exported file (flip a byte in the blob payload area)
      final exportBytes = await exportedFile.readAsBytes();
      final corruptedBytes = Uint8List.fromList(exportBytes);
      // Flip a byte near the end (in the blob data, before the 32-byte trailer)
      corruptedBytes[corruptedBytes.length - 40] ^= 0xFF;

      final corruptedFile = File('$downloadsPath/corrupted_v2.mimic');
      await corruptedFile.writeAsBytes(corruptedBytes);

      // Reinitialize VaultCrypto
      VaultCrypto(AndroidPlatformService());

      // Import should throw
      bool threw = false;
      try {
        await VaultImporter.importWithPhrase(corruptedFile, recoveryWords);
      } catch (e) {
        threw = true;
        expect(e.toString(), contains('corrupted or incomplete'));
      }
      expect(threw, isTrue, reason: 'Import of corrupted v2 file should throw');

      // Vault files should be untouched (existing data preserved)
      expect(await photoFile.exists(), isTrue);
      expect(await photoFile.readAsBytes(), equals(existingContent),
          reason: 'Existing vault file must not be modified after corrupted import');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────
    //  V1 backward compatibility: hand-built v1 .mimic imports
    // ─────────────────────────────────────────────────────────────────

    test('V1 backward-compat: hand-built v1 .mimic imports correctly', () async {
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      // Capture the recovery blob + salt that were just stored
      final recoveryBlob = secureStorageData['recovery_blob']!;
      final recoverySalt = secureStorageData['recovery_salt']!;
      final vaultSalt = secureStorageData['vault_salt']!;
      final vaultPinHash = secureStorageData['vault_pin_hash']!;

      // Build a v1 payload with one tiny base64-encoded blob
      final tinyBlob = utf8.encode('hello_v1');
      final payload = <String, dynamic>{
        'recovery_blob': recoveryBlob,
        'recovery_salt': recoverySalt,
        'vault_salt': vaultSalt,
        'vault_pin_hash': vaultPinHash,
        'vault_photos_meta': jsonEncode([
          {'id': 'v1_photo', 'mimeType': 'image/jpeg', 'size': tinyBlob.length, 'createdAt': DateTime.now().toIso8601String()},
        ]),
        'encrypted_files': {
          'v1_photo': base64Encode(tinyBlob),
        },
      };

      final v1Bytes = _buildV1File(payload);
      final v1File = File('$downloadsPath/legacy_v1.mimic');
      await v1File.writeAsBytes(v1Bytes);

      // Verify validateFile accepts it
      final validation = await VaultImporter.validateFile(v1File);
      expect(validation.isValid, isTrue, reason: 'v1 file should validate');

      // Clear state
      secureStorageData.clear();
      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();

      VaultCrypto(AndroidPlatformService());

      // Import the v1 file
      final importSuccess = await VaultImporter.importWithPhrase(v1File, recoveryWords);
      expect(importSuccess, isTrue, reason: 'v1 import should succeed');

      // Verify the blob was restored
      final appDir = await getApplicationDocumentsDirectory();
      final restoredBlobFile = File('${appDir.path}/vault_files/v1_photo');
      expect(await restoredBlobFile.exists(), isTrue, reason: 'v1 blob should be restored');
      expect(await restoredBlobFile.readAsBytes(), equals(tinyBlob));

      // Verify VaultCrypto is unlocked
      expect(VaultCrypto.instance.isUnlocked, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────
    //  Backward compatibility: old backups without new keys
    // ─────────────────────────────────────────────────────────────────

    test('Import backward-compat payload WITHOUT video/document keys (v1)', () async {
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      // Capture recovery data
      final recoveryBlob = secureStorageData['recovery_blob']!;
      final recoverySalt = secureStorageData['recovery_salt']!;
      final vaultSalt = secureStorageData['vault_salt']!;
      final vaultPinHash = secureStorageData['vault_pin_hash']!;

      // Build a v1 payload WITHOUT video/document keys
      final payload = <String, dynamic>{
        'recovery_blob': recoveryBlob,
        'recovery_salt': recoverySalt,
        'vault_salt': vaultSalt,
        'vault_pin_hash': vaultPinHash,
      };

      final v1Bytes = _buildV1File(payload);
      final tamperedFile = File('$downloadsPath/tampered.mimic');
      await tamperedFile.writeAsBytes(v1Bytes);

      // Attempt import
      final importSuccess = await VaultImporter.importWithPhrase(tamperedFile, recoveryWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed even if new keys are missing');
    });

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
      final backupFile = await VaultExporter.buildExportFile(ProviderContainer());

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

    test('validateFile() correctly identifies valid and corrupted files', () async {
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      // Good file
      final goodResult = await VaultImporter.validateFile(exportedFile);
      expect(goodResult.isValid, isTrue);

      // Corrupted file (flip one byte in payload)
      final bytes = await exportedFile.readAsBytes();
      final corruptedBytes = Uint8List.fromList(bytes);
      if (corruptedBytes.length > 50) {
        corruptedBytes[corruptedBytes.length - 10] ^= 0xFF; // Flip a byte
      }
      final corruptedFile = File('${exportedFile.path}_corrupted.mimic');
      await corruptedFile.writeAsBytes(corruptedBytes);

      // v2 validateFile only does a cheap sanity check, so the corrupted file
      // will still pass validation (corruption is detected at import time via trailer)
      final badResult = await VaultImporter.validateFile(corruptedFile);
      expect(badResult.isValid, isTrue, reason: 'v2 validateFile is a cheap check; corruption caught at import');
    });

    test('TRUE uninstall-simulation: export -> wipe -> import with dirty phrase', () async {
      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

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
      final now = DateTime.now().toIso8601String();
      await photosDb.insert('photos', {
        'id': 'photo_sim',
        'mimeType': 'image/jpeg',
        'size': 1024,
        'createdAt': now,
      });
      await photosDb.close();

      final photoFile = File('$appDocsPath/vault_files/photo_sim');
      await Directory('$appDocsPath/vault_files').create(recursive: true);
      await photoFile.writeAsBytes(utf8.encode('photo_sim_bytes'));

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();
      if (await photoFile.exists()) await photoFile.delete();

      final platformService = AndroidPlatformService();
      VaultCrypto(platformService);

      final dirtyWords = [
        'abandon\u200B',    // zero-width space
        ' ABANDON\u00A0 ',  // non-breaking space + uppercase
        'abandon ',         // trailing space
        'abandon', 'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];

      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, dirtyWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed despite injected artifacts in phrase');

      expect(VaultCrypto.instance.isUnlocked, isTrue);
      
      final restoredPhotosDb = await openDatabase(photosDbPath);
      final restoredPhotos = await restoredPhotosDb.query('photos');
      await restoredPhotosDb.close();
      expect(restoredPhotos.length, equals(1));
      expect(restoredPhotos[0]['id'], equals('photo_sim'));
      expect(await photoFile.exists(), isTrue);
    });

    test('FRESH install simulation: vault_files directory does not exist on import', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService);
      await crypto.initialize('123456');
      await crypto.storeRecoveryBlob(recoveryWords);

      // Add a real photo via FileVaultService to get full live schema (incl. originalName)
      final fileService = FileVaultService(platformService, crypto);
      final photoBytes = Uint8List.fromList(utf8.encode('real_photo_bytes'));
      final photoId = await fileService.savePhoto(
        photoBytes,
        'image/jpeg',
        originalName: 'test.jpg',
      );

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      // Simulate FRESH install: wipe storage, delete database, delete vault_files dir
      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      if (await vaultFilesDir.exists()) await vaultFilesDir.delete(recursive: true);

      expect(await vaultFilesDir.exists(), isFalse);

      VaultCrypto(AndroidPlatformService());

      // Perform import
      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed');

      // Verify the live service can read the restored metadata
      final newFileService = FileVaultService(AndroidPlatformService(), VaultCrypto.instance);
      final photos = await newFileService.getAllPhotos();
      expect(photos.length, equals(1));
      expect(photos.first.id, equals(photoId));
      expect(photos.first.originalName, equals('test.jpg'));

      // Verify blob file was restored
      final photoFile = File('${vaultFilesDir.path}/$photoId');
      expect(await photoFile.exists(), isTrue, reason: 'photo file should have been written');
    });

    test('EXISTING db simulation: DB exists but with NO tables (gating bug reproduction)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService);
      await crypto.initialize('123456');
      await crypto.storeRecoveryBlob(recoveryWords);

      final fileService = FileVaultService(platformService, crypto);
      final photoBytes = Uint8List.fromList(utf8.encode('real_photo_bytes'));
      final photoId = await fileService.savePhoto(
        photoBytes,
        'image/jpeg',
        originalName: 'test.jpg',
      );

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      if (await vaultFilesDir.exists()) await vaultFilesDir.delete(recursive: true);

      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) {
        await File(photosDbPath).delete();
      }
      final emptyDb = await openDatabase(photosDbPath, version: 1);
      await emptyDb.close();

      VaultCrypto(AndroidPlatformService());

      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed');

      final newFileService = FileVaultService(AndroidPlatformService(), VaultCrypto.instance);
      final photos = await newFileService.getAllPhotos();
      expect(photos.length, equals(1));
      expect(photos.first.id, equals(photoId));
      expect(photos.first.originalName, equals('test.jpg'));
    });

    test('EXISTING db simulation: DB exists WITH empty table (FileVaultService actual behavior)', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService);
      await crypto.initialize('123456');
      await crypto.storeRecoveryBlob(recoveryWords);

      final fileService = FileVaultService(platformService, crypto);
      final photoBytes = Uint8List.fromList(utf8.encode('real_photo_bytes'));
      final photoId = await fileService.savePhoto(
        photoBytes,
        'image/jpeg',
        originalName: 'test.jpg',
      );

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      if (await vaultFilesDir.exists()) await vaultFilesDir.delete(recursive: true);

      // Create DB WITH the empty schema (which is what FileVaultService would actually leave)
      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) {
        await File(photosDbPath).delete();
      }
      final db = await openDatabase(
        photosDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE photos(
              id TEXT PRIMARY KEY,
              mimeType TEXT,
              size INTEGER,
              createdAt TEXT,
              originalName TEXT
            )
          ''');
        },
      );
      await db.close();

      VaultCrypto(AndroidPlatformService());

      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed');

      final newFileService = FileVaultService(AndroidPlatformService(), VaultCrypto.instance);
      final photos = await newFileService.getAllPhotos();
      expect(photos.length, equals(1));
      expect(photos.first.id, equals(photoId));
      expect(photos.first.originalName, equals('test.jpg'));
    });

    test('SHARED DB HANDLE simulation: database_closed error on getAllPhotos after import', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService);
      await crypto.initialize('123456');
      await crypto.storeRecoveryBlob(recoveryWords);

      // (1) Get the SAME FileVaultService the app uses, open its DB
      final fileService = FileVaultService(platformService, crypto);
      final photoBytes = Uint8List.fromList(utf8.encode('real_photo_bytes'));
      final photoId = await fileService.savePhoto(
        photoBytes,
        'image/jpeg',
        originalName: 'test.jpg',
      );
      
      // Ensure the _db handle is cached
      await fileService.getAllPhotos();

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      if (await vaultFilesDir.exists()) await vaultFilesDir.delete(recursive: true);

      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) {
        await File(photosDbPath).delete();
      }
      final db = await openDatabase(
        photosDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE photos(
              id TEXT PRIMARY KEY,
              mimeType TEXT,
              size INTEGER,
              createdAt TEXT,
              originalName TEXT
            )
          ''');
        },
      );
      await db.close();

      VaultCrypto(AndroidPlatformService());

      // (2) Run importWithPhrase
      final importSuccess = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(importSuccess, isTrue, reason: 'Import should succeed');

      // (3) Call getAllPhotos() AGAIN on that same service instance and assert NO exception
      try {
        final photos = await fileService.getAllPhotos();
        expect(photos.length, equals(1));
        expect(photos.first.id, equals(photoId));
        expect(photos.first.originalName, equals('test.jpg'));
      } catch (e) {
        fail('Exception thrown on getAllPhotos after import: $e');
      }
    });

    test('Round-trip boundary: vault with ~748KB blob round-trips successfully', () async {

      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);
      const storage = FlutterSecureStorage();
      await storage.write(key: 'vault_photos_meta', value: '[{"id":"boundary_photo"}]');

      final appDocsPath = (await getApplicationDocumentsDirectory()).path;
      final photosDbPath = p.join(appDocsPath, 'vault_databases', 'vault_photos.db');
      await Directory(p.dirname(photosDbPath)).create(recursive: true);
      final photosDb = await databaseFactoryFfi.openDatabase(
        photosDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE photos(id TEXT PRIMARY KEY, mimeType TEXT, size INTEGER, createdAt TEXT, originalName TEXT)');
          },
        ),
      );
      final now = DateTime.now().toIso8601String();
      // 1MB = 1048576 bytes. (1048576 / 1.4) = ~748982. We use 748000 bytes.
      await photosDb.insert('photos', {'id': 'boundary_photo', 'mimeType': 'image/jpeg', 'size': 748000, 'createdAt': now});
      await photosDb.close();

      final boundaryFile = File('$appDocsPath/vault_files/boundary_photo');
      await Directory('$appDocsPath/vault_files').create(recursive: true);
      
      final randomAccessFile = await boundaryFile.open(mode: FileMode.write);
      await randomAccessFile.setPosition(748000 - 1);
      await randomAccessFile.writeByte(0);
      await randomAccessFile.close();

      final exportFile = await VaultExporter.buildExportFile(ProviderContainer());
      
      final result = await VaultImporter.importWithPhrase(exportFile, recoveryWords);
      expect(result, isTrue);
    });

    test('1MB backup imports successfully', () async {
      final originalImportLimit = VaultImporter.maxImportFileBytes;
      VaultImporter.maxImportFileBytes = 3 * 1024 * 1024; // 3MB import limit
      addTearDown(() {
        VaultImporter.maxImportFileBytes = originalImportLimit;
      });

      await VaultCrypto.instance.initialize('123456');
      await VaultCrypto.instance.storeRecoveryBlob(recoveryWords);

      final photosDbPath = '$dbDirPath/vault_files.db';
      final photosDb = await openDatabase(
        photosDbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE photos(id TEXT PRIMARY KEY, mimeType TEXT, size INTEGER, createdAt TEXT, originalName TEXT)');
        },
      );
      final now = DateTime.now().toIso8601String();
      await photosDb.insert('photos', {'id': 'photo_90mb', 'mimeType': 'image/jpeg', 'size': 1 * 1024 * 1024, 'createdAt': now});
      await photosDb.close();

      final hugeFile = File('$appDocsPath/vault_files/photo_90mb');
      await Directory('$appDocsPath/vault_files').create(recursive: true);
      
      final randomAccessFile = await hugeFile.open(mode: FileMode.write);
      await randomAccessFile.setPosition((1 * 1024 * 1024) - 1); // 1MB
      await randomAccessFile.writeByte(0);
      await randomAccessFile.close();

      final exportFile = await VaultExporter.buildExportFile(ProviderContainer());
      
      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();
      if (await hugeFile.exists()) await hugeFile.delete();

      VaultCrypto(AndroidPlatformService());

      try {
        final result = await VaultImporter.importWithPhrase(exportFile, recoveryWords);
        expect(result, isTrue);
      } catch (e) {
        fail('Failed to import 1MB backup: \$e');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));



    test('IMPORT size guard: fails gracefully if .mimic v1 file exceeds ceiling', () async {
      final originalLimit = VaultImporter.maxImportFileBytes;
      VaultImporter.maxImportFileBytes = 1024; // 1KB limit
      addTearDown(() => VaultImporter.maxImportFileBytes = originalLimit);

      // Build a v1 file that exceeds the limit
      final hugeFile = File('$downloadsPath/huge_backup.mimic');
      final randomAccessFile = await hugeFile.open(mode: FileMode.write);
      // Write MMIC magic + v1 version first
      await randomAccessFile.writeFrom([0x4D, 0x4D, 0x49, 0x43, 0x01]);
      await randomAccessFile.setPosition(1025 - 1);
      await randomAccessFile.writeByte(0);
      await randomAccessFile.close();

      try {
        await VaultImporter.importWithPhrase(hugeFile, recoveryWords);
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString().toLowerCase(), contains('too large'));
      }
    });

    test('CORRUPT import: fails gracefully with corrupt or invalid backup', () async {
      final corruptFile = File('$downloadsPath/corrupt_backup.mimic');
      await corruptFile.writeAsBytes([0x4D, 0x4D, 0x49, 0x43, 0x01, 1, 2, 3]);

      try {
        await VaultImporter.importWithPhrase(corruptFile, recoveryWords);
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString().toLowerCase(), contains('corrupt or invalid backup'));
      }
    });
  });
}
