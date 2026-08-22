// test/vault/crypto/keystore_channel_test.dart
//
// Platform-channel-level tests for AndroidKeystoreService.wrap().
// These exercise the actual PlatformException → KeystoreWrapException
// conversion path, which fakes like FailingKeystoreService bypass entirely.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  final Map<String, Uint8List> fileStore = {};

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
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    fileStore[path] = data;
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => fileStore[path];

  @override
  Future<void> deleteFile(String path) async {
    fileStore.remove(path);
  }

  @override
  Future<File> resolveVaultFile(String path) async =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mimic/keystore');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AndroidKeystoreService.wrap platform-channel coverage', () {
    test(
        'PlatformException(WRAP_ERROR) surfaces as KeystoreWrapException',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'wrap') {
          throw PlatformException(
              code: 'WRAP_ERROR', message: 'simulated wrap failure');
        }
        return null;
      });

      final service = AndroidKeystoreService();
      final testData = base64Encode(Uint8List(32));

      await expectLater(
        service.wrap(testData),
        throwsA(isA<KeystoreWrapException>()),
        reason:
            'PlatformException with WRAP_ERROR must surface as KeystoreWrapException',
      );
    });

    test(
        'null result from platform channel surfaces as KeystoreWrapException',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'wrap') {
          return null;
        }
        return null;
      });

      final service = AndroidKeystoreService();
      final testData = base64Encode(Uint8List(32));

      await expectLater(
        service.wrap(testData),
        throwsA(isA<KeystoreWrapException>()),
        reason: 'null result from wrap must surface as KeystoreWrapException',
      );
    });
  });

  group('Vault-layer propagation', () {
    test(
        'wrap PlatformException propagates as KeystoreWrapException through VaultCrypto.initialize',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        switch (call.method) {
          case 'ensureKey':
            return null;
          case 'wrap':
            throw PlatformException(
                code: 'WRAP_ERROR', message: 'keystore broken');
          case 'unwrap':
            final Uint8List combined =
                call.arguments['bytes'] as Uint8List;
            if (combined.length < 12) {
              throw PlatformException(
                  code: 'KEY_INVALID', message: 'Invalid');
            }
            return combined.sublist(12);
          case 'deleteKey':
            return null;
          case 'elapsedRealtime':
            return 1000000;
          default:
            return null;
        }
      });

      final platform = FakePlatformService();
      final crypto = VaultCrypto(platform, AndroidKeystoreService());

      await expectLater(
        crypto.initialize('1111'),
        throwsA(isA<KeystoreWrapException>()),
        reason:
            'Wrap failure must propagate through VaultCrypto as a typed exception',
      );

      // Nothing should be persisted after the failure.
      expect(platform.store.containsKey('vault_salt'), isFalse);
      expect(platform.store.containsKey('vault_pin_hash'), isFalse);
      expect(platform.store.containsKey('master_key_wrapped'), isFalse);
    });
  });
}
