// test/vault/crypto/constant_time_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/vault_kdf.dart';

void main() {
  group('constantTimeEquals', () {
    test('returns true for identical strings', () {
      expect(constantTimeEquals('hello world', 'hello world'), isTrue);
      expect(
        constantTimeEquals('v3:100000:abc123xyz', 'v3:100000:abc123xyz'),
        isTrue,
      );
    });

    test('returns false for different strings of the same length', () {
      expect(constantTimeEquals('hello world', 'hello workd'), isFalse);
      expect(constantTimeEquals('abcd', 'abce'), isFalse);
      expect(constantTimeEquals('1234', '5678'), isFalse);
    });

    test('returns false for different-length strings', () {
      expect(constantTimeEquals('hello', 'hello world'), isFalse);
      expect(constantTimeEquals('abc', 'abcd'), isFalse);
      expect(constantTimeEquals('longer string', 'short'), isFalse);
    });

    test('returns true for empty vs empty', () {
      expect(constantTimeEquals('', ''), isTrue);
    });

    test('returns false for empty vs non-empty', () {
      expect(constantTimeEquals('', 'non-empty'), isFalse);
      expect(constantTimeEquals('non-empty', ''), isFalse);
    });
  });
}
