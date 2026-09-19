// test/vault/crypto/media_file_decrypt_test.dart
//
// The photo vault draws every visible tile at once, so each tile's whole-file
// decrypt used to run on the UI isolate in the same frame window. Measured on
// the dev box before the fix (PROBE A/B below): 588 ms for one 3 MB photo and
// 2134 ms for a nine-tile grid, with ZERO event-loop ticks in both cases. That
// is the "little hang" reported on re-entering the photo vault.
//
// The fix runs the same AES pass inside the long-lived range worker
// (`RangeDecryptWorker.decryptFile`, `VaultCrypto.tryDecryptFileInWorker`,
// consumed by `FileVaultService._readDecryptedBlob`). This file pins:
//   1. what the old path cost (the probes, kept so the before-number is real);
//   2. byte-identical output for ALL FOUR on-disk formats the worker serves,
//      so the speed fix cannot silently change what a photo contains;
//   3. that the UI isolate keeps ticking while a photo decrypts (the fix);
//   4. the fallback contract: null, never a new exception, when the worker is
//      down or the vault is locked (behavior parity with the old null return).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:pointycastle/export.dart';
class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);

  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

/// Runs [work] while a 1 ms periodic timer counts how many times the event loop
/// got a chance to run. No Dart code can interleave with a synchronous AES pass
/// on the same isolate, so 0 ticks is direct evidence of a blocked UI: the
/// probes below record exactly that, because the old path never yields.
Future<({int ticks, Duration elapsed})> measureEventLoop(
  Future<void> Function() work,
) async {
  int ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
  final stopwatch = Stopwatch()..start();
  await work();
  stopwatch.stop();
  timer.cancel();
  return (ticks: ticks, elapsed: stopwatch.elapsed);
}

Uint8List randomBytes(int length, Random random) {
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// Builds a CTR blob (c1 or c2 header) independently of production code, so the
/// comparison is against an outside reference rather than the same helper.
Uint8List buildCtrBlob({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
  required List<int> magic,
}) {
  final aes = AESEngine()..init(true, KeyParameter(key));
  final counter = Uint8List.fromList(iv);
  final ksBlock = Uint8List(16);
  final ciphertext = Uint8List(plaintext.length);
  int offset = 0;
  while (offset + 16 <= plaintext.length) {
    aes.processBlock(counter, 0, ksBlock, 0);
    for (int i = 0; i < 16; i++) {
      ciphertext[offset + i] = plaintext[offset + i] ^ ksBlock[i];
    }
    for (int i = 15; i >= 0; i--) {
      counter[i] = (counter[i] + 1) & 0xFF;
      if (counter[i] != 0) break;
    }
    offset += 16;
  }
  if (offset < plaintext.length) {
    aes.processBlock(counter, 0, ksBlock, 0);
    final remaining = plaintext.length - offset;
    for (int i = 0; i < remaining; i++) {
      ciphertext[offset + i] = plaintext[offset + i] ^ ksBlock[i];
    }
  }
  final blob = Uint8List(8 + 16 + ciphertext.length);
  blob.setRange(0, 8, magic);
  blob.setRange(8, 24, iv);
  blob.setRange(24, blob.length, ciphertext);
  return blob;
}

/// Builds a headerless legacy blob: 16-byte IV followed by PKCS7-padded
/// AES-CBC ciphertext under the system key, matching the layout
/// `VaultCrypto._decryptLegacySystem` accepts (and the worker mirrors).
Uint8List buildLegacyBlob({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
}) {
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()));
  cipher.init(
    true,
    PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
  );
  final ciphertext = cipher.process(plaintext);
  final blob = Uint8List(16 + ciphertext.length);
  blob.setRange(0, 16, iv);
  blob.setRange(16, blob.length, ciphertext);
  return blob;
}

void main() {
  late Directory tempDir;
  late FakePlatformService platformService;
  late VaultCrypto crypto;
  final random = Random(4242);

  Future<File> writeBlob(String name, Uint8List bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<Uint8List> systemKeyBytes() async {
    final raw = platformService.store['system_key'];
    if (raw == null) {
      throw StateError('fixture error: system key was not provisioned');
    }
    return Uint8List.fromList(base64Decode(raw));
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_file_decrypt_');
    platformService = FakePlatformService();
    crypto = VaultCrypto(platformService, FakeKeystoreService());
    await crypto.initialize('1234');
    // Provision the device-local system key by touching a system-key path once;
    // the c1 and headerless cases below need it to exist.
    await crypto.encryptBreakInEvidenceBytes(Uint8List.fromList([1, 2, 3]));
  });

  tearDown(() async {
    crypto.lock();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('PROBES — what the old inline path cost (pre-fix baseline)', () {
    test('PROBE A — inline decryptSystem on one 3 MB v1 photo blob', () async {
      final plaintext = randomBytes(3 * 1024 * 1024, random);
      final blob = await crypto.encryptSystem(plaintext);

      final measurement = await measureEventLoop(() async {
        await crypto.decryptSystem(blob);
      });

      // ignore: avoid_print
      print('PROBE A: decryptSystem(3 MB v1) took '
          '${measurement.elapsed.inMilliseconds} ms, '
          'event-loop ticks = ${measurement.ticks}');
      expect(measurement.elapsed, greaterThan(Duration.zero));
    });

    test('PROBE B — 9 tiles decrypting at once, exactly like grid entry', () async {
      const tileCount = 9;
      final blobs = <Uint8List>[];
      for (int i = 0; i < tileCount; i++) {
        blobs.add(await crypto.encryptSystem(randomBytes(3 * 1024 * 1024, random)));
      }

      final measurement = await measureEventLoop(() async {
        await Future.wait(blobs.map((b) => crypto.decryptSystem(b)));
      });

      // ignore: avoid_print
      print('PROBE B: $tileCount concurrent decryptSystem(3 MB v1) took '
          '${measurement.elapsed.inMilliseconds} ms, '
          'event-loop ticks = ${measurement.ticks}');
      expect(measurement.elapsed, greaterThan(Duration.zero));
    });
  });

  group('worker whole-file decrypt — byte equality for every on-disk format', () {
    test('T1 — v1 CBC (the format photos are written in) matches the inline path', () async {
      // 3 MB + 91 bytes: multi-chunk and off the AES block boundary, so a
      // padding or tail-handling slip cannot hide.
      final plaintext = randomBytes(3 * 1024 * 1024 + 91, random);
      final blob = await crypto.encryptSystem(plaintext);
      final file = await writeBlob('t1_v1.blob', blob);

      final fromWorker = await crypto.tryDecryptFileInWorker(file);

      expect(fromWorker, isNotNull,
          reason: 'the worker must serve a v1 blob; null means the fix is inert');
      expect(fromWorker, equals(plaintext),
          reason: 'worker v1 output must equal the original photo bytes');
      expect(fromWorker, equals(await crypto.decryptSystem(blob)),
          reason: 'worker and inline v1 output must be byte-identical');
    });

    test('T2 — c2 CTR (master-DEK videos) is served byte-identically', () async {
      final plaintext = randomBytes(512 * 1024 + 57, random);
      final src = await writeBlob('t2_src.bin', plaintext);
      final blob = File('${tempDir.path}/t2_c2.blob');
      await crypto.encryptStreamSystemCtr(src, blob);

      final fromWorker = await crypto.tryDecryptFileInWorker(blob);

      expect(fromWorker, isNotNull);
      expect(fromWorker, equals(plaintext),
          reason: 'c2 bytes through the worker must equal the original');
    });

    test('T3 — c1 CTR (system key) is served byte-identically', () async {
      final systemKey = await systemKeyBytes();
      final plaintext = randomBytes(128 * 1024 + 19, random);
      final blob = await writeBlob(
        't3_c1.blob',
        buildCtrBlob(
          key: systemKey,
          iv: randomBytes(16, random),
          plaintext: plaintext,
          magic: kMediaMagicCtrV1,
        ),
      );

      final fromWorker = await crypto.tryDecryptFileInWorker(blob);

      expect(fromWorker, isNotNull,
          reason: 'the worker must serve every format the inline path accepts; '
              'a c1 blob reaching this code would otherwise decrypt inline but '
              'refuse in the worker, which would be a behavior change');
      expect(fromWorker, equals(plaintext));
    });
  });

  group('headerless legacy format (oldest blobs, system key)', () {
    test('T4 — IV + PKCS7 CBC with no magic header is served byte-identically', () async {
      final systemKey = await systemKeyBytes();
      final plaintext = randomBytes(64 * 1024 + 5, random);
      final blob = await writeBlob(
        't4_legacy.blob',
        buildLegacyBlob(
          key: systemKey,
          iv: randomBytes(16, random),
          plaintext: plaintext,
        ),
      );

      final fromWorker = await crypto.tryDecryptFileInWorker(blob);

      expect(fromWorker, isNotNull,
          reason: 'a headerless legacy blob must still decrypt; these are the oldest photos');
      expect(fromWorker, equals(plaintext));
      expect(fromWorker, equals(await crypto.decryptSystem(await blob.readAsBytes())),
          reason: 'worker and inline legacy output must be byte-identical');
    });

    test('T4b — a legacy blob with a bad tail is reported, never returned as bytes', () async {
      final systemKey = await systemKeyBytes();
      // 20 bytes cannot be IV(16) + a whole AES block, which the design treats
      // as corruption rather than "an empty photo".
      final blob = await writeBlob('t4b_bad.blob', randomBytes(20, random));

      final fromWorker = await crypto.tryDecryptFileInWorker(blob);

      expect(fromWorker, isNull,
          reason: 'corrupt input falls back to the caller, it is not reported as content');
      expect(systemKey.length, equals(32)); // fixture sanity
    });
  });

  group('FIX PROOF — the UI isolate keeps running while a photo decrypts', () {
    test('T5 — a 3 MB photo through the worker leaves the event loop alive', () async {
      final plaintext = randomBytes(3 * 1024 * 1024, random);
      final file = await writeBlob('t5_photo.blob', await crypto.encryptSystem(plaintext));
      // Warm the worker so its one-off spawn cost is not counted as decrypt time.
      await crypto.tryDecryptFileInWorker(file);

      final measurement = await measureEventLoop(() async {
        await crypto.tryDecryptFileInWorker(file);
      });

      // ignore: avoid_print
      print('T5: worker whole-file decrypt of a 3 MB photo took '
          '${measurement.elapsed.inMilliseconds} ms, '
          'event-loop ticks = ${measurement.ticks}');
      expect(measurement.ticks, greaterThan(0),
          reason: 'PROBE A measured 0 ticks on this same work; >0 proves the '
              'AES pass no longer runs on the isolate that paints the grid');
    });

    test('T5b — nine photo tiles in one frame window still leave the loop alive', () async {
      const tileCount = 9;
      final files = <File>[];
      for (int i = 0; i < tileCount; i++) {
        files.add(await writeBlob(
          't5b_$i.blob',
          await crypto.encryptSystem(randomBytes(3 * 1024 * 1024, random)),
        ));
      }
      await crypto.tryDecryptFileInWorker(files.first);

      final measurement = await measureEventLoop(() async {
        await Future.wait(files.map(crypto.tryDecryptFileInWorker));
      });

      // ignore: avoid_print
      print('T5b: $tileCount tiles through one worker took '
          '${measurement.elapsed.inMilliseconds} ms, '
          'event-loop ticks = ${measurement.ticks}');
      expect(measurement.ticks, greaterThan(0),
          reason: 'PROBE B measured 0 ticks for this exact grid workload');
    });
  });

  group('fallback contract — null instead of a new exception', () {
    test('T6 — a locked vault yields null, exactly as the old path yielded null', () async {
      final file = await writeBlob(
        't6_locked.blob',
        await crypto.encryptSystem(randomBytes(4096, random)),
      );
      crypto.lock();

      // The old `getPhoto` caught every error and returned null. If this threw,
      // the lock state would surface as a crash on paths that never caught it.
      final fromWorker = await crypto.tryDecryptFileInWorker(file);

      expect(fromWorker, isNull);
      expect(crypto.isUnlocked, isFalse);
    });

    test('T7 — unlocking again re-spawns the worker and still decrypts correctly', () async {
      final plaintext = randomBytes(256 * 1024 + 7, random);
      final file = await writeBlob('t7.sh', await crypto.encryptSystem(plaintext));

      expect(await crypto.tryDecryptFileInWorker(file), equals(plaintext));

      crypto.lock();
      expect(await crypto.tryDecryptFileInWorker(file), isNull,
          reason: 'the lock must dispose the worker that holds a key copy');

      await crypto.initialize('1234');

      final afterUnlock = await crypto.tryDecryptFileInWorker(file);
      expect(afterUnlock, equals(plaintext),
          reason: 'the worker is spawned per unlock and must serve the same blob '
              'with the same DEK after a lock/unlock cycle');
    });

    test('T8 — a corrupt v1 blob yields null rather than a damaged photo', () async {
      final blob = await crypto.encryptSystem(randomBytes(4096, random));
      // Corrupt the FINAL ciphertext block, which carries the PKCS7 padding.
      // Corrupting middle blocks would still unpad cleanly and return damaged
      // bytes; only a damaged pad block guarantees the decrypt must refuse
      // (random damage passes PKCS7 validation with ~1/256 probability).
      for (int i = blob.length - 8; i < blob.length; i++) {
        blob[i] = blob[i] ^ 0xFF;
      }
      final file = await writeBlob('t8_corrupt.blob', blob);

      final fromWorker = await crypto.tryDecryptFileInWorker(file);

      expect(fromWorker, isNull,
          reason: 'a damaged blob is a failure, never silently-returned bytes');
    });

    test('T9 — a missing file yields null (no tile is worth a crash)', () async {
      final fromWorker = await crypto.tryDecryptFileInWorker(
        File('${tempDir.path}/does_not_exist.blob'),
      );
      expect(fromWorker, isNull);
    });
  });
}
