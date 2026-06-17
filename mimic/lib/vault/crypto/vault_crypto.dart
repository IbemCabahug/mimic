// lib/vault/crypto/vault_crypto.dart
// WEB NOTE: web storage is not secure. For testing only. Android uses full encryption.

import 'dart:io';
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
  static const List<int> _mediaMagic = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x76, 0x31, 0x00]; // "MVKEYv1\0"
  static const List<int> _mediaMagicCtr = [0x4D, 0x56, 0x4B, 0x45, 0x59, 0x63, 0x31, 0x00]; // "MVKEYc1\0"

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
        await _platformService.secureWrite('vault_setup_completed', 'true');
        await _platformService.secureDelete('vault_wiped');
        notifyListeners();
        return;
      } else {
        throw Exception('Invalid PIN');
      }
    }

    salt = _generateSecureRandomBytes(16);
    await _platformService.secureWrite(_storageKeySalt, base64Encode(salt));
    await _platformService.secureWrite(_storageKeyPinHash, _hashPin(pin));
    await _platformService.secureWrite('vault_setup_completed', 'true');
    await _platformService.secureDelete('vault_wiped');
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
      await _platformService.secureWrite('vault_setup_completed', 'true');
      await _platformService.secureDelete('vault_wiped');
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
