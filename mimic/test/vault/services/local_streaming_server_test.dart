import 'dart:async';
import 'package:mimic/vault/crypto/keystore_service.dart';
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

    crypto = VaultCrypto(FakePlatformService(), FakeKeystoreService());
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

      // c. Cross 256 KB sub-chunk boundary: bytes=200000-500000
      response = await makeGet('/media/$testId?token=${server.token}',
          range: 'bytes=200000-500000');
      expect(response.statusCode, 206);
      expect(response.contentLength, 300001);
      expect(response.headers.value('content-range'),
          'bytes 200000-500000/${plaintext.length}');
      body = await readBody(response);
      expect(body, equals(plaintext.sublist(200000, 500001)));

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

    test(
        '6. H15: stop() aborts an in-flight range decrypt instead of finishing it',
        () async {
      // Why this guard exists: before it the loop had NO cancellation check at
      // all and `stop()` only closed the socket, so a range already being served
      // ran to its END. A player asks for an open-ended range, so popping the
      // screen left the whole remainder of the file decrypting inline on the UI
      // isolate — the "vault is still laggy after playing" report.
      //
      // Evidence note: measured against the pre-fix code on 2026-09-16 — the
      // loop stood at decrypt call 11 of 32 when stop() returned (in 15 ms) and
      // still ran to 32; with the client gone at call 12 it also ran to 32
      // (worksheet section 13). What IS proven here is the `stop()` path,
      // deterministically; the "client went away" exit is a defensive branch
      // with no test of its own.
      //
      // Deterministic, not timing-based: decrypt call #2 is held open on a gate,
      // so the loop is provably INSIDE the loop when stop() runs.
      final gate = Completer<void>();
      int calls = 0;
      final abortable = LocalStreamingServer(
        resolveVaultFile: (id) async => File(p.join(vaultFilesDir, id)),
        decryptRange: (file, offset, length) async {
          calls++;
          if (calls == 2) await gate.future; // hold the loop mid-range
          return crypto.decryptRangeSystem(file, offset, length);
        },
      );
      await abortable.start();

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${abortable.port}/media/$testId'
          '?token=${abortable.token}'));
      request.headers.set('Range', 'bytes=0-'); // open-ended, as a player asks
      final response = await request.close();
      expect(response.statusCode, 206);
      unawaited(response.drain<void>().catchError((_) {}));

      // Precondition: the loop reached the held call. Bounded so a regression
      // that never streams fails as an assertion instead of hanging the suite.
      for (int i = 0; i < 200 && calls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(calls, greaterThanOrEqualTo(2),
          reason: 'the loop must reach the held second decrypt');

      await abortable.stop(); // the player screen being popped
      gate.complete(); // let the held decrypt return
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final callsAtStop = calls;

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, callsAtStop,
          reason: 'once stop() has run, no further decrypt may start: the loop '
              'must abandon the rest of the range (H15)');

      // Sanity: the range really was longer than the two calls we allowed, so
      // "it stopped" is not "it had already finished".
      expect(plaintext.length ~/ (256 * 1024), greaterThan(4));

      client.close(force: true);
    });

    test(
        '7. restart after stop() on the same instance streams again '
        '(the H15 abort flag must not leak into the new session)', () async {
      // stop() sets an abort flag for the session it is ending. start() is
      // documented as idempotent, so an instance may legitimately be started
      // again after being stopped — and if the flag survived, the new session
      // would answer every range with 206 and an EMPTY body, which looks like a
      // corrupt vault rather than a stale flag.
      final restarted = LocalStreamingServer(
        resolveVaultFile: (id) async => File(p.join(vaultFilesDir, id)),
        decryptRange: crypto.decryptRangeSystem,
      );
      await restarted.start();
      final client = HttpClient();

      Future<Uint8List> rangeBody(int start, int end) async {
        final request = await client.getUrl(Uri.parse(
            'http://127.0.0.1:${restarted.port}/media/$testId'
            '?token=${restarted.token}'));
        request.headers.set('Range', 'bytes=$start-$end');
        final response = await request.close();
        expect(response.statusCode, 206);
        return readBody(response);
      }

      // Session 1: the range decrypts.
      expect(await rangeBody(0, 999), equals(plaintext.sublist(0, 1000)));

      await restarted.stop(); // the player screen being popped
      await restarted.start(); // a later play, same instance

      // Session 2: the same range must still decrypt, not come back empty.
      expect(await rangeBody(0, 999), equals(plaintext.sublist(0, 1000)),
          reason: 'the abort flag set by the stopped session must not leak '
              'into the session that replaces it');

      client.close(force: true);
      await restarted.stop();
    });
  });
}
