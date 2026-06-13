// lib/vault/crypto/recovery_phrase.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'bip39_wordlist.dart';

class RecoveryPhrase {
  /// Uses dart:math Random.secure to pick 12 random words from kBip39Wordlist
  static List<String> generate() {
    final random = Random.secure();
    return List.generate(12, (_) {
      final index = random.nextInt(kBip39Wordlist.length);
      return kBip39Wordlist[index];
    });
  }

  static String normalizeWord(String w) {
    var normalized = w.replaceAll(RegExp(r'[\u200B\u200C\u200D\uFEFF]'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), '');
    return normalized.trim().toLowerCase();
  }

  static List<String> normalizeWords(List<String> words) {
    return words.map((w) => normalizeWord(w)).toList();
  }

  /// Joins words with a space separator and derives a 32-byte key using PBKDF2-HMAC-SHA256
  static Uint8List deriveKey(List<String> words, Uint8List salt) {
    final cleanWords = normalizeWords(words);
    final mnemonic = cleanWords.join(' ');
    final mnemonicBytes = Uint8List.fromList(utf8.encode(mnemonic));
    
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, 100000, 32));
    
    return pbkdf2.process(mnemonicBytes);
  }

  /// Returns true if the word exists in kBip39Wordlist
  static bool isValidWord(String word) {
    return kBip39Wordlist.contains(normalizeWord(word));
  }
}
