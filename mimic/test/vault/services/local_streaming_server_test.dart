import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/local_streaming_server.dart';
import 'package:path/path.dart' as p;

class FakePlatformService implements PlatformService {
  final Map<String, String> _secureStorage = {};
  final Map<String, Uint8List> _files = {};

  @override
  bool isWeb() => false;

  @override
  Future<void> secureWrite(String key, String value) async =>
      _secureStorage[key] = value;
  @override
  Future<String?> secureRead(String key) async => _secureStorage[key];
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
  Future<File> resolveVaultFile(String path) async =>
      throw UnimplementedError();
}

void main() {
  late VaultCrypto crypto;
  late Directory tempDir;
  late String vaultFilesDir;
  late LocalStreamingServer server;
  late Uint8List plaintext;
  late String testId;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('streaming_server_test');
    vaultFilesDir = p.join(tempDir.path, 'vault_files');
    Directory(vaultFilesDir).createSync();

    crypto = VaultCrypto(FakePlatformService());
    await crypto.initialize('1234');

    testId = 'test-video-001';

    // 2 MB + 57 bytes (not aligned to 16)
    final random = Random(42);
    plaintext = Uint8List(2 * 1024 * 1024 + 57);
    for (int i = 0; i < plaintext.length; i++) {
      plaintext[i] = random.nextInt(256);
    }

    // Create plaintext source file, encrypt as CTR, delete source
    final srcFile = File(p.join(tempDir.path, 'src.bin'));
    await srcFile.writeAsBytes(plaintext);
    final blobFile = File(p.join(vaultFilesDir, testId));
    await crypto.encryptStreamSystemCtr(srcFile, blobFile);
    await srcFile.delete();

    // Create and start server
    server = LocalStreamingServer(
      resolveVaultFile: (id) async => File(p.join(vaultFilesDir, id)),
      decryptRange: crypto.decryptRangeSystem,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // --- HTTP helpers ---

  Future<HttpClientResponse> makeGet(String path, {String? range}) async {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (range != null) {
      request.headers.set('Range', range);
    }
    return await request.close();
  }

  Future<Uint8List> readBody(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  // --- Tests ---

  group('LocalStreamingServer', () {
    test('1. Auth: no token -> 403, wrong token -> 403, correct -> success',
        () async {
      // No token
      var response = await makeGet('/media/$testId');
      expect(response.statusCode, 403);
      await readBody(response); // drain

      // Wrong token
      response = await makeGet('/media/$testId?token=wrongtoken');
      expect(response.statusCode, 403);
      await readBody(response);

      // Correct token
      response = await makeGet('/media/$testId?token=${server.token}');
      expect(response.statusCode, 200);
      await readBody(response);
    });

    test(
        '2. Full GET (no Range) -> 200, Content-Length == plaintextLength, body == plaintext',
        () async {
      final response =
          await makeGet('/media/$testId?token=${server.token}');
      expect(response.statusCode, 200);
      expect(response.contentLength, plaintext.length);
      expect(response.headers.value('accept-ranges'), 'bytes');

      final body = await readBody(response);
      expect(body.length, plaintext.length);
      expect(body, equals(plaintext));
    });

    test('3. Range GET -> 206 with correct Content-Range and body', () async {
      // a. Aligned range: bytes=0-1023
      var response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=0-1023');
      expect(response.statusCode, 206);
      expect(response.contentLength, 1024);
      expect(response.headers.value('content-range'),
          'bytes 0-1023/${plaintext.length}');
      var body = await readBody(response);
      expect(body, equals(plaintext.sublist(0, 1024)));

      // b. Unaligned start: bytes=101-250
      response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=101-250');
      expect(response.statusCode, 206);
      expect(response.contentLength, 150);
      expect(response.headers.value('content-range'),
          'bytes 101-250/${plaintext.length}');
      body = await readBody(response);
      expect(body, equals(plaintext.sublist(101, 251)));

      // c. Cross 1 MB sub-chunk boundary: bytes=1000000-1200000
      response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=1000000-1200000');
      expect(response.statusCode, 206);
      expect(response.contentLength, 200001);
      expect(response.headers.value('content-range'),
          'bytes 1000000-1200000/${plaintext.length}');
      body = await readBody(response);
      expect(body, equals(plaintext.sublist(1000000, 1200001)));

      // d. Open-ended range: bytes=N-  (last 100 bytes)
      final openStart = plaintext.length - 100;
      response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=$openStart-');
      expect(response.statusCode, 206);
      expect(response.contentLength, 100);
      expect(response.headers.value('content-range'),
          'bytes $openStart-${plaintext.length - 1}/${plaintext.length}');
      body = await readBody(response);
      expect(body, equals(plaintext.sublist(openStart)));

      // e. Final byte
      final lastByteOffset = plaintext.length - 1;
      response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=$lastByteOffset-$lastByteOffset');
      expect(response.statusCode, 206);
      expect(response.contentLength, 1);
      expect(response.headers.value('content-range'),
          'bytes $lastByteOffset-$lastByteOffset/${plaintext.length}');
      body = await readBody(response);
      expect(body, equals(plaintext.sublist(lastByteOffset)));
    });

    test('4. Path safety: traversal and separators -> 400/404', () async {
      // ID with ".."
      var response =
          await makeGet('/media/..secret?token=${server.token}');
      expect(response.statusCode, 400);
      await readBody(response);

      // ID with backslash (URL-encoded)
      response = await makeGet('/media/foo%5Cbar?token=${server.token}');
      expect(response.statusCode, 400);
      await readBody(response);

      // Non-existent but valid ID -> 404
      response =
          await makeGet('/media/nonexistent-id?token=${server.token}');
      expect(response.statusCode, 404);
      await readBody(response);

      // Completely wrong path
      response = await makeGet('/other/path?token=${server.token}');
      expect(response.statusCode, 404);
      await readBody(response);
    });

    test('5. Lifecycle: after stop(), request fails to connect', () async {
      final savedPort = server.port!;
      await server.stop();

      bool connectionFailed = false;
      try {
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse(
              'http://127.0.0.1:$savedPort/media/$testId?token=anytoken'),
        );
        await request.close();
      } catch (e) {
        connectionFailed = true;
      }
      expect(connectionFailed, isTrue);
    });
  });
}
