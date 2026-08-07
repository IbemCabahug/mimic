// lib/vault/crypto/vault_crypto.dart
// WEB NOTE: web storage is not secure. For testing only. Android uses full encryption.

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'vault_kdf.dart';

import '../../core/services/platform_service.dart';
import 'recovery_phrase.dart';
import 'keystore_service.dart';

class SystemKeyMissingException implements Exception {
  final String message;
  SystemKeyMissingException([this.message =
    'System key is missing but the vault was already provisioned. Refusing to regenerate to avoid orphaning encrypted data.']);
  @override
  String toString() => 'SystemKeyMissingException: $message';
}

class VaultCrypto extends ChangeNotifier {
  static VaultCrypto? _instance;
  static VaultCrypto get instance {
    if (_instance == null) {
      throw StateError('VaultCrypto has not been initialized yet.');
    }
    return _instance!;
  }

  final PlatformService _platformService;
  final KeystoreService _keystoreService;
  static final Map<String, String> _webKeyStore = {};

  static const int _keyLength = 32;
  static const int _ivLength = 16;

  static const String _storageKeySalt = 'vault_salt';
  static const String _storageKeyPinHash = 'vault_pin_hash';
  static const String _storageKeyMasterWrapped = 'master_key_wrapped';
  static const List<int> _mediaMagic = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x76, 0x31, 0x00]; // "MVKEYv1\0"
  static const List<int> _mediaMagicCtr = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x63, 0x31, 0x00]; // "MVKEYc1\0"

  Uint8List? _derivedKey;
  Uint8List? _temporaryKek;
  bool _isUnlocked = false;
  List<String>? _recoveryWords;
  bool _needsHardwareMigration = false;
  bool _hasRecoveryPhrase = false;

  VaultCrypto(this._platformService, [KeystoreService? keystoreService]) 
      : _keystoreService = keystoreService ?? AndroidKeystoreService() {
    _instance = this;
  }

  bool get isUnlocked => _isUnlocked;
  bool get needsHardwareMigration => _needsHardwareMigration;
  bool get hasRecoveryPhrase => _hasRecoveryPhrase;

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
      if (storedHash == null) {
        throw Exception('Invalid PIN');
      }
      // Derive the candidate master key once; used to both verify and unlock.
      final candidateKey = await _deriveKey(pin, storedSalt);
      bool ok;
      bool needsMigration = false;
      if (storedHash.startsWith('v2:')) {
        ok = _constantTimeEquals(storedHash, _verifierForKey(candidateKey));
      } else {
        // Legacy unsalted SHA-256(pin) verifier — upgrade on success.
        ok = _constantTimeEquals(storedHash, _hashPin(pin));
        needsMigration = ok;
      }
      if (!ok) {
        throw Exception('Invalid PIN');
      }
      // Resolve the stable data key (DEK) through the PIN-derived wrapping key.
      final kek = _deriveKek(candidateKey);
      final wrapped =
          await _platformService.secureRead(_storageKeyMasterWrapped);
      Uint8List dek;
      bool needsHwMigration = false;
      if (wrapped == null) {
        // Legacy vault: the PIN-derived key IS the current data key.
        dek = candidateKey;
        await _platformService.secureWrite(
            _storageKeyMasterWrapped, _wrapKey(dek, kek));
        needsHwMigration = true;
      } else {
        if (wrapped.startsWith('hw1:')) {
          final actualWrapped = wrapped.substring(4);
          final inner = await _keystoreService.unwrap(actualWrapped);
          if (inner == 'KEY_INVALID') {
            throw KeystoreInvalidException();
          }
          dek = _unwrapKey(inner, kek);
        } else {
          dek = _unwrapKey(wrapped, kek);
          needsHwMigration = true;
        }
      }
      _derivedKey = dek;
      _needsHardwareMigration = needsHwMigration;
      if (needsHwMigration) {
        _temporaryKek = kek;
      }
      _isUnlocked = true;
      if (needsMigration) {
        await _platformService.secureWrite(
            _storageKeyPinHash, _verifierForKey(candidateKey));
      }
      await _platformService.secureWrite('vault_setup_completed', 'true');
      await _platformService.secureDelete('vault_wiped');
      
      final blob = await _platformService.secureRead('recovery_blob');
      _hasRecoveryPhrase = blob != null;
      
      notifyListeners();
      return;
    }

    salt = _generateSecureRandomBytes(16);
    final saltBase64 = base64Encode(salt);
    final candidateKey = await _deriveKey(pin, saltBase64);
    final hashVerifier = _verifierForKey(candidateKey);
    final kek = _deriveKek(candidateKey);
    final innerWrapped = _wrapKey(candidateKey, kek);
    
    // Do hardware wrap first. If this throws, nothing is persisted.
    final hwWrapped = await _keystoreService.wrap(innerWrapped);

    // Clear stale vault keys to avoid AutoBackup corruption
    await _platformService.secureDelete(_storageKeyMasterWrapped);
    await _platformService.secureDelete('recovery_blob');
    await _platformService.secureDelete('recovery_salt');
    await _platformService.secureDelete('wrong_attempts');
    await _platformService.secureDelete('lockout_set_wall');
    await _platformService.secureDelete('lockout_set_elapsed');
    await _platformService.secureDelete('lockout_duration_ms');

    // Persist new vault data atomically
    await _platformService.secureWrite(_storageKeySalt, saltBase64);
    await _platformService.secureWrite(_storageKeyPinHash, hashVerifier);
    await _platformService.secureWrite(_storageKeyMasterWrapped, 'hw1:$hwWrapped');
    
    _derivedKey = candidateKey;
    _needsHardwareMigration = false;
    _hasRecoveryPhrase = false;
    await _platformService.secureWrite('vault_setup_completed', 'true');
    await _platformService.secureDelete('vault_wiped');
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
    if (_derivedKey != null) {
      _derivedKey!.fillRange(0, _derivedKey!.length, 0);
    }
    _derivedKey = null;
    if (_temporaryKek != null) {
      _temporaryKek!.fillRange(0, _temporaryKek!.length, 0);
      _temporaryKek = null;
    }
    notifyListeners();
  }

  void clearKey() {
    lock();
  }

  bool _isStoringRecovery = false;

  Future<void> storeRecoveryBlob([List<String>? recoveryWords]) async {
    if (_isStoringRecovery) return;
    _isStoringRecovery = true;
    try {
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
      _hasRecoveryPhrase = true;
    } finally {
      _isStoringRecovery = false;
    }
  }

  Future<void> changePin(String newPin) async {
    // The data key (DEK) must NOT change when the PIN changes, or all existing
    // vault data would be orphaned. Re-wrap the SAME DEK under the new PIN.
    if (_derivedKey == null) {
      throw Exception('Vault must be unlocked before changing the PIN');
    }
    final dek = _derivedKey!;
    final salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    final newCandidateKey = await _deriveKey(newPin, base64Encode(salt));
    await _platformService.secureWrite(
        _storageKeyPinHash, _verifierForKey(newCandidateKey));
    final newKek = _deriveKek(newCandidateKey);
    final innerWrapped = _wrapKey(dek, newKek);
    final hwWrapped = await _keystoreService.wrap(innerWrapped);
    await _platformService.secureWrite(
        _storageKeyMasterWrapped, 'hw1:$hwWrapped');
    if (!kIsWeb) {
      await _platformService.secureWrite('vault_pin', newPin);
      await _platformService.secureWrite('wrong_attempts', '0');
      await _platformService.secureWrite('vault_setup_completed', 'true');
      await _platformService.secureDelete('vault_wiped');
    }
    _derivedKey = dek; // unchanged — the whole point of the fix
    _needsHardwareMigration = false;
    _isUnlocked = true;
    notifyListeners();
  }

  Future<void> migrateToHardwareBinding() async {
    if (!_isUnlocked || _derivedKey == null || _temporaryKek == null) {
      throw Exception('Vault locked or missing KEK');
    }
    if (!_needsHardwareMigration) return;
    
    final innerWrapped = _wrapKey(_derivedKey!, _temporaryKek!);
    final hwWrapped = await _keystoreService.wrap(innerWrapped);
    await _platformService.secureWrite(_storageKeyMasterWrapped, 'hw1:$hwWrapped');
    _needsHardwareMigration = false;
    _temporaryKek!.fillRange(0, _temporaryKek!.length, 0);
    _temporaryKek = null;
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
      final isProvisioned = await _platformService.secureRead('system_key_provisioned');
      if (isProvisioned != 'true') {
        await _platformService.secureWrite('system_key_provisioned', 'true');
      }
      return base64Decode(storedKey);
    }
    final isProvisioned = await _platformService.secureRead('system_key_provisioned');
    if (isProvisioned == 'true') {
      throw SystemKeyMissingException();
    }
    final newKey = _generateSecureRandomBytes(32);
    await _platformService.secureWrite('system_key', base64Encode(newKey));
    await _platformService.secureWrite('system_key_provisioned', 'true');
    return newKey;
  }

  Future<Uint8List> encryptSystem(Uint8List plaintext) async {
    if (plaintext.isEmpty) return Uint8List(0);
    final encrypted = encrypt(plaintext);
    final result = Uint8List(_mediaMagic.length + encrypted.length);
    result.setRange(0, _mediaMagic.length, _mediaMagic);
    result.setRange(_mediaMagic.length, result.length, encrypted);
    return result;
  }

  bool isLegacySystemBlob(Uint8List cipher) {
    if (cipher.length < _mediaMagic.length) return true;
    for (int i = 0; i < _mediaMagic.length; i++) {
      if (cipher[i] != _mediaMagic[i]) return true;
    }
    return false;
  }

  Future<void> encryptStream(File src, File dest) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    final iv = _generateSecureRandomBytes(_ivLength);
    final raf = await dest.open(mode: FileMode.write);
    try {
      await raf.writeFrom(iv);

      final cipher = CBCBlockCipher(AESEngine());
      cipher.init(true, ParametersWithIV(KeyParameter(_derivedKey!), iv));

      final srcRaf = await src.open(mode: FileMode.read);
      try {
        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024 + 16);
        
        var leftover = <int>[];
        var bytesRead = 0;

        while ((bytesRead = await srcRaf.readInto(buffer)) > 0) {
          int offset = 0;
          int outOffset = 0;
          
          if (leftover.isNotEmpty) {
            final needed = 16 - leftover.length;
            if (bytesRead < needed) {
              leftover.addAll(buffer.sublist(0, bytesRead));
              continue;
            } else {
              final temp = Uint8List(16);
              temp.setRange(0, leftover.length, leftover);
              temp.setRange(leftover.length, 16, buffer.sublist(0, needed));
              cipher.processBlock(temp, 0, outBuffer, outOffset);
              outOffset += 16;
              offset = needed;
              leftover.clear();
            }
          }

          while (offset + 16 <= bytesRead) {
            cipher.processBlock(buffer, offset, outBuffer, outOffset);
            outOffset += 16;
            offset += 16;
          }

          if (outOffset > 0) {
            await raf.writeFrom(outBuffer, 0, outOffset);
          }

          if (offset < bytesRead) {
            leftover.addAll(buffer.sublist(offset, bytesRead));
          }
        }

        final padLength = 16 - leftover.length;
        final finalBlock = Uint8List(16);
        if (leftover.isNotEmpty) {
          finalBlock.setRange(0, leftover.length, leftover);
        }
        for (int i = leftover.length; i < 16; i++) {
          finalBlock[i] = padLength;
        }
        final outBlock = Uint8List(16);
        cipher.processBlock(finalBlock, 0, outBlock, 0);
        await raf.writeFrom(outBlock);
      } finally {
        await srcRaf.close();
      }
    } finally {
      await raf.flush();
      await raf.close();
    }
  }

  Future<void> decryptStream(File src, File dest) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    final srcRaf = await src.open(mode: FileMode.read);
    try {
      final iv = Uint8List(_ivLength);
      final ivRead = await srcRaf.readInto(iv);
      if (ivRead < _ivLength) {
        throw Exception('Invalid ciphertext: missing IV');
      }

      final raf = await dest.open(mode: FileMode.write);
      try {
        final cipher = CBCBlockCipher(AESEngine());
        cipher.init(false, ParametersWithIV(KeyParameter(_derivedKey!), iv));

        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024 + 16);
        var bytesRead = 0;
        
        var leftoverCipher = <int>[];
        Uint8List? heldPlaintextBlock;

        while ((bytesRead = await srcRaf.readInto(buffer)) > 0) {
          int offset = 0;
          int outOffset = 0;
          
          if (leftoverCipher.isNotEmpty) {
            final needed = 16 - leftoverCipher.length;
            if (bytesRead < needed) {
              leftoverCipher.addAll(buffer.sublist(0, bytesRead));
              continue;
            } else {
              final temp = Uint8List(16);
              temp.setRange(0, leftoverCipher.length, leftoverCipher);
              temp.setRange(leftoverCipher.length, 16, buffer.sublist(0, needed));
              
              final tempOut = Uint8List(16);
              cipher.processBlock(temp, 0, tempOut, 0);
              
              if (heldPlaintextBlock != null) {
                outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
                outOffset += 16;
              }
              heldPlaintextBlock = tempOut;
              
              offset = needed;
              leftoverCipher.clear();
            }
          }

          while (offset + 16 <= bytesRead) {
            final tempOut = Uint8List(16);
            cipher.processBlock(buffer, offset, tempOut, 0);
            
            if (heldPlaintextBlock != null) {
              outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
              outOffset += 16;
            }
            heldPlaintextBlock = tempOut;
            offset += 16;
          }

          if (outOffset > 0) {
            await raf.writeFrom(outBuffer, 0, outOffset);
          }

          if (offset < bytesRead) {
            leftoverCipher.addAll(buffer.sublist(offset, bytesRead));
          }
        }

        if (leftoverCipher.isNotEmpty) {
          throw Exception('Invalid ciphertext: not a multiple of block size');
        }

        if (heldPlaintextBlock != null) {
          final padLength = heldPlaintextBlock[15];
          if (padLength > 0 && padLength <= 16) {
            await raf.writeFrom(heldPlaintextBlock.sublist(0, 16 - padLength));
          } else {
            throw Exception('Invalid PKCS7 padding');
          }
        }
      } finally {
        await raf.flush();
        await raf.close();
      }
    } finally {
      await srcRaf.close();
    }
  }

  Future<void> encryptStreamSystem(File src, File dest) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    final iv = _generateSecureRandomBytes(_ivLength);
    final raf = await dest.open(mode: FileMode.write);
    try {
      await raf.writeFrom(_mediaMagic);
      await raf.writeFrom(iv);

      final cipher = CBCBlockCipher(AESEngine());
      cipher.init(true, ParametersWithIV(KeyParameter(_derivedKey!), iv));

      final srcRaf = await src.open(mode: FileMode.read);
      try {
        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024 + 16);
        
        var leftover = <int>[];
        var bytesRead = 0;

        while ((bytesRead = await srcRaf.readInto(buffer)) > 0) {
          int offset = 0;
          int outOffset = 0;
          
          if (leftover.isNotEmpty) {
            final needed = 16 - leftover.length;
            if (bytesRead < needed) {
              leftover.addAll(buffer.sublist(0, bytesRead));
              continue;
            } else {
              final temp = Uint8List(16);
              temp.setRange(0, leftover.length, leftover);
              temp.setRange(leftover.length, 16, buffer.sublist(0, needed));
              cipher.processBlock(temp, 0, outBuffer, outOffset);
              outOffset += 16;
              offset = needed;
              leftover.clear();
            }
          }

          while (offset + 16 <= bytesRead) {
            cipher.processBlock(buffer, offset, outBuffer, outOffset);
            outOffset += 16;
            offset += 16;
          }

          if (outOffset > 0) {
            await raf.writeFrom(outBuffer, 0, outOffset);
          }

          if (offset < bytesRead) {
            leftover.addAll(buffer.sublist(offset, bytesRead));
          }
        }

        final padLength = 16 - leftover.length;
        final finalBlock = Uint8List(16);
        if (leftover.isNotEmpty) {
          finalBlock.setRange(0, leftover.length, leftover);
        }
        for (int i = leftover.length; i < 16; i++) {
          finalBlock[i] = padLength;
        }
        final outBlock = Uint8List(16);
        cipher.processBlock(finalBlock, 0, outBlock, 0);
        await raf.writeFrom(outBlock);
      } finally {
        await srcRaf.close();
      }
    } finally {
      await raf.flush();
      await raf.close();
    }
  }

  Future<void> decryptStreamSystem(File src, File dest) async {
    int magicType = 0; // 0 = legacy, 1 = v1 (CBC), 2 = c1 (CTR)
    final raf = await src.open(mode: FileMode.read);
    try {
      final magicBuffer = Uint8List(_mediaMagic.length);
      final magicRead = await raf.readInto(magicBuffer);
      
      if (magicRead == _mediaMagic.length) {
        bool isV1 = true;
        bool isC1 = true;
        for (int i = 0; i < _mediaMagic.length; i++) {
          if (magicBuffer[i] != _mediaMagic[i]) isV1 = false;
          if (magicBuffer[i] != _mediaMagicCtr[i]) isC1 = false;
        }
        if (isV1) magicType = 1;
        else if (isC1) magicType = 2;
      }

      if (magicType == 1) {
        if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
        
        final iv = Uint8List(_ivLength);
        final ivRead = await raf.readInto(iv);
        if (ivRead < _ivLength) {
          throw Exception('Invalid ciphertext: missing IV');
        }

        final destRaf = await dest.open(mode: FileMode.write);
        try {
          final cipher = CBCBlockCipher(AESEngine());
          cipher.init(false, ParametersWithIV(KeyParameter(_derivedKey!), iv));

          final buffer = Uint8List(64 * 1024);
          final outBuffer = Uint8List(64 * 1024 + 16);
          var bytesRead = 0;
          
          var leftoverCipher = <int>[];
          Uint8List? heldPlaintextBlock;

          while ((bytesRead = await raf.readInto(buffer)) > 0) {
            int offset = 0;
            int outOffset = 0;
            
            if (leftoverCipher.isNotEmpty) {
              final needed = 16 - leftoverCipher.length;
              if (bytesRead < needed) {
                leftoverCipher.addAll(buffer.sublist(0, bytesRead));
                continue;
              } else {
                final temp = Uint8List(16);
                temp.setRange(0, leftoverCipher.length, leftoverCipher);
                temp.setRange(leftoverCipher.length, 16, buffer.sublist(0, needed));
                
                final tempOut = Uint8List(16);
                cipher.processBlock(temp, 0, tempOut, 0);
                
                if (heldPlaintextBlock != null) {
                  outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
                  outOffset += 16;
                }
                heldPlaintextBlock = tempOut;
                
                offset = needed;
                leftoverCipher.clear();
              }
            }

            while (offset + 16 <= bytesRead) {
              final tempOut = Uint8List(16);
              cipher.processBlock(buffer, offset, tempOut, 0);
              
              if (heldPlaintextBlock != null) {
                outBuffer.setRange(outOffset, outOffset + 16, heldPlaintextBlock);
                outOffset += 16;
              }
              heldPlaintextBlock = tempOut;
              offset += 16;
            }

            if (outOffset > 0) {
              await destRaf.writeFrom(outBuffer, 0, outOffset);
            }

            if (offset < bytesRead) {
              leftoverCipher.addAll(buffer.sublist(offset, bytesRead));
            }
          }

          if (leftoverCipher.isNotEmpty) {
            throw Exception('Invalid ciphertext: not a multiple of block size');
          }

          if (heldPlaintextBlock != null) {
            final padLength = heldPlaintextBlock[15];
            if (padLength > 0 && padLength <= 16) {
              await destRaf.writeFrom(heldPlaintextBlock.sublist(0, 16 - padLength));
            } else {
              throw Exception('Invalid PKCS7 padding');
            }
          }
        } finally {
          await destRaf.flush();
          await destRaf.close();
        }
      } else if (magicType == 2) {
        final systemKey = await _getSystemKey();
        final iv = Uint8List(16);
        final ivRead = await raf.readInto(iv);
        if (ivRead < 16) throw Exception('Invalid ciphertext: missing IV');

        final destRaf = await dest.open(mode: FileMode.write);
        try {
          final aes = AESEngine()..init(true, KeyParameter(systemKey));
          final counter = Uint8List.fromList(iv);
          final ksBlock = Uint8List(16);

          final buffer = Uint8List(64 * 1024);
          final outBuffer = Uint8List(64 * 1024);
          var bytesRead = 0;

          while ((bytesRead = await raf.readInto(buffer)) > 0) {
            int offset = 0;
            while (offset + 16 <= bytesRead) {
              aes.processBlock(counter, 0, ksBlock, 0);
              for (int i = 0; i < 16; i++) {
                outBuffer[offset + i] = buffer[offset + i] ^ ksBlock[i];
              }
              _ctrIncrement(counter);
              offset += 16;
            }
            if (offset < bytesRead) {
              aes.processBlock(counter, 0, ksBlock, 0);
              final remaining = bytesRead - offset;
              for (int i = 0; i < remaining; i++) {
                outBuffer[offset + i] = buffer[offset + i] ^ ksBlock[i];
              }
              _ctrIncrement(counter);
            }
            await destRaf.writeFrom(outBuffer, 0, bytesRead);
          }
        } finally {
          await destRaf.flush();
          await destRaf.close();
        }
      }
    } finally {
      await raf.close();
    }

    if (magicType == 0) {
      final allBytes = await src.readAsBytes();
      final decrypted = await _decryptLegacySystem(allBytes);
      await dest.writeAsBytes(decrypted, flush: true);
    }
  }

  Future<Uint8List> decryptSystem(Uint8List ciphertext) async {
    if (ciphertext.isEmpty) return Uint8List(0);
    int magicType = 0;
    if (ciphertext.length >= _mediaMagic.length) {
      bool isV1 = true;
      bool isC1 = true;
      for (int i = 0; i < _mediaMagic.length; i++) {
        if (ciphertext[i] != _mediaMagic[i]) isV1 = false;
        if (ciphertext[i] != _mediaMagicCtr[i]) isC1 = false;
      }
      if (isV1) magicType = 1;
      else if (isC1) magicType = 2;
    }

    if (magicType == 1) {
      final actualCiphertext = ciphertext.sublist(_mediaMagic.length);
      return decrypt(actualCiphertext);
    } else if (magicType == 2) {
      final actualCiphertext = ciphertext.sublist(_mediaMagic.length);
      if (actualCiphertext.length < 16) throw Exception('Invalid ciphertext: missing IV');
      final iv = actualCiphertext.sublist(0, 16);
      final encrypted = actualCiphertext.sublist(16);
      
      final systemKey = await _getSystemKey();
      final aes = AESEngine()..init(true, KeyParameter(systemKey));
      final counter = Uint8List.fromList(iv);
      final ksBlock = Uint8List(16);
      
      final outBuffer = Uint8List(encrypted.length);
      int offset = 0;
      while (offset + 16 <= encrypted.length) {
        aes.processBlock(counter, 0, ksBlock, 0);
        for (int i = 0; i < 16; i++) {
          outBuffer[offset + i] = encrypted[offset + i] ^ ksBlock[i];
        }
        _ctrIncrement(counter);
        offset += 16;
      }
      if (offset < encrypted.length) {
        aes.processBlock(counter, 0, ksBlock, 0);
        final remaining = encrypted.length - offset;
        for (int i = 0; i < remaining; i++) {
          outBuffer[offset + i] = encrypted[offset + i] ^ ksBlock[i];
        }
      }
      return outBuffer;
    } else {
      return _decryptLegacySystem(ciphertext);
    }
  }

  Future<Uint8List> _decryptLegacySystem(Uint8List ciphertext) async {
    if (ciphertext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    if (ciphertext.length < _ivLength) throw Exception('Invalid ciphertext');
    final iv = ciphertext.sublist(0, _ivLength);
    final encrypted = ciphertext.sublist(_ivLength);
    final cipher = _createCipher(key, iv, false);
    return cipher.process(encrypted);
  }

  /// Strong PIN verifier: SHA-256 of the PBKDF2-derived master key, tagged "v2:".
  /// Reproducing it costs the full PBKDF2 work and it never reveals the key.
  String _verifierForKey(Uint8List key) {
    final digest = SHA256Digest().process(key);
    return 'v2:${base64Encode(digest)}';
  }

  bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var result = 0;
    for (var i = 0; i < ab.length; i++) {
      result |= ab[i] ^ bb[i];
    }
    return result == 0;
  }

  /// Derive the PIN-based wrapping key (KEK) from the PIN-derived key. Domain-
  /// separated from the verifier so vault_pin_hash never reveals the KEK.
  Uint8List _deriveKek(Uint8List candidateKey) {
    final input = Uint8List.fromList([
      ...candidateKey,
      ...utf8.encode('mimic-kek-v1'),
    ]);
    return SHA256Digest().process(input);
  }

  String _wrapKey(Uint8List dek, Uint8List kek) {
    final iv = _generateSecureRandomBytes(_ivLength);
    final cipher = _createCipher(kek, iv, true);
    final enc = cipher.process(dek);
    final blob = Uint8List(iv.length + enc.length);
    blob.setRange(0, iv.length, iv);
    blob.setRange(iv.length, blob.length, enc);
    return base64Encode(blob);
  }

  Uint8List _unwrapKey(String wrapped, Uint8List kek) {
    final blob = base64Decode(wrapped);
    if (blob.length < _ivLength) {
      throw Exception('Invalid wrapped master key');
    }
    final iv = blob.sublist(0, _ivLength);
    final enc = blob.sublist(_ivLength);
    final cipher = _createCipher(kek, iv, false);
    return cipher.process(enc);
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
    // Delegates to the production KDF helper.
    return deriveVaultPinKek(pin, saltBase64);
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

  static void _ctrIncrement(Uint8List counter) {
    for (int i = 15; i >= 0; i--) {
      counter[i] = (counter[i] + 1) & 0xFF;
      if (counter[i] != 0) break;
    }
  }

  static Uint8List _ctrCounterAt(Uint8List iv, int blockIndex) {
    final counter = Uint8List.fromList(iv);
    int carry = blockIndex;
    for (int i = 15; i >= 0 && carry > 0; i--) {
      final sum = counter[i] + carry;
      counter[i] = sum & 0xFF;
      carry = sum >> 8;
    }
    return counter;
  }

  Future<void> encryptStreamSystemCtr(File src, File dest) async {
    final systemKey = await _getSystemKey();
    final iv = _generateSecureRandomBytes(16);
    final raf = await dest.open(mode: FileMode.write);
    try {
      await raf.writeFrom(_mediaMagicCtr);
      await raf.writeFrom(iv);

      final aes = AESEngine()..init(true, KeyParameter(systemKey));
      final counter = Uint8List.fromList(iv);
      final ksBlock = Uint8List(16);

      final srcRaf = await src.open(mode: FileMode.read);
      try {
        final buffer = Uint8List(64 * 1024);
        final outBuffer = Uint8List(64 * 1024);
        var bytesRead = 0;

        while ((bytesRead = await srcRaf.readInto(buffer)) > 0) {
          int offset = 0;
          while (offset + 16 <= bytesRead) {
            aes.processBlock(counter, 0, ksBlock, 0);
            for (int i = 0; i < 16; i++) {
              outBuffer[offset + i] = buffer[offset + i] ^ ksBlock[i];
            }
            _ctrIncrement(counter);
            offset += 16;
          }
          if (offset < bytesRead) {
            aes.processBlock(counter, 0, ksBlock, 0);
            final remaining = bytesRead - offset;
            for (int i = 0; i < remaining; i++) {
              outBuffer[offset + i] = buffer[offset + i] ^ ksBlock[i];
            }
            _ctrIncrement(counter);
          }
          await raf.writeFrom(outBuffer, 0, bytesRead);
        }
      } finally {
        await srcRaf.close();
      }
    } finally {
      await raf.flush();
      await raf.close();
    }
  }

  Future<Uint8List> decryptRangeSystem(File src, int offset, int length) async {
    int magicType = 0;
    final raf = await src.open(mode: FileMode.read);
    try {
      final magicBuffer = Uint8List(8);
      final magicRead = await raf.readInto(magicBuffer);
      if (magicRead == 8) {
        bool isV1 = true;
        bool isC1 = true;
        for (int i = 0; i < 8; i++) {
          if (magicBuffer[i] != _mediaMagic[i]) isV1 = false;
          if (magicBuffer[i] != _mediaMagicCtr[i]) isC1 = false;
        }
        if (isV1) magicType = 1;
        else if (isC1) magicType = 2;
      }

      if (magicType == 2) {
        final fileLength = await src.length();
        final maxReadable = fileLength - 24;
        if (offset >= maxReadable || offset < 0) return Uint8List(0);
        
        int actualLength = length;
        if (offset + length > maxReadable) {
          actualLength = maxReadable - offset;
        }
        if (actualLength <= 0) return Uint8List(0);

        final systemKey = await _getSystemKey();
        final iv = Uint8List(16);
        final ivRead = await raf.readInto(iv);
        if (ivRead < 16) throw Exception('Invalid ciphertext: missing IV');

        final blockIndex = offset ~/ 16;
        final blockOffset = offset % 16;

        final counter = Uint8List.fromList(iv);
        int carry = blockIndex;
        for (int i = 15; i >= 0 && carry > 0; i--) {
          final sum = counter[i] + carry;
          counter[i] = sum & 0xFF;
          carry = sum >> 8;
        }

        final aes = AESEngine()..init(true, KeyParameter(systemKey));
        final rangeCounter = _ctrCounterAt(iv, blockIndex);
        final ksBlock = Uint8List(16);

        await raf.setPosition(24 + offset);
        final ciphertext = Uint8List(actualLength);
        await raf.readInto(ciphertext);

        final outBuffer = Uint8List(actualLength);
        
        int outPos = 0;
        int inPos = 0;
        
        if (blockOffset > 0) {
          aes.processBlock(rangeCounter, 0, ksBlock, 0);
          _ctrIncrement(rangeCounter);
          
          final availableInThisBlock = 16 - blockOffset;
          final toProcess = (actualLength < availableInThisBlock) ? actualLength : availableInThisBlock;
          
          for (int i = 0; i < toProcess; i++) {
            outBuffer[outPos++] = ciphertext[inPos++] ^ ksBlock[blockOffset + i];
          }
        }
        
        while (inPos + 16 <= actualLength) {
          aes.processBlock(rangeCounter, 0, ksBlock, 0);
          for (int i = 0; i < 16; i++) {
            outBuffer[outPos + i] = ciphertext[inPos + i] ^ ksBlock[i];
          }
          _ctrIncrement(rangeCounter);
          inPos += 16;
          outPos += 16;
        }
        
        if (inPos < actualLength) {
          aes.processBlock(rangeCounter, 0, ksBlock, 0);
          final remaining = actualLength - inPos;
          for (int i = 0; i < remaining; i++) {
            outBuffer[outPos + i] = ciphertext[inPos + i] ^ ksBlock[i];
          }
        }
        
        return outBuffer;
      }
    } finally {
      await raf.close();
    }

    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/temp_decrypt_${DateTime.now().millisecondsSinceEpoch}');
    try {
      await decryptStreamSystem(src, tempFile);
      if (!await tempFile.exists()) return Uint8List(0);
      final readRaf = await tempFile.open(mode: FileMode.read);
      try {
        final fileLen = await tempFile.length();
        if (offset >= fileLen) return Uint8List(0);
        
        int actualLength = length;
        if (offset + length > fileLen) {
          actualLength = fileLen - offset;
        }
        
        await readRaf.setPosition(offset);
        final buffer = Uint8List(actualLength);
        await readRaf.readInto(buffer);
        return buffer;
      } finally {
        await readRaf.close();
      }
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}


final vaultCryptoProvider = ChangeNotifierProvider<VaultCrypto>((ref) {
  return VaultCrypto(ref.read(platformServiceProvider));
});
