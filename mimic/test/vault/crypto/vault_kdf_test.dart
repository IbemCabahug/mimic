import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';

void main() {
  setUp(() {
    resetNativePbkdf2VerificationForTests();
  });

  group('derivePbkdf2Async & self-test fallback', () {
    test('a · native returns byte-correct results -> derivePbkdf2Async returns matching bytes and fake is called', () async {
      int callCount = 0;
      final testPassword = Uint8List.fromList(utf8.encode('test-pass'));
      final testSalt = Uint8List.fromList(utf8.encode('test-salt'));
      const testIterations = 10;
      const testKeyLength = 32;

      final expected = deriveVaultPinKek('test-pass', base64Encode(testSalt), testIterations);

      Future<Uint8List> fakeNative(Uint8List pw, Uint8List salt, int iter, int len) async {
        callCount++;
        final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
        pbkdf2.init(Pbkdf2Parameters(salt, iter, len));
        return pbkdf2.process(pw);
      }

      final result = await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(result, equals(expected));
      expect(callCount, equals(2));
    });

    test('b · native returns wrong bytes -> falls back to PointyCastle and fake is not called for second derivation', () async {
      int callCount = 0;
      final testPassword = Uint8List.fromList(utf8.encode('test-pass'));
      final testSalt = Uint8List.fromList(utf8.encode('test-salt'));
      const testIterations = 10;
      const testKeyLength = 32;

      final expected = deriveVaultPinKek('test-pass', base64Encode(testSalt), testIterations);

      Future<Uint8List> fakeNative(Uint8List pw, Uint8List salt, int iter, int len) async {
        callCount++;
        return Uint8List(len); // Wrong bytes (all zeroes)
      }

      final result1 = await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(result1, equals(expected));
      expect(callCount, equals(1)); // Only vector self-test was attempted

      final result2 = await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(result2, equals(expected));
      expect(callCount, equals(1)); // No second call because verification is cached as false
    });

    test('c · native throws -> falls back to PointyCastle', () async {
      int callCount = 0;
      final testPassword = Uint8List.fromList(utf8.encode('test-pass'));
      final testSalt = Uint8List.fromList(utf8.encode('test-salt'));
      const testIterations = 10;
      const testKeyLength = 32;

      final expected = deriveVaultPinKek('test-pass', base64Encode(testSalt), testIterations);

      Future<Uint8List> fakeNative(Uint8List pw, Uint8List salt, int iter, int len) async {
        callCount++;
        throw Exception('Simulated native crash');
      }

      final result = await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(result, equals(expected));
      expect(callCount, equals(1));
    });

    test('d · verification vector is derived only ONCE across consecutive calls', () async {
      int vectorCalls = 0;
      int payloadCalls = 0;
      final testPassword = Uint8List.fromList(utf8.encode('test-pass'));
      final testSalt = Uint8List.fromList(utf8.encode('test-salt'));
      const testIterations = 10;
      const testKeyLength = 32;

      Future<Uint8List> fakeNative(Uint8List pw, Uint8List salt, int iter, int len) async {
        if (iter == 4096) {
          vectorCalls++;
        } else {
          payloadCalls++;
        }
        final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
        pbkdf2.init(Pbkdf2Parameters(salt, iter, len));
        return pbkdf2.process(pw);
      }

      await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(vectorCalls, equals(1));
      expect(payloadCalls, equals(1));

      await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(vectorCalls, equals(1)); // Still 1, vector was not re-run
      expect(payloadCalls, equals(2));
    });

    test('e · verified native path returns native bytes rather than silently recomputing in Dart', () async {
      final testPassword = Uint8List.fromList(utf8.encode('test-pass'));
      final testSalt = Uint8List.fromList(utf8.encode('test-salt'));
      const testIterations = 10;
      const testKeyLength = 32;

      // Distinguishable 32-byte marker payload distinct from PointyCastle PBKDF2
      final distinguishableBytes = Uint8List.fromList(List.generate(32, (i) => 0x42));

      Future<Uint8List> fakeNative(Uint8List pw, Uint8List salt, int iter, int len) async {
        if (iter == 4096) {
          // Return byte-correct output for the verification vector
          final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
          pbkdf2.init(Pbkdf2Parameters(salt, iter, len));
          return pbkdf2.process(pw);
        }
        // Return distinguishable value for the actual payload derivation
        return distinguishableBytes;
      }

      final result = await derivePbkdf2Async(
        testPassword,
        testSalt,
        testIterations,
        testKeyLength,
        native: fakeNative,
      );

      expect(result, equals(distinguishableBytes));
    });
  });
}
