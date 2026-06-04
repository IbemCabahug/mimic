// lib/vault/crypto/vault_crypto.dart
// WEB NOTE: web storage is not secure. For testing only. Android uses full encryption.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import '../../core/services/platform_service.dart';
import 'recovery_phrase.dart';

class VaultCrypto extends ChangeNotifier {
  static VaultCrypto? _instance;
  static VaultCrypto get instance {
    if (_instance == null) {
      throw StateError('VaultCrypto has not been initialized yet.');
    }
    return _instance!;
  }

  final PlatformService _platformService;
  static final Map<String, String> _webKeyStore = {};

  static const int _keyLength = 32;
  static const int _ivLength = 16;
  static const int _pbkdf2Iterations = 100000;
  static const String _storageKeySalt = 'vault_salt';
  static const String _storageKeyPinHash = 'vault_pin_hash';

  Uint8List? _derivedKey;
  bool _isUnlocked = false;
  List<String>? _recoveryWords;

  VaultCrypto(this._platformService) {
    _instance = this;
  }

  bool get isUnlocked => _isUnlocked;

  Future<void> initialize(String pin) async {
    if (kIsWeb) {
      _webKeyStore[_storageKeySalt] = _generateRandomSalt();
      _webKeyStore[_storageKeyPinHash] = _hashPin(pin);
      _derivedKey = await _deriveKey(pin, _webKeyStore[_storageKeySalt]!);
      _isUnlocked = true;
      notifyListeners();
      return;
    }

    Uint8List salt;
    final storedSalt = await _platformService.secureRead(_storageKeySalt);
    if (storedSalt != null) {
      salt = base64Decode(storedSalt);
      final storedHash = await _platformService.secureRead(_storageKeyPinHash);
      if (storedHash != null && storedHash == _hashPin(pin)) {
        _derivedKey = await _deriveKey(pin, storedSalt);
        _isUnlocked = true;
        notifyListeners();
        return;
      } else {
        throw Exception('Invalid PIN');
      }
    }

    salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    await _platformService.secureWrite(_storageKeyPinHash, _hashPin(pin));
    _derivedKey = await _deriveKey(pin, base64Encode(salt));
    _isUnlocked = true;
    notifyListeners();
  }

  Uint8List encrypt(Uint8List plaintext) {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    if (plaintext.isEmpty) return Uint8List(0);
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipher(_derivedKey!, iv, true);
    final encrypted = cipher.process(plaintext);
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);
    return result;
  }

  Uint8List decrypt(Uint8List ciphertext) {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    if (ciphertext.isEmpty) return Uint8List(0);
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    final iv = ciphertext.sublist(0, _ivLength);
    final encrypted = ciphertext.sublist(_ivLength);
    final cipher = _createCipher(_derivedKey!, iv, false);
    try {
      return cipher.process(encrypted);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  void lock() {
    _isUnlocked = false;
    _derivedKey = null;
    notifyListeners();
  }

  void clearKey() {
    lock();
  }

  Future<void> storeRecoveryBlob([List<String>? recoveryWords]) async {
    if (!_isUnlocked || _derivedKey == null) {
      throw Exception('Vault is locked; cannot store recovery blob');
    }

    final words = recoveryWords ?? _recoveryWords;
    if (words == null || words.length != 12) {
      throw Exception('Invalid or missing recovery phrase');
    }

    final salt = _generateSecureRandomBytes(16);
    final recoveryKey = RecoveryPhrase.deriveKey(words, salt);
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipher(recoveryKey, iv, true);
    final encryptedMasterKey = cipher.process(_derivedKey!);

    final blob = Uint8List(iv.length + encryptedMasterKey.length);
    blob.setRange(0, iv.length, iv);
    blob.setRange(iv.length, blob.length, encryptedMasterKey);

    await _platformService.secureWrite('recovery_blob', base64Encode(blob));
    await _platformService.secureWrite('recovery_salt', base64Encode(salt));
  }

  Future<void> changePin(String newPin) async {
    final salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    await _platformService.secureWrite(_storageKeyPinHash, _hashPin(newPin));
    if (!kIsWeb) {
      await _platformService.secureWrite('vault_pin', newPin);
      await _platformService.secureWrite('wrong_attempts', '0');
    }
    _derivedKey = await _deriveKey(newPin, base64Encode(salt));
    _isUnlocked = true;
    notifyListeners();
  }

  Future<bool> recoverWithPhrase(List<String> recoveryWords) async {
    final storedBlob = await _platformService.secureRead('recovery_blob');
    final storedSalt = await _platformService.secureRead('recovery_salt');
    if (storedBlob == null || storedSalt == null) {
      return false;
    }

    try {
      final salt = base64Decode(storedSalt);
      final blob = base64Decode(storedBlob);

      final recoveryKey = RecoveryPhrase.deriveKey(recoveryWords, salt);

      if (blob.length < _ivLength) return false;
      final iv = blob.sublist(0, _ivLength);
      final encryptedMasterKey = blob.sublist(_ivLength);

      final cipher = _createCipher(recoveryKey, iv, false);
      final masterKey = cipher.process(encryptedMasterKey);

      if (masterKey.length != _keyLength) return false;

      _derivedKey = masterKey;
      _isUnlocked = true;
      _recoveryWords = recoveryWords;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List> encryptBytes(Uint8List plaintext) async {
    return encryptSystem(plaintext);
  }

  Future<Uint8List> decryptBytes(Uint8List ciphertext) async {
    return decryptSystem(ciphertext);
  }

  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    final encrypted = encrypt(data);
    if (kIsWeb) {
      _webKeyStore['file_$path'] = base64Encode(encrypted);
      return;
    }
    await _platformService.saveEncryptedFile(path, encrypted);
  }

  Future<Uint8List?> readEncryptedFile(String path) async {
    if (kIsWeb) {
      final encoded = _webKeyStore['file_$path'];
      if (encoded != null) return decrypt(base64Decode(encoded));
      return null;
    }
    final encrypted = await _platformService.readEncryptedFile(path);
    if (encrypted != null) return decrypt(encrypted);
    return null;
  }

  Future<void> deleteEncryptedFile(String path) async {
    if (kIsWeb) {
      _webKeyStore.remove('file_$path');
      return;
    }
    await _platformService.deleteFile(path);
  }

  String encryptString(String plaintext) {
    final bytes = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = encrypt(bytes);
    return base64Encode(encrypted);
  }

  String decryptString(String ciphertext) {
    final bytes = base64Decode(ciphertext);
    final decrypted = decrypt(bytes);
    return utf8.decode(decrypted);
  }

  Future<Uint8List> _getSystemKey() async {
    final storedKey = await _platformService.secureRead('system_key');
    if (storedKey != null) {
      return base64Decode(storedKey);
    }
    final newKey = _generateSecureRandomBytes(32);
    await _platformService.secureWrite('system_key', base64Encode(newKey));
    return newKey;
  }

  Future<Uint8List> encryptSystem(Uint8List plaintext) async {
    if (plaintext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipher(key, iv, true);
    final encrypted = cipher.process(plaintext);
    final result = Uint8List(iv.length + encrypted.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, encrypted);
    return result;
  }

  Future<Uint8List> decryptSystem(Uint8List ciphertext) async {
    if (ciphertext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    final iv = ciphertext.sublist(0, _ivLength);
    final encrypted = ciphertext.sublist(_ivLength);
    final cipher = _createCipher(key, iv, false);
    return cipher.process(encrypted);
  }

  String _hashPin(String pin) {
    final bytes = Uint8List.fromList(utf8.encode(pin));
    final digest = SHA256Digest().process(bytes);
    return base64Encode(digest);
  }

  String _generateRandomSalt() {
    return base64Encode(_generateSecureRandomBytes(16));
  }

  Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  Future<Uint8List> _deriveKey(String pin, String saltBase64) async {
    final salt = base64Decode(saltBase64);
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
    return pbkdf2.process(pinBytes);
  }

  BlockCipher _createCipher(Uint8List key, Uint8List iv, bool forEncryption) {
    final cipher = CBCBlockCipher(AESEngine());
    final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
    paddedCipher.init(
      forEncryption,
      PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null),
    );
    return paddedCipher;
  }
}

final vaultCryptoProvider = ChangeNotifierProvider<VaultCrypto>((ref) {
  return VaultCrypto(ref.read(platformServiceProvider));
});
