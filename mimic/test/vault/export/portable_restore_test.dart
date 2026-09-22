// test/vault/export/portable_restore_test.dart
//
// F9 — portable restore, proven against a DEVICE-BOUND keystore.
//
// Why this file exists: the export/import suite passes `FakeKeystoreService`,
// which is a pass-through (its "wrap" is a no-op wrapper any instance can
// undo). That made the "uninstall simulation" test green while the real
// defect stood: `master_key_wrapped` inside a backup is `hw1:`-wrapped by the
// EXPORTING device's hardware keystore, so after a cross-device restore the
// persisted wrap is unreadable and every PIN unlock throws
// KeystoreInvalidException, looping the owner back into phrase recovery.
//
// The fix under test: after import, the owner lands on the reset-PIN flow,
// whose changePin() performs the complete LOCAL re-wrap — new salt, new
// verifier, and a hardware wrap created by THIS device (and recovery_blob is
// re-stored). The export file itself needs no change: its portable path is
// the recovery phrase (recovery_blob + recovery_salt), which is exactly what
// the importer uses to get the DEK back.

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
import 'package:mimic/vault/services/file_vault_service.dart';

/// A KeystoreService whose wraps are bound to one simulated device. A wrap
/// made by instance A can only be undone by instance A; any other instance
/// gets 'KEY_INVALID' — the same contract as AndroidKeystoreService across an
/// uninstall/reinstall, which the pass-through fake cannot model.
class DeviceBoundKeystore implements KeystoreService {
  DeviceBoundKeystore(this.deviceId);

  final String deviceId;

  @override
  Future<void> ensureKey() async {}

  @override
  Future<void> deleteKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    final inner = base64Decode(base64Data);
    final bound = Uint8List.fromList([
      ...utf8.encode('$deviceId|'),
      ...inner,
    ]);
    return base64Encode(bound);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final bound = base64Decode(base64Data);
    final marker = utf8.decode(bound, allowMalformed: true);
    final idx = marker.indexOf('|');
    if (idx < 0 || marker.substring(0, idx) != deviceId) {
      return 'KEY_INVALID';
    }
    return base64Encode(bound.sublist(idx + 1));
  }
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
    tempDir = Directory.systemTemp.createTempSync('mimic_portable_restore');
    appDocsPath = '${tempDir.path}/app_docs';
    downloadsPath = '${tempDir.path}/downloads';
    dbDirPath = '${tempDir.path}/databases';

    Directory(appDocsPath).createSync(recursive: true);
    Directory(downloadsPath).createSync(recursive: true);
    Directory(dbDirPath).createSync(recursive: true);

    secureStorageData.clear();
    SharedPreferences.setMockInitialValues({});
    await databaseFactory.setDatabasesPath(dbDirPath);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Slices the v2 metadata JSON out of an exported file:
  /// [4 magic][1 version][8 timestamp][4 json-length][json...]
  Map<String, dynamic> readMetadataJson(File file) {
    final bytes = file.readAsBytesSync();
    final lenData = ByteData.sublistView(bytes, 13, 17);
    final jsonLen = lenData.getUint32(0, Endian.big);
    final clamped = jsonLen <= bytes.length - 17 ? jsonLen : bytes.length - 17;
    final jsonStr = utf8.decode(bytes.sublist(17, 17 + clamped));
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  group('F9 portable restore (device-bound keystore)', () {
    test('CROSS-DEVICE: import recovers via the phrase, and the reset-PIN step re-wraps locally so the new PIN unlocks the vault',
        () async {
      // ── Device A: a real vault with one real encrypted photo ──────────
      final cryptoA = VaultCrypto(
        AndroidPlatformService(),
        DeviceBoundKeystore('device-A'),
      );
      await cryptoA.initialize('123456');
      await cryptoA.storeRecoveryBlob(recoveryWords);

      final fileServiceA = FileVaultService(AndroidPlatformService(), cryptoA);
      const photoPlain = 'f9_portable_photo_bytes';
      final photoBytes = Uint8List.fromList(utf8.encode(photoPlain));
      final photoId = await fileServiceA.savePhoto(
        photoBytes,
        'image/jpeg',
        originalName: 'trip.jpg',
      );

      // Sanity: device A's persisted wrap is hardware-bound, as in production.
      expect(secureStorageData['master_key_wrapped']!, startsWith('hw1:'));

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());
      expect(await exportedFile.exists(), isTrue);

      // The phrase-gated portability set rides in the metadata JSON.
      final meta = readMetadataJson(exportedFile);
      for (final key in ['recovery_blob', 'recovery_salt', 'vault_salt', 'vault_pin_hash']) {
        expect(meta.containsKey(key), isTrue,
            reason: '$key is what makes the backup restorable off-device');
      }
      expect(meta['master_key_wrapped'], startsWith('hw1:'),
          reason: 'the exported wrap is the EXPORTING device\'s hardware blob');

      // ── Wipe everything: the phone was reset / the app reinstalled ────
      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      final photosDbPath = '$dbDirPath/vault_files.db';
      if (await File(photosDbPath).exists()) await File(photosDbPath).delete();
      final vaultFilesDir = Directory('$appDocsPath/vault_files');
      if (await vaultFilesDir.exists()) await vaultFilesDir.delete(recursive: true);

      // ── Device B: import with the 12 words ────────────────────────────
      VaultCrypto(AndroidPlatformService(), DeviceBoundKeystore('device-B'));

      final imported = await VaultImporter.importWithPhrase(exportedFile, recoveryWords);
      expect(imported, isTrue,
          reason: 'the recovery-phrase path is device-independent and must succeed');
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      // THE DEFECT, documented: the persisted wrap still belongs to device A.
      // The next PIN unlock fails LOUDLY (never silently — a wrong key must
      // not pretend to work), and the app routes the owner to recovery.
      VaultCrypto.instance.lock();
      await expectLater(
        VaultCrypto.instance.initialize('123456'),
        throwsA(isA<KeystoreInvalidException>()),
      );

      // THE FIX: the reset-PIN flow (changePin) performs the complete local
      // re-wrap — exactly what ResetPinScreen drives after this import.
      await VaultCrypto.instance.recoverWithPhrase(recoveryWords);
      await VaultCrypto.instance.changePin('654321');
      await VaultCrypto.instance.storeRecoveryBlob();

      expect(secureStorageData['master_key_wrapped']!, startsWith('hw1:'),
          reason: 'the re-wrap must still be hardware-bound — to THIS device');

      // A fresh launch on device B with the chosen PIN unlocks the vault, and
      // the DEK was preserved by changePin, so restored files still decrypt.
      VaultCrypto.instance.lock();
      await VaultCrypto.instance.initialize('654321');
      expect(VaultCrypto.instance.isUnlocked, isTrue);

      final restored = await FileVaultService(
        AndroidPlatformService(),
        VaultCrypto.instance,
      ).getPhoto(photoId);
      expect(restored, isNotNull);
      expect(utf8.decode(restored!), equals(photoPlain));
    });

    test('CROSS-DEVICE without the reset-PIN step: the old PIN can never unlock (loud failure, not silent corruption)',
        () async {
      final cryptoA = VaultCrypto(
        AndroidPlatformService(),
        DeviceBoundKeystore('device-A'),
      );
      await cryptoA.initialize('123456');
      await cryptoA.storeRecoveryBlob(recoveryWords);

      final exportedFile = await VaultExporter.buildExportFile(ProviderContainer());

      secureStorageData.clear();
      SharedPreferences.setMockInitialValues({});
      VaultCrypto(AndroidPlatformService(), DeviceBoundKeystore('device-B'));

      expect(await VaultImporter.importWithPhrase(exportedFile, recoveryWords), isTrue);

      // Neither the old PIN nor a guessed PIN can unwrap device A's blob.
      VaultCrypto.instance.lock();
      await expectLater(
        VaultCrypto.instance.initialize('123456'),
        throwsA(isA<KeystoreInvalidException>()),
      );
      // Recovery still works — the escape hatch stays open at all times.
      expect(await VaultCrypto.instance.recoverWithPhrase(recoveryWords), isTrue);
    });
  });
}
