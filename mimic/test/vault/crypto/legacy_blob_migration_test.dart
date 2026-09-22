// test/vault/crypto/legacy_blob_migration_test.dart
//
// F24 — legacy blob migration tests. Builds REAL system-keyed fixtures (c1
// CTR and legacy raw-IV CBC) against the same 'system_key' the production
// decrypt path reads, runs the migration, and proves: system-key blobs are
// converted to verified c2 under the DEK and decrypt byte-exact afterwards;
// modern blobs are left alone; failures and deferred files are reported
// honestly; and a killed run's temp files are swept without touching
// originals.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/legacy_blob_migration.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';

/// Device-bound fake keystore (same contract as AndroidKeystoreService
/// across an uninstall); this suite only needs it to be self-consistent.
class _BoundKeystore implements KeystoreService {
  @override
  Future<void> ensureKey() async {}

  @override
  Future<void> deleteKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    final inner = base64Decode(base64Data);
    return base64Encode(Uint8List.fromList([1, 2, 3, ...inner]));
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final bound = base64Decode(base64Data);
    if (bound.length < 4) return 'KEY_INVALID';
    return base64Encode(bound.sublist(4));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late Directory vaultDir;

  final Map<String, String> secureStorageData = {};

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'write') {
          secureStorageData[methodCall.arguments['key'] as String] =
              methodCall.arguments['value'] as String;
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
        if (methodCall.method == 'getTemporaryDirectory') {
          return appDocsPath;
        }
        return null;
      },
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mimic_f24_migration');
    appDocsPath = '${tempDir.path}/app_docs';
    vaultDir = Directory('$appDocsPath/vault_files');
    vaultDir.createSync(recursive: true);

    secureStorageData.clear();
    SharedPreferences.setMockInitialValues({});
    await databaseFactory.setDatabasesPath(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Unlocked crypto + the system key the fixtures are built against.
  Future<VaultCrypto> makeCrypto() async {
    final crypto = VaultCrypto(AndroidPlatformService(), _BoundKeystore());
    await crypto.initialize('123456');
    return crypto;
  }

  /// The device-local system key, provisioned exactly as production does
  /// (via _getSystemKey's lazy path) so the fixtures share the key the
  /// production decrypt path will read.
  Future<Uint8List> systemKey() async {
    final crypto = VaultCrypto(AndroidPlatformService(), _BoundKeystore());
    // The getter is private, but decryptBytes of a no-header blob exercises
    // the same provisioning path. Simpler and honest: provision through a
    // real production call — decrypt of legacy bytes provisions the key.
    final existing = secureStorageData['system_key'];
    if (existing == null) {
      // Provision by invoking the production lazy path: encryptBreakInEvidence
      // uses _getSystemKey(). Use decryptSystem with a legacy no-header blob
      // instead — same effect. Cheapest honest route: write via a probe
      // decrypt call on a tiny legacy blob.
      final dummyIv = Uint8List(16);
      final dummy = Uint8List.fromList([...dummyIv, ...List.filled(16, 0)]);
      try {
        await crypto.decryptSystem(dummy);
      } catch (_) {}
    }
    final stored = secureStorageData['system_key'];
    if (stored == null) {
      throw StateError('system_key was not provisioned by decryptSystem');
    }
    return base64Decode(stored);
  }

  /// Builds a c1 blob: MVKEYc1\0 + IV + AES-CTR(systemKey) of [plaintext].
  Future<File> writeC1Blob(String path, List<int> plaintext) async {
    final key = await systemKey();
    final iv = Uint8List.fromList(
      List<int>.generate(16, (i) => (i * 13 + 5) & 0xFF),
    );

    final aes = AESEngine()..init(true, KeyParameter(key));
    final counter = Uint8List.fromList(iv);
    final ksBlock = Uint8List(16);
    final body = BytesBuilder();

    var offset = 0;
    while (offset + 16 <= plaintext.length) {
      aes.processBlock(counter, 0, ksBlock, 0);
      for (int i = 0; i < 16; i++) {
        body.addByte(plaintext[offset + i] ^ ksBlock[i]);
      }
      for (int i = 15; i >= 0; i--) {
        if (++counter[i] != 0) break;
      }
      offset += 16;
    }
    if (offset < plaintext.length) {
      aes.processBlock(counter, 0, ksBlock, 0);
      for (int i = 0; i < plaintext.length - offset; i++) {
        body.addByte(plaintext[offset + i] ^ ksBlock[i]);
      }
    }

    final file = File(path);
    await file.writeAsBytes([...kMediaMagicCtrV1, ...iv, ...body.toBytes()]);
    return file;
  }

  /// Builds a legacy no-header blob: raw IV + AES-CBC(systemKey) of
  /// [plaintext], PKCS7-padded — the pre-magic format.
  Future<File> writeLegacyBlob(String path, List<int> plaintext) async {
    final key = await systemKey();
    final iv = Uint8List.fromList(
      List<int>.generate(16, (i) => (i * 5 + 3) & 0xFF),
    );

    final padLength = 16 - (plaintext.length % 16);
    final padded =
        Uint8List.fromList([...plaintext, ...List.filled(padLength, padLength)]);

    final cipher = CBCBlockCipher(AESEngine());
    cipher.init(true, ParametersWithIV(KeyParameter(key), iv));
    final out = BytesBuilder();
    out.add(iv);
    for (int off = 0; off < padded.length; off += 16) {
      final block = Uint8List(16);
      cipher.processBlock(padded, off, block, 0);
      out.add(block);
    }
    final file = File(path);
    await file.writeAsBytes(out.toBytes());
    return file;
  }

  group('F24 legacy blob migration', () {
    test('converts c1 and legacy blobs to verified c2, byte-exact, and leaves modern blobs alone',
        () async {
      final crypto = await makeCrypto();
      const c1Plain = 'c1-plaintext-that-must-survive-migration';
      const legacyPlain = 'legacy-blob-content!';
      const modernPlain = 'already-modern-content';

      final c1File = await writeC1Blob('${vaultDir.path}/photo_c1', utf8.encode(c1Plain));
      final legacyFile =
          await writeLegacyBlob('${vaultDir.path}/doc_legacy', utf8.encode(legacyPlain));

      // A modern c2 blob (what every new video write produces).
      final modernTmp = File('${tempDir.path}/plain_modern');
      await modernTmp.writeAsBytes(utf8.encode(modernPlain));
      final modernC2 = File('${vaultDir.path}/video_c2');
      await crypto.encryptStreamSystemCtr(modernTmp, modernC2);
      final modernBytesBefore = await modernC2.readAsBytes();

      // A DEK-keyed CBC v1 blob: old, but already phrase-recoverable.
      final cbcPlain = await crypto.encryptSystem(utf8.encode('cbc-v1-content'));
      final cbcFile = File('${vaultDir.path}/photo_cbcV1');
      await cbcFile.writeAsBytes(cbcPlain);
      final cbcBytesBefore = await cbcFile.readAsBytes();

      final report = await LegacyBlobMigration(crypto: crypto).migrateAll();

      expect(report.scanned, 4);
      expect(report.alreadyModern, 2, reason: 'c2 and cbcV1 are both DEK-keyed already');
      expect(report.migrated, 2, reason: 'c1 and legacyNoHeader must convert');
      expect(report.failed, 0);
      expect(report.deferred, 0);
      // Both converted files are now c2 under the DEK and decrypt byte-exact.
      for (final pair in [
        MapEntry(c1File, c1Plain),
        MapEntry(legacyFile, legacyPlain),
      ]) {
        final head = (await pair.key.openRead(0, 8).expand((b) => b).toList());
        expect(classifyMediaHeader(head), MediaBlobFormat.ctrV2,
            reason: '${pair.key.path} must now be c2');
        final outTmp = File('${tempDir.path}/out_${pair.key.uri.pathSegments.last}');
        await crypto.decryptStreamSystem(pair.key, outTmp);
        expect(utf8.decode(await outTmp.readAsBytes()), pair.value);
        await outTmp.delete();
      }

      // The untouched modern blobs are byte-identical.
      expect(await modernC2.readAsBytes(), modernBytesBefore);
      expect(await cbcFile.readAsBytes(), cbcBytesBefore);

      // No working copies left behind.
      final leftovers = vaultDir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.f24_plain') ||
              f.path.endsWith('.f24_c2') ||
              f.path.endsWith('.f24_verify'))
          .toList();
      expect(leftovers, isEmpty);

      // The summary is persisted for diagnostics.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyBlobMigration.lastRunPrefsKey), isNotNull);
    });
    test('is idempotent — a second run converts nothing and reports the truth', () async {
      final crypto = await makeCrypto();
      await writeC1Blob('${vaultDir.path}/photo_c1', utf8.encode('one'));
      await writeLegacyBlob('${vaultDir.path}/doc_legacy', utf8.encode('two'));

      final first = await LegacyBlobMigration(crypto: crypto).migrateAll();
      expect(first.migrated, 2);

      final second = await LegacyBlobMigration(crypto: crypto).migrateAll();
      expect(second.scanned, 2);
      expect(second.alreadyModern, 2);
      expect(second.migrated, 0);
      expect(second.failed, 0);
    });

    test('reports corrupt legacy files as failed, keeps converting the rest, and never touches the failed file',
        () async {
      final crypto = await makeCrypto();
      const goodPlain = 'good-c1-content-survives';

      // Corrupt legacy blob: headerless CBC whose final block carries an
      // invalid PKCS7 pad byte (0x00), which the decrypt path must reject.
      // (A truncated c1 file would NOT be honest corruption: CTR is a stream
      // cipher, truncation still "decrypts" to short garbage without error.)
      final corruptFile = File('${vaultDir.path}/photo_corrupt');
      final corruptBytes = List<int>.generate(48, (i) => (i * 31 + 7) & 0xFF);
      corruptBytes[47] = 0x00; // invalid pad
      await corruptFile.writeAsBytes(corruptBytes);

      final goodFile = await writeC1Blob('${vaultDir.path}/photo_good', utf8.encode(goodPlain));
      final goodBytesBefore = await goodFile.readAsBytes();

      final report = await LegacyBlobMigration(crypto: crypto).migrateAll();

      expect(report.failed, 1);
      expect(report.failedIds, contains('photo_corrupt'));
      expect(report.migrated, 1, reason: 'one failure must not stop the run');
      expect(
        await corruptFile.readAsBytes(),
        corruptBytes,
        reason: 'the failed file must be left byte-identical',
      );

      final outTmp = File('${tempDir.path}/out_good');
      await crypto.decryptStreamSystem(goodFile, outTmp);
      expect(utf8.decode(await outTmp.readAsBytes()), goodPlain);
      expect(await goodFile.readAsBytes(), isNot(goodBytesBefore));
      await outTmp.delete();
    });

    test('sweeps a killed run stale temp files without touching originals', () async {
      final crypto = await makeCrypto();
      final c1File = await writeC1Blob('${vaultDir.path}/photo_c1', utf8.encode('sweep-test'));

      // Stale partials from a hypothetical killed run.
      await File('${c1File.path}.f24_plain').writeAsBytes(utf8.encode('partial'));
      await File('${c1File.path}.f24_c2').writeAsBytes(utf8.encode('partial'));

      final report = await LegacyBlobMigration(crypto: crypto).migrateAll();

      expect(report.migrated, 1);
      expect(File('${c1File.path}.f24_plain').existsSync(), isFalse);
      expect(File('${c1File.path}.f24_c2').existsSync(), isFalse);
      expect(File('${c1File.path}.f24_verify').existsSync(), isFalse);
    });

    test('maxFiles batches the work honestly and the next run finishes it', () async {
      final crypto = await makeCrypto();
      await writeC1Blob('${vaultDir.path}/photo_a', utf8.encode('aaa'));
      await writeC1Blob('${vaultDir.path}/photo_b', utf8.encode('bbb'));

      final first = await LegacyBlobMigration(crypto: crypto).migrateAll(maxFiles: 1);
      expect(first.migrated, 1, reason: 'only one conversion per batch');

      final head =
          await File('${vaultDir.path}/photo_b').openRead(0, 8).expand((b) => b).toList();
      expect(classifyMediaHeader(head), MediaBlobFormat.ctrV1,
          reason: 'the unbudgeted file must be untouched');

      final second = await LegacyBlobMigration(crypto: crypto).migrateAll();
      expect(second.migrated, 1);
      expect(second.failed, 0);
    });
  });
}
