import 'dart:io';
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
      final crypto = VaultCrypto(platformService);
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
      final crypto = VaultCrypto(platformService);
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
      final crypto = VaultCrypto(platformService);
      await crypto.initialize('123456');
      final documentService = DocumentVaultService(platformService, crypto);

      final tempFile = await documentService.getDocumentToTempFile('non_existent_id');
      expect(tempFile, isNull);
    });
  });
}
