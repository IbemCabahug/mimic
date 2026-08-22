import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/video_vault_service.dart';
import 'package:mimic/vault/services/media_stream_server.dart';
import 'package:path/path.dart' as p;

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
  });
}
