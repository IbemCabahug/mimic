// test/vault/crypto/recovery_phrase_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/vault/crypto/recovery_phrase.dart';

void main() {
  group('RecoveryPhrase Tests', () {
    test('generate() produces 12 valid BIP39 words', () {
      final words = RecoveryPhrase.generate();
      expect(words.length, equals(12));
      for (final word in words) {
        expect(RecoveryPhrase.isValidWord(word), isTrue);
      }
    });

    test('isValidWord() validation logic', () {
      expect(RecoveryPhrase.isValidWord('abandon'), isTrue);
      expect(RecoveryPhrase.isValidWord('  ABANDON  '), isTrue); // should handle spaces and capitalization
      expect(RecoveryPhrase.isValidWord('zoo'), isTrue);
      expect(RecoveryPhrase.isValidWord('notaword'), isFalse);
    });

    test('deriveKey() produces deterministic 32-byte key', () {
      final words = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      
      final key1 = RecoveryPhrase.deriveKey(words, salt);
      final key2 = RecoveryPhrase.deriveKey(words, salt);
      
      expect(key1.length, equals(32));
      expect(key2, equals(key1));
      
      // different salt should produce different key
      final differentSalt = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final key3 = RecoveryPhrase.deriveKey(words, differentSalt);
      expect(key3, isNot(equals(key1)));
    });
  });
}
