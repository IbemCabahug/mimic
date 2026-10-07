import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/export/vault_exporter.dart';
import 'package:mimic/vault/export/vault_importer.dart';

class FakeKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {}
  @override
  Future<String> wrap(String base64Data) async => 'hw1:$base64Data';
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
    tempDir = Directory.systemTemp.createTempSync('pin_bruteforce_sec02_test');
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

  Map<String, dynamic> extractMetadataJson(File file) {
    final bytes = file.readAsBytesSync();
    final lenData = ByteData.sublistView(bytes, 13, 17);
    final jsonLen = lenData.getUint32(0, Endian.big);
    final clamped = jsonLen <= bytes.length - 17 ? jsonLen : bytes.length - 17;
    final jsonStr = utf8.decode(bytes.sublist(17, 17 + clamped));
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  test('SEC-02: Exported backup contains ZERO PIN hashes, salts, or local wraps to prevent offline brute-force', () async {
    const pin = '1234';
    final crypto = VaultCrypto.instance;
    await crypto.initialize(pin);
    await crypto.storeRecoveryBlob(recoveryWords);

    // Verify local storage holds the credentials for unlock
    expect(secureStorageData['vault_pin_hash'], isNotNull);
    expect(secureStorageData['vault_salt'], isNotNull);
    expect(secureStorageData['master_key_wrapped'], isNotNull);

    // Build backup file
    final exportFile = await VaultExporter.buildExportFile(ProviderContainer());
    expect(await exportFile.exists(), isTrue);

    // Read metadata JSON header
    final metadata = extractMetadataJson(exportFile);

    // SEC-02 assertions:
    expect(metadata.containsKey('vault_pin_hash'), isFalse,
        reason: 'CRITICAL: vault_pin_hash must NOT be present in export (prevents offline dictionary attack)');
    expect(metadata.containsKey('vault_salt'), isFalse,
        reason: 'CRITICAL: vault_salt must NOT be present in export');
    expect(metadata.containsKey('master_key_wrapped'), isFalse,
        reason: 'CRITICAL: master_key_wrapped must NOT be present in export');

    // Only phrase-gated recovery secrets must be present
    expect(metadata.containsKey('recovery_blob'), isTrue);
    expect(metadata.containsKey('recovery_salt'), isTrue);

    // Simulate attacker inspecting entire raw file bytes for the pin hash
    final rawBytes = await exportFile.readAsBytes();
    final pinHash = secureStorageData['vault_pin_hash']!;
    final pinHashBytes = utf8.encode(pinHash);
    
    bool foundHashInRawFile = false;
    for (int i = 0; i <= rawBytes.length - pinHashBytes.length; i++) {
      bool match = true;
      for (int j = 0; j < pinHashBytes.length; j++) {
        if (rawBytes[i + j] != pinHashBytes[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        foundHashInRawFile = true;
        break;
      }
    }
    expect(foundHashInRawFile, isFalse, reason: 'PIN hash was leaked in raw backup file');

    // Restore on another device/clean state
    secureStorageData.clear();
    SharedPreferences.setMockInitialValues({});
    VaultCrypto(AndroidPlatformService(), FakeKeystoreService());

    final restored = await VaultImporter.importWithPhrase(exportFile, recoveryWords);
    expect(restored, isTrue);
    expect(VaultCrypto.instance.isUnlocked, isTrue);

    // Verify that the restored device DOES NOT receive any stale PIN hash
    expect(secureStorageData['vault_pin_hash'], isNull);
    expect(secureStorageData['vault_salt'], isNull);
    expect(secureStorageData['master_key_wrapped'], isNull);

    // Attempting to unlock with old PIN without reset-PIN step must fail loudly
    VaultCrypto.instance.lock();
    await expectLater(
      VaultCrypto.instance.initialize(pin),
      throwsA(isA<SystemKeyMissingException>()),
    );
  });
}
