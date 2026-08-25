import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/media_format.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/screens/video_player_screen.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/media_stream_server.dart';
import 'package:mimic/vault/services/local_streaming_server.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> _secureStorage = {};
  final Map<String, Uint8List> _files = {};
  final Directory tempDir;

  FakePlatformService(this.tempDir);

  @override
  bool isWeb() => false;

  @override
  Future<void> secureWrite(String key, String value) async =>
      _secureStorage[key] = value;
  @override
  Future<String?> secureRead(String key) async => _secureStorage[key];
  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(_secureStorage);
  @override
  Future<void> secureDelete(String key) async => _secureStorage.remove(key);
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async =>
      _files[path] = data;
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => _files[path];
  @override
  Future<void> deleteFile(String path) async => _files.remove(path);

  @override
  Future<File> resolveVaultFile(String path) async {
    final dir = Directory(p.join(tempDir.path, 'vault_files'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dir.path, path));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String appDocsPath;
  late FakePlatformService platformService;
  late VaultCrypto crypto;
  late VideoVaultService videoVaultService;
  late Uint8List plaintext;
  late String testId;

  setUpAll(() {
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
    HttpOverrides.global = null;
    MediaStreamServer.instance.reset(); // ensure fresh state for every test

    tempDir = await Directory.systemTemp.createTemp('media_stream_server_test');
    appDocsPath = p.join(tempDir.path, 'app_docs');
    await Directory(appDocsPath).create(recursive: true);

    platformService = FakePlatformService(tempDir);
    crypto = VaultCrypto(platformService, FakeKeystoreService());
    await crypto.initialize('1234');
    videoVaultService = VideoVaultService(platformService, crypto);

    testId = 'test-video-cbc';

    final random = Random(42);
    plaintext = Uint8List(100 * 1024);
    for (int i = 0; i < plaintext.length; i++) {
      plaintext[i] = random.nextInt(256);
    }

    // Seed a CBC-encrypted blob file
    final srcFile = File(p.join(tempDir.path, 'src.bin'));
    await srcFile.writeAsBytes(plaintext);
    final blobFile = await platformService.resolveVaultFile(testId);
    await crypto.encryptStreamSystem(srcFile, blobFile);
    await srcFile.delete();
  });

  tearDown(() async {
    await MediaStreamServer.instance.stop();
    MediaStreamServer.instance.reset();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<HttpClientResponse> makeGet(Uri url) async {
    final client = HttpClient();
    final request = await client.getUrl(url);
    return await request.close();
  }

  Future<Uint8List> readBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  group('MediaStreamServer', () {
    test('a. init(...) with test deps, seed a CBC blob, urlFor(id): GET the returned URL and assert the body is byte-identical to the original plaintext', () async {
      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      final url = await MediaStreamServer.instance.urlFor(testId);
      final response = await makeGet(url);

      expect(response.statusCode, 200);
      final body = await readBody(response);
      expect(body, equals(plaintext));
    });

    test('b. Two urlFor calls in one session reuse the SAME port and token', () async {
      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      final url1 = await MediaStreamServer.instance.urlFor(testId);
      final url2 = await MediaStreamServer.instance.urlFor(testId);

      expect(url1.port, equals(url2.port));
      expect(url1.queryParameters['token'], equals(url2.queryParameters['token']));
    });

    test('c. After stop(), the previously returned URL no longer connects; a subsequent urlFor starts a fresh server and serves correctly again', () async {
      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      final url1 = await MediaStreamServer.instance.urlFor(testId);
      final response1 = await makeGet(url1);
      expect(response1.statusCode, 200);
      await readBody(response1);

      await MediaStreamServer.instance.stop();

      // Connecting to url1 should now fail
      bool connectionFailed = false;
      try {
        await makeGet(url1);
      } catch (_) {
        connectionFailed = true;
      }
      expect(connectionFailed, isTrue);

      // Subsequent urlFor starts a fresh server
      final url2 = await MediaStreamServer.instance.urlFor(testId);

      final response2 = await makeGet(url2);
      expect(response2.statusCode, 200);
      final body2 = await readBody(response2);
      expect(body2, equals(plaintext));
    });

    test('d. urlFor before init() throws StateError', () async {
      expect(
        () => MediaStreamServer.instance.urlFor(testId),
        throwsA(isA<StateError>()),
      );
    });

    test('e. C10/M34: after the manual-lock teardown path (AutoLock.dispose), the previously valid URL no longer connects', () async {
      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      final url = await MediaStreamServer.instance.urlFor(testId);
      final first = await makeGet(url);
      expect(first.statusCode, 200);
      await readBody(first);

      AutoLock().dispose();

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var stopped = false;
      while (DateTime.now().isBefore(deadline)) {
        try {
          final r = await makeGet(url);
          await readBody(r);
        } catch (_) {
          stopped = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(stopped, isTrue,
          reason: 'AutoLock.dispose must stop the media server so a locked vault never serves content');
    });

    testWidgets('f. M34: popping VideoPlayerScreen stops the media server', (tester) async {
      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      late Uri url;
      await tester.runAsync(() async {
        url = await MediaStreamServer.instance.urlFor(testId);
        final first = await makeGet(url);
        expect(first.statusCode, 200);
        await readBody(first);
      });

      await tester.pumpWidget(MaterialApp(home: VideoPlayerScreen(videoId: testId)));
      await tester.pump();
      // Give _initializePlayer's async work (real file IO, missing
      // video_player plugin) time to settle before popping.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        var stopped = false;
        while (DateTime.now().isBefore(deadline)) {
          try {
            final r = await makeGet(url);
            await readBody(r);
          } catch (_) {
            stopped = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(stopped, isTrue,
            reason: 'VideoPlayerScreen.dispose must stop the media server on pop');
      });
    });

    test('g. C10: a real c1 blob is refused rather than served', () async {
      // Build a REAL c1 blob: kMediaMagicCtrV1 + 16-byte IV + AES-CTR
      // ciphertext under the device-local system key (the legacy format).
      final random = Random.secure();
      final rawStoredKey = await platformService.secureRead('system_key');
      final Uint8List systemKey;
      if (rawStoredKey != null) {
        systemKey = base64Decode(rawStoredKey);
      } else {
        systemKey =
            Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
        await platformService.secureWrite('system_key', base64Encode(systemKey));
        await platformService.secureWrite('system_key_provisioned', 'true');
      }

      const marker = 'MIMIC_C1_SERVABLE_MARKER';
      final plainBytes = Uint8List.fromList([
        ...utf8.encode(marker),
        ...List<int>.filled(4096, 0x42),
      ]);
      final iv = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
      final aes = AESEngine()..init(true, KeyParameter(systemKey));
      final counter = Uint8List.fromList(iv);
      final ksBlock = Uint8List(16);
      final ciphertext = Uint8List(plainBytes.length);
      var off = 0;
      while (off < plainBytes.length) {
        aes.processBlock(counter, 0, ksBlock, 0);
        final n =
            (plainBytes.length - off) < 16 ? (plainBytes.length - off) : 16;
        for (int i = 0; i < n; i++) {
          ciphertext[off + i] = plainBytes[off + i] ^ ksBlock[i];
        }
        for (int i = 15; i >= 0; i--) {
          counter[i] = (counter[i] + 1) & 0xFF;
          if (counter[i] != 0) break;
        }
        off += n;
      }

      const c1Id = 'test-video-c1';
      final c1File = await platformService.resolveVaultFile(c1Id);
      final c1Blob = Uint8List(24 + ciphertext.length);
      c1Blob.setRange(0, 8, kMediaMagicCtrV1);
      c1Blob.setRange(8, 24, iv);
      c1Blob.setRange(24, c1Blob.length, ciphertext);
      await c1File.writeAsBytes(c1Blob);

      // Sanity: the blob is genuinely servable content — decryptRangeSystem's
      // legacy c1 branch recovers the marker while unlocked.
      final probe = await crypto.decryptRangeSystem(c1File, 0, marker.length);
      expect(utf8.decode(probe), equals(marker));

      // The server itself must refuse it instead of serving plaintext.
      final server = LocalStreamingServer(
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );
      await server.start();
      try {
        final url = Uri.parse(
            'http://127.0.0.1:${server.port}/media/$c1Id?token=${server.token}');
        final response = await makeGet(url);
        expect(response.statusCode, 500,
            reason: 'a c1 blob must be refused with the non-CTR rejection');
        final body = await readBody(response);
        expect(utf8.decode(body), contains('Blob not CTR-encrypted'));
      } finally {
        await server.stop();
      }
    });

    test('h. C10 regression guard: a c2 blob is still served correctly while unlocked', () async {
      final srcFile = File(p.join(tempDir.path, 'src_c2.bin'));
      await srcFile.writeAsBytes(plaintext);
      const c2Id = 'test-video-c2';
      final c2BlobFile = await platformService.resolveVaultFile(c2Id);
      await crypto.encryptStreamSystemCtr(srcFile, c2BlobFile);
      await srcFile.delete();
      expect((await c2BlobFile.readAsBytes()).sublist(0, 8),
          equals(kMediaMagicCtrV2));

      MediaStreamServer.instance.init(
        videoVaultService: videoVaultService,
        resolveVaultFile: platformService.resolveVaultFile,
        decryptRange: crypto.decryptRangeSystem,
      );

      final url = await MediaStreamServer.instance.urlFor(c2Id);
      final response = await makeGet(url);
      expect(response.statusCode, 200);
      final body = await readBody(response);
      expect(body, equals(plaintext),
          reason: 'c2 must remain servable byte-for-byte after restricting the accepted magic to c2-only');
    });
  });
}
