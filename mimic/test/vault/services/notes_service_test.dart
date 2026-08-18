import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    tempDir = Directory.systemTemp.createTempSync('notes_vault_test');
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

  group('NotesService', () {
    test('concurrent getAllNotes calls open the database exactly once', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final notesService = NotesService(platformService, crypto);

      expect(notesService.openCount, equals(0));

      // Fire two getAllNotes() calls without awaiting the first, await both together
      final future1 = notesService.getAllNotes();
      final future2 = notesService.getAllNotes();
      final results = await Future.wait([future1, future2]);

      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
      expect(notesService.openCount, equals(1));

      // Positive control: genuinely separate instance opens its database independently
      final platformService2 = AndroidPlatformService();
      final crypto2 = VaultCrypto(platformService2, FakeKeystoreService());
      await crypto2.initialize('1234');
      final separateService = NotesService(platformService2, crypto2);
      expect(separateService.openCount, equals(0));
      await separateService.getAllNotes();
      expect(separateService.openCount, equals(1));
    });

    test('a closed database handle is reopened on the next query', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('1234');
      final notesService = NotesService(platformService, crypto);

      // First query opens the database
      final initialNotes = await notesService.getAllNotes();
      expect(initialNotes, isEmpty);
      expect(notesService.openCount, equals(1));

      // Close the underlying SQLite database handle externally
      final dbPath = p.join(await getDatabasesPath(), 'vault_notes.db');
      final db = await openDatabase(dbPath);
      await db.close();

      // Next query detects closed handle, reopens and succeeds
      final notes = await notesService.getAllNotes();
      expect(notes, isEmpty);
      expect(notesService.openCount, equals(2));
    });
  });
}
