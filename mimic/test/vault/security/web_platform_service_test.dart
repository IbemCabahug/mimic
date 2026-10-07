// test/vault/security/web_platform_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/services/platform_service.dart';

void main() {
  group('SEC-12: WebPlatformService Hardening', () {
    late WebPlatformService service;

    setUp(() {
      service = WebPlatformService();
    });

    test('isWeb reports true', () {
      expect(service.isWeb(), isTrue);
    });

    test('vault file operations are explicitly disabled and throw UnsupportedError', () async {
      expect(
        () => service.saveEncryptedFile('test.bin', Uint8List.fromList([1, 2, 3])),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => service.readEncryptedFile('test.bin'),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => service.deleteFile('test.bin'),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => service.resolveVaultFile('test.bin'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
