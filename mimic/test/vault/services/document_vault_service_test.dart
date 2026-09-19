import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/services/document_vault_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late String dbDirPath;

  final Map<String, String> secureStorageData = {};
  final Map<String, Object> sharedPrefsData = {};

  setUpAll(() {
    // Mock SharedPreferences
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
    tempDir = Directory.systemTemp.createTempSync('document_vault_test');
    appDocsPath = '${tempDir.path}/app_docs';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    sharedPrefsData.clear();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('DocumentVaultService', () {
    test('saveDocumentFromFile encrypts and saves document metadata correctly', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final srcFile = File(p.join(tempDir.path, 'test_doc.pdf'));
      // Generate ~2MB file
      final bytes = List<int>.generate(2 * 1024 * 1024, (i) => i % 256);
      await srcFile.writeAsBytes(bytes);

      final id = await documentService.saveDocumentFromFile(srcFile, 'pdf', originalName: 'test_doc.pdf');

      final extractedBytes = await documentService.getDocumentBytes(id);
      expect(extractedBytes, isNotNull);
      expect(extractedBytes!.length, equals(2 * 1024 * 1024));

      final docs = await documentService.listDocuments();
      final doc = docs.firstWhere((d) => d.id == id);
      expect(doc.fileName, equals('test_doc.pdf'));
      expect(doc.fileType, equals('pdf'));
    });

    test('getDocumentToTempFile decrypts stream to a temp file safely', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final srcFile = File(p.join(tempDir.path, 'test_doc.pdf'));
      final bytes = List<int>.generate(1024 * 1024, (i) => i % 256);
      await srcFile.writeAsBytes(bytes);

      final id = await documentService.saveDocumentFromFile(srcFile, 'pdf', originalName: 'test_doc.pdf');

      final tempFile = await documentService.getDocumentToTempFile(id);
      expect(tempFile, isNotNull);
      expect(tempFile!.existsSync(), isTrue);

      final tempBytes = await tempFile.readAsBytes();
      expect(tempBytes.length, equals(1024 * 1024));

      // Cleanup
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });

    test('getDocumentToTempFile returns null for missing blob id', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final tempFile = await documentService.getDocumentToTempFile('non_existent_id');
      expect(tempFile, isNull);
    });

    test('saveDocumentFromFile leaves the original source file untouched (H7)', () async {
      // H7: the system file picker grants no authority to delete, so the fix
      // is NOT deletion — deleting a path we do not own could destroy data
      // outside the vault — but honesty. This test pins the service half:
      // saveDocumentFromFile must NEVER delete or modify its src, whichever
      // path it is handed.
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final srcFile = File(p.join(tempDir.path, 'h7_doc.pdf'));
      final bytes = List<int>.generate(4096, (i) => i % 256);
      await srcFile.writeAsBytes(bytes);

      await documentService.saveDocumentFromFile(srcFile, 'pdf',
          originalName: 'h7_doc.pdf');

      expect(srcFile.existsSync(), isTrue,
          reason: 'import must not delete the original');
      expect(await srcFile.readAsBytes(), equals(bytes),
          reason: 'import must not modify the original');
    });

    test('importDocument removes the picker\'s own plaintext temp copy after a successful import',
        () async {
      // H7 follow-up. The pinned plugin (file_picker 10.3.10) copies the picked
      // document into OUR cache dir and returns THAT path, so the path the
      // service is handed is a plaintext duplicate we own — unlike the user's
      // original, which stays put. Leaving it behind would strand a readable
      // copy of a document the user just chose to protect.
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final pickedCopy = File(p.join(tempDir.path, 'file_picker', '9876', 'picked.pdf'));
      await pickedCopy.create(recursive: true);
      final bytes = List<int>.generate(4096, (i) => i % 256);
      await pickedCopy.writeAsBytes(bytes);

      FilePicker.platform = _FakeFilePicker(pickedCopy.path);
      addTearDown(() => FilePicker.platform = FilePickerIO());

      final result = await documentService.importDocument();

      expect(result.tempCopyRemoved, isTrue,
          reason: 'a copy inside our own cache dir is ours to delete');
      expect(pickedCopy.existsSync(), isFalse,
          reason: 'a plaintext duplicate inside our cache must not be left behind');
      // Deletion happens only AFTER the encrypted write succeeded, so the
      // document must be readable from the vault.
      expect(await documentService.getDocumentBytes(result.id), equals(bytes));
    });

    test('importDocument never deletes a picked path outside the app temp dir', () async {
      // The guard that makes the worst case "we left a file alone" instead of
      // "we deleted the user's file": if a future plugin version hands back a
      // real external path, it must survive the import untouched.
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final outsideDir = Directory.systemTemp.createTempSync('mimic_user_docs');
      addTearDown(() {
        try {
          outsideDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final outsider = File(p.join(outsideDir.path, 'user_document.pdf'));
      final bytes = List<int>.generate(2048, (i) => i % 256);
      await outsider.writeAsBytes(bytes);

      FilePicker.platform = _FakeFilePicker(outsider.path);
      addTearDown(() => FilePicker.platform = FilePickerIO());

      final result = await documentService.importDocument();

      expect(result.tempCopyRemoved, isFalse,
          reason: 'the guard must refuse any path it does not own');
      expect(outsider.existsSync(), isTrue,
          reason: 'a path outside our temp dir must survive an import');
      expect(await outsider.readAsBytes(), equals(bytes),
          reason: 'and it must be byte-identical afterwards');
    });

    test('importDocumentAndRemoveOriginal deletes the original through the '
        'SAF hook and reports removal', () async {
      // The opt-in flow: the original's content URI (PlatformFile.identifier)
      // goes to the native deleteDocument channel; a provider that supports
      // FLAG_SUPPORTS_DELETE answers true and the result says "removed".
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final pickedCopy = File(p.join(tempDir.path, 'file_picker', '9901', 'picked.pdf'));
      await pickedCopy.create(recursive: true);
      final bytes = List<int>.generate(4096, (i) => i % 256);
      await pickedCopy.writeAsBytes(bytes);

      final requestedUris = <String>[];
      documentService.deleteOriginalHook = (uri) async {
        requestedUris.add(uri);
        return true;
      };

      FilePicker.platform =
          _FakeFilePicker(pickedCopy.path, identifier: 'content://downloads/document/42');
      addTearDown(() => FilePicker.platform = FilePickerIO());

      final result = await documentService.importDocumentAndRemoveOriginal();

      expect(requestedUris, equals(['content://downloads/document/42']),
          reason: 'exactly the original URI is handed to SAF, never the copy path');
      expect(result.originalRemoved, isTrue);
      expect(result.originalNote, isNull);
      // The vault copy is unaffected either way.
      expect(await documentService.getDocumentBytes(result.id), equals(bytes));
      expect(pickedCopy.existsSync(), isFalse,
          reason: 'the plugin temp copy is still cleaned up');
    });

    test('importDocumentAndRemoveOriginal keeps the original when the provider '
        'refuses, and says so', () async {
      // Read-only providers, cloud docs and expired grants all surface as
      // false — the flow must keep the original and NOT pretend otherwise.
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final pickedCopy = File(p.join(tempDir.path, 'file_picker', '9902', 'picked.pdf'));
      await pickedCopy.create(recursive: true);
      final bytes = List<int>.generate(2048, (i) => i % 256);
      await pickedCopy.writeAsBytes(bytes);

      documentService.deleteOriginalHook = (_) async => false;

      FilePicker.platform =
          _FakeFilePicker(pickedCopy.path, identifier: 'content://com.example/read_only/doc');
      addTearDown(() => FilePicker.platform = FilePickerIO());

      final result = await documentService.importDocumentAndRemoveOriginal();

      expect(result.originalRemoved, isFalse,
          reason: 'a refusal must not be reported as a removal');
      expect(result.originalNote, isNotNull,
          reason: 'the outcome must explain that the original was kept');
      expect(await documentService.getDocumentBytes(result.id), equals(bytes),
          reason: 'the vault copy exists regardless');
    });

    test('importDocumentAndRemoveOriginal with no identifier reports the '
        'original was not removed', () async {
      final platformService = AndroidPlatformService();
      final crypto = VaultCrypto(platformService, FakeKeystoreService());
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final pickedCopy = File(p.join(tempDir.path, 'file_picker', '9903', 'picked.pdf'));
      await pickedCopy.create(recursive: true);
      final bytes = List<int>.generate(1024, (i) => i % 256);
      await pickedCopy.writeAsBytes(bytes);

      var hookCalled = false;
      documentService.deleteOriginalHook = (_) async {
        hookCalled = true;
        return true;
      };

      FilePicker.platform = _FakeFilePicker(pickedCopy.path, identifier: null);
      addTearDown(() => FilePicker.platform = FilePickerIO());

      final result = await documentService.importDocumentAndRemoveOriginal();

      expect(hookCalled, isFalse,
          reason: 'without a URI there is nothing SAF can address');
      expect(result.originalRemoved, isFalse);
      expect(result.originalNote, isNotNull);
      expect(await documentService.getDocumentBytes(result.id), equals(bytes));
    });

    group('restoreDocumentToDisk outcomes', () {
      test('a confirmed save removes the vault copy', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('123456');
        final service = _RestoreSeamDocumentService(platformService, crypto);
        final src = File(p.join(tempDir.path, 'restore_me.pdf'));
        await src.writeAsBytes(List<int>.generate(4096, (i) => i % 256));
        final id =
            await service.saveDocumentFromFile(src, 'pdf', originalName: 'restore_me.pdf');
        service.saveFileResult = p.join(tempDir.path, 'restored.pdf');

        final outcome = await service.restoreDocumentToDisk(id);

        expect(outcome, DocumentRestoreOutcome.restored);
        // Per-id assertions, not counts: the document meta store is a
        // SharedPreferences singleton shared by every test in this isolate,
        // so earlier tests' rows are still listed here.
        final remaining = await service.listDocuments();
        expect(remaining.map((d) => d.id), isNot(contains(id)),
            reason: 'the vault copy is removed only after the save succeeded');
        expect(await service.getDocumentBytes(id), isNull);
      });

      test('a cancelled picker keeps the vault copy', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('123456');
        final service = _RestoreSeamDocumentService(platformService, crypto);
        final src = File(p.join(tempDir.path, 'cancelled.pdf'));
        await src.writeAsBytes(List<int>.generate(1024, (i) => i % 256));
        final id =
            await service.saveDocumentFromFile(src, 'pdf', originalName: 'cancelled.pdf');
        service.saveFileResult = null;

        final outcome = await service.restoreDocumentToDisk(id);

        expect(outcome, DocumentRestoreOutcome.cancelled);
        expect((await service.listDocuments()).map((d) => d.id), contains(id),
            reason: 'a cancelled save must never delete the vault copy');
        expect(await service.getDocumentBytes(id), isNotNull);
      });

      test('a failed write keeps the vault copy', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('123456');
        final service = _RestoreSeamDocumentService(platformService, crypto);
        final src = File(p.join(tempDir.path, 'failed.pdf'));
        await src.writeAsBytes(List<int>.generate(1024, (i) => i % 256));
        final id =
            await service.saveDocumentFromFile(src, 'pdf', originalName: 'failed.pdf');
        service.saveFileThrows = true;

        final outcome = await service.restoreDocumentToDisk(id);

        expect(outcome, DocumentRestoreOutcome.saveFailed);
        expect((await service.listDocuments()).map((d) => d.id), contains(id),
            reason: 'a failed save must never delete the vault copy');
        expect(await service.getDocumentBytes(id), isNotNull);
      });

      test('a vault delete failing after the save reports the duplicate', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('123456');
        final service = _RestoreSeamDocumentService(platformService, crypto);
        final src = File(p.join(tempDir.path, 'stuck.pdf'));
        await src.writeAsBytes(List<int>.generate(1024, (i) => i % 256));
        final id =
            await service.saveDocumentFromFile(src, 'pdf', originalName: 'stuck.pdf');
        service.saveFileResult = p.join(tempDir.path, 'stuck_copy.pdf');
        service.deleteThrows = true;

        final outcome = await service.restoreDocumentToDisk(id);

        expect(outcome, DocumentRestoreOutcome.restoredButVaultCopyRemains);
        expect((await service.listDocuments()).map((d) => d.id), contains(id),
            reason: 'the duplicate must actually exist when the message says so');
        expect(await service.getDocumentBytes(id), isNotNull);
      });

      test('an unknown id cancels without consulting the picker', () async {
        final platformService = AndroidPlatformService();
        final crypto = VaultCrypto(platformService, FakeKeystoreService());
        await crypto.initialize('123456');
        final service = _RestoreSeamDocumentService(platformService, crypto);
        service.saveFileResult = p.join(tempDir.path, 'should_not_be_written.pdf');

        final outcome = await service.restoreDocumentToDisk('no_such_doc');

        expect(outcome, DocumentRestoreOutcome.cancelled);
        expect(service.pickerCalls, 0,
            reason: 'nothing to restore means nothing to pick a location for');
      });
    });
  });
}

/// Minimal file_picker double. `importDocument` needs only `pickFiles`, and the
/// path it returns is what the pinned plugin returns in reality: a copy the
/// plugin wrote into the app's own cache directory.
class _FakeFilePicker extends FilePicker {
  final String path;
  /// The original's content URI, as Android populates `PlatformFile.identifier`
  /// (verified in the pinned plugin's FileInfo builder). Null on other doubles.
  final String? identifier;
  _FakeFilePicker(this.path, {this.identifier});

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('unused in this double') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
            name: 'picked.pdf', path: path, size: 4096, identifier: identifier),
      ]);
}

/// Puts restoreDocumentToDisk's picker behind a controllable seam and can fail
/// the vault delete, so every DocumentRestoreOutcome is reachable in a plain
/// ffi test without a real SAF dialog.
class _RestoreSeamDocumentService extends DocumentVaultService {
  _RestoreSeamDocumentService(super.platformService, super.crypto);

  String? saveFileResult;
  bool saveFileThrows = false;
  bool deleteThrows = false;
  int pickerCalls = 0;

  @override
  Future<String?> saveDocumentToDisk(Uint8List bytes, String fileName) async {
    pickerCalls++;
    if (saveFileThrows) throw Exception('SAF refused the write');
    return saveFileResult;
  }

  @override
  Future<void> deleteDocument(String id) async {
    if (deleteThrows) throw Exception('simulated vault delete failure');
    return super.deleteDocument(id);
  }
}
