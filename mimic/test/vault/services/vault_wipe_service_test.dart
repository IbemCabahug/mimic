// test/vault/services/vault_wipe_service_test.dart
//
// Danger Zone → Clear All Data. Regression tests for the r28 device finding:
// the old Settings dialog deleted only the WEB-ONLY meta keys, so on a device
// the photos (vault_files.db), videos (vault_videos.db), notes
// (vault_notes.db), documents (vault_documents_meta) and every encrypted blob
// in vault_files/ survived — thumbnails included, since they regenerate from
// surviving blobs. These tests pin the real wipe: content stores gone, blobs
// gone, intruder evidence gone, decrypted temp dirs gone, while the PIN /
// duress / gesture / setup state that keeps the vault unlockable stays.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:mimic/vault/services/file_vault_service.dart';
import 'package:mimic/vault/services/notes_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/vault_wipe_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    tempDir = Directory.systemTemp.createTempSync('vault_wipe_test');
    appDocsPath = '${tempDir.path}/app_docs';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await databaseFactory.setDatabasesPath(dbDirPath);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<VaultWipeService> buildWipe({
    FileVaultService? fileVault,
    VideoVaultService? videoVault,
    NotesService? notes,
  }) async {
    final platform = AndroidPlatformService();
    final crypto = VaultCrypto(platform, FakeKeystoreService());
    await crypto.initialize('1234');
    return VaultWipeService(
      platform,
      fileVault ?? FileVaultService(platform, crypto),
      videoVault ?? VideoVaultService(platform, crypto),
      notes ?? NotesService(platform, crypto),
      DocumentVaultService(platform, crypto),
    );
  }

  group('VaultWipeService (Danger Zone → Clear All Data)', () {
    test('wipes every content store and leaves access state alone', () async {
      final wipe = await buildWipe();

      // Access state that MUST survive: PIN, duress PIN, gesture, setup flag.
      secureStorageData['vault_pin_hash'] = 'pin-hash';
      secureStorageData['vault_pin_salt'] = 'pin-salt';
      secureStorageData['duress_pin_hash'] = 'duress-hash';
      secureStorageData['vault_gesture_record'] = '0,1,2';
      secureStorageData['vault_setup_completed'] = 'true';

      // Content metadata keys that MUST go — including the web-only keys the
      // old dialog mistook for the device stores.
      const contentKeys = [
        'break_in_logs',
        'vault_photos_meta',
        'vault_audio_meta',
        'vault_videos_meta',
        'vault_documents_meta',
        'vault_notes',
      ];
      for (final key in contentKeys) {
        secureStorageData[key] = '[]';
      }

      // Encrypted blobs (shared vault_files/ dir) + intruder evidence.
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      vaultFilesDir.createSync(recursive: true);
      File(p.join(vaultFilesDir.path, 'photo_a.blob')).writeAsBytesSync([1, 2, 3]);
      File(p.join(vaultFilesDir.path, 'video_b.blob')).writeAsBytesSync([4, 5, 6]);
      File(p.join(vaultFilesDir.path, 'doc_c.blob')).writeAsBytesSync([7, 8, 9]);
      File(p.join(appDocsPath, 'intruder_1700000000001.enc'))
          .writeAsBytesSync([9, 9]);

      // Decrypted temp leftovers (share exports, opened documents).
      final shareDir = Directory('${tempDir.path}/vault_share')
        ..createSync(recursive: true);
      final openDocsDir = Directory('${tempDir.path}/vault_docs')
        ..createSync(recursive: true);
      File(p.join(shareDir.path, 'export.bin')).writeAsBytesSync([1]);
      File(p.join(openDocsDir.path, 'opened.pdf')).writeAsBytesSync([2]);

      // Vault databases + SQLite sidecar files.
      for (final name in const [
        'vault_files.db',
        'vault_files.db-journal',
        'vault_videos.db',
        'vault_notes.db',
        'breakin_logs.db',
        'breakin_logs.db-wal',
      ]) {
        File(p.join(dbDirPath, name)).writeAsBytesSync([1]);
      }

      await wipe.wipeAllContent();

      // Blobs: the directory stays (services recreate paths inside it), the
      // contents are gone.
      expect(vaultFilesDir.existsSync(), isTrue);
      expect(vaultFilesDir.listSync(), isEmpty);
      expect(
          File('$appDocsPath/intruder_1700000000001.enc').existsSync(), isFalse);
      expect(shareDir.listSync(), isEmpty);
      expect(openDocsDir.listSync(), isEmpty);

      // Databases and sidecars gone.
      for (final name in const [
        'vault_files.db',
        'vault_files.db-journal',
        'vault_videos.db',
        'vault_notes.db',
        'breakin_logs.db',
        'breakin_logs.db-wal',
      ]) {
        expect(File(p.join(dbDirPath, name)).existsSync(), isFalse,
            reason: name);
      }

      // Content keys gone.
      for (final key in contentKeys) {
        expect(secureStorageData.containsKey(key), isFalse, reason: key);
      }

      // Access state untouched — the vault still unlocks (r28 Phase 10.1).
      expect(secureStorageData['vault_pin_hash'], 'pin-hash');
      expect(secureStorageData['vault_pin_salt'], 'pin-salt');
      expect(secureStorageData['duress_pin_hash'], 'duress-hash');
      expect(secureStorageData['vault_gesture_record'], '0,1,2');
      expect(secureStorageData['vault_setup_completed'], 'true');
    });

    test('a live service does not keep serving rows from a deleted store',
        () async {
      final platform = AndroidPlatformService();
      final crypto = VaultCrypto(platform, FakeKeystoreService());
      await crypto.initialize('1234');
      final fileVault = FileVaultService(platform, crypto);
      final videoVault = VideoVaultService(platform, crypto);
      final notes = NotesService(platform, crypto);
      final wipe = VaultWipeService(
        platform,
        fileVault,
        videoVault,
        notes,
        DocumentVaultService(platform, crypto),
      );

      final photoId = await fileVault.savePhoto(
          Uint8List.fromList([1, 2, 3, 4]),
          'image/jpeg',
          originalName: 'a.jpg');
      final videoId = await videoVault.saveVideo(
          Uint8List.fromList([5, 6, 7, 8]),
          'video/mp4',
          3,
          originalName: 'v.mp4');
      await notes.addNote(Note(
        id: 'note-1',
        title: 'Secret',
        encryptedBody: 'plain body',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(await fileVault.getAllPhotos(), hasLength(1));
      expect(await videoVault.getAllVideos(), hasLength(1));
      expect(await notes.getAllNotes(), hasLength(1));

      await wipe.wipeAllContent();

      // The wipe closes the cached connections first; without that, these
      // open handles kept serving the deleted rows for the whole session —
      // the in-session half of the r28 device finding.
      expect(await fileVault.getAllPhotos(), isEmpty,
          reason: 'the closed-and-recreated photo store must be empty');
      expect(await videoVault.getAllVideos(), isEmpty);
      expect(await notes.getAllNotes(), isEmpty);
      expect(await platform.readEncryptedFile(photoId), isNull);
      expect(await platform.readEncryptedFile(videoId), isNull);
    });
  });
}
