import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/export/mimic_v2_format.dart';
import 'package:mimic/vault/export/vault_importer.dart';

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
    'abandon', 'abandon', 'abandon', 'about',
  ];

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
          return secureStorageData[methodCall.arguments['key'] as String];
        }
        if (methodCall.method == 'delete') {
          secureStorageData.remove(methodCall.arguments['key'] as String);
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
    tempDir = Directory.systemTemp.createTempSync('path_traversal_sec01_test');
    appDocsPath = '${tempDir.path}/app_docs';
    downloadsPath = '${tempDir.path}/downloads';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(downloadsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    SharedPreferences.setMockInitialValues({});
    await databaseFactory.setDatabasesPath(dbDirPath);
    VaultCrypto(AndroidPlatformService(), FakeKeystoreService());
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('SEC-01: V2 import rejects backup with path traversal in metadata blob_ids', () async {
    final exploitFile = File('$downloadsPath/traversal_meta.mimic');
    final sink = exploitFile.openWrite();

    // Valid recovery phrase payload with malicious blob ID in blob_ids
    // Note: We need recovery_blob and recovery_salt so phrase verification passes
    final crypto = VaultCrypto.instance;
    await crypto.initialize('123456');
    await crypto.storeRecoveryBlob(recoveryWords);

    final recoveryBlob = secureStorageData['recovery_blob']!;
    final recoverySalt = secureStorageData['recovery_salt']!;

    const evilId = '../../evil_escape.txt';
    final metadataJson = jsonEncode({
      'recovery_blob': recoveryBlob,
      'recovery_salt': recoverySalt,
      'blob_ids': [evilId],
      'vault_photos_meta': '[]',
      'vault_videos_meta': '[]',
    });
    final metaBytes = Uint8List.fromList(utf8.encode(metadataJson));

    // Write header
    sink.add(kMimicMagic);
    sink.add([kMimicVersionV2]);
    final ts = ByteData(8)..setInt64(0, 1000, Endian.big);
    sink.add(ts.buffer.asUint8List());
    final metaLen = ByteData(4)..setUint32(0, metaBytes.length, Endian.big);
    sink.add(metaLen.buffer.asUint8List());
    sink.add(metaBytes);

    await sink.close();

    // Verify import throws FormatException
    await expectLater(
      VaultImporter.importWithPhrase(exploitFile, recoveryWords),
      throwsA(isA<FormatException>()),
    );

    // Verify no evil file escaped into tempDir or appDocsPath
    final escapedFile = File('${tempDir.path}/evil_escape.txt');
    expect(escapedFile.existsSync(), isFalse);
    final escapedFileApp = File('$appDocsPath/../evil_escape.txt');
    expect(escapedFileApp.existsSync(), isFalse);
  });

  test('SEC-01: V1 import rejects backup with path traversal in encrypted_files map', () async {
    final exploitFile = File('$downloadsPath/traversal_v1.mimic');

    final crypto = VaultCrypto.instance;
    await crypto.initialize('123456');
    await crypto.storeRecoveryBlob(recoveryWords);

    final recoveryBlob = secureStorageData['recovery_blob']!;
    final recoverySalt = secureStorageData['recovery_salt']!;

    final payload = {
      'recovery_blob': recoveryBlob,
      'recovery_salt': recoverySalt,
      'encrypted_files': {
        '../../hacked_file.txt': base64Encode(utf8.encode('PWNED')),
      },
    };
    final jsonStr = jsonEncode(payload);
    final payloadBytes = utf8.encode(jsonStr);
    final checksum = sha256.convert(payloadBytes).bytes;
    final ts = ByteData(8)..setInt64(0, 1000, Endian.big);

    final bytes = <int>[
      ...kMimicMagic,
      kMimicVersionV1,
      ...checksum,
      ...ts.buffer.asUint8List(),
      ...payloadBytes,
    ];
    await exploitFile.writeAsBytes(bytes);

    await expectLater(
      VaultImporter.importWithPhrase(exploitFile, recoveryWords),
      throwsA(isA<FormatException>()),
    );

    final hackedFile = File('${tempDir.path}/hacked_file.txt');
    expect(hackedFile.existsSync(), isFalse);
  });
}
