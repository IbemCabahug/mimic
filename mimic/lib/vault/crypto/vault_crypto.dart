// lib/vault/crypto/vault_crypto.dart
// WEB NOTE: web storage is not secure. For testing only. Android uses full encryption.

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'vault_kdf.dart';

import '../../core/services/platform_service.dart';
import 'recovery_phrase.dart';
import 'keystore_service.dart';
import 'media_format.dart';
import 'vault_exceptions.dart';
import 'crypto_isolate.dart';

export 'vault_exceptions.dart';

class InvalidPinException implements Exception {
  final String message;
  const InvalidPinException([this.message = 'Invalid PIN']);

  @override
  String toString() => 'InvalidPinException: $message';
}

class SystemKeyMissingException implements Exception {
  final String message;
  SystemKeyMissingException([this.message =
    'System key is missing but the vault was already provisioned. Refusing to regenerate to avoid orphaning encrypted data.']);
  @override
  String toString() => 'SystemKeyMissingException: $message';
}

class VaultSwapRecoveryException implements Exception {
  final String message;
  VaultSwapRecoveryException([this.message =
    'Interrupted vault swap detected with incomplete backup data; cannot safely recover.']);
  @override
  String toString() => 'VaultSwapRecoveryException: $message';
}

class VaultCrypto extends ChangeNotifier {
  static const int _ivLength = 16;
  static const int _keyLength = 32;
  static const List<int> _mediaMagic = kMediaMagicV1;
  static const List<int> _mediaMagicCtr = kMediaMagicCtrV1;
  static const List<int> _mediaMagicCtrV2 = kMediaMagicCtrV2;

  static VaultCrypto? _instance;
  static VaultCrypto get instance {
    if (_instance == null) {
      throw StateError('VaultCrypto has not been initialized yet.');
    }
    return _instance!;
  }

  final PlatformService _platformService;
  final KeystoreService _keystoreService;
  Uint8List? _derivedKey;
  Uint8List? _temporaryKek;
  List<String>? _recoveryWords;
  bool _isUnlocked = false;
  bool _needsHardwareMigration = false;
  bool _hasRecoveryPhrase = false;
  int _lockEpoch = 0;

  static final Map<String, String> _webKeyStore = {};

  Future<void> _mutex = Future<void>.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _mutex;
    final completer = Completer<void>();
    _mutex = completer.future;

    return previous.catchError((_) {}).then((_) {
      return action();
    }).whenComplete(() {
      completer.complete();
    });
  }

  VaultCrypto(this._platformService, [KeystoreService? keystoreService]) 
      : _keystoreService = keystoreService ?? AndroidKeystoreService() {
    _instance = this;
  }

  bool get isUnlocked => _isUnlocked;
  bool get needsHardwareMigration => _needsHardwareMigration;
  bool get hasRecoveryPhrase => _hasRecoveryPhrase;

  /// Verifies a candidate PIN against the stored verifier.
  ///
  /// This method is read-only, does not unlock the vault, does not alter internal
  /// crypto state or keys in memory, does not write any storage keys, and does
  /// not count toward lockout attempts. Returns true if the PIN matches the
  /// stored verifier, or false otherwise (including when the vault is uninitialized
  /// or keys are missing/empty).
  Future<bool> verifyPin(String pin) async {
    try {
      if (kIsWeb) {
        final salt = _webKeyStore[_storageKeySalt];
        final storedHash = _webKeyStore[_storageKeyPinHash];
        if (salt == null || salt.isEmpty || storedHash == null || storedHash.isEmpty) {
          return false;
        }
        final parsed = parseVerifier(storedHash);
        final candidateKey = await _deriveKey(pin, salt, parsed.iterations);
        final digest = SHA256Digest().process(candidateKey);
        final expectedVerifier = parsed.version == 3
            ? 'v3:${parsed.iterations}:${base64Encode(digest)}'
            : 'v2:${base64Encode(digest)}';
        return _constantTimeEquals(storedHash, expectedVerifier);
      }

      final storedSalt = await _platformService.secureRead(_storageKeySalt);
      if (storedSalt == null || storedSalt.isEmpty) {
        return false;
      }
      final storedHash = await _platformService.secureRead(_storageKeyPinHash);
      if (storedHash == null || storedHash.isEmpty) {
        return false;
      }

      final parsed = parseVerifier(storedHash);
      final candidateKey = await _deriveKey(pin, storedSalt, parsed.iterations);
      final digest = SHA256Digest().process(candidateKey);
      final expectedVerifier = parsed.version == 3
          ? 'v3:${parsed.iterations}:${base64Encode(digest)}'
          : 'v2:${base64Encode(digest)}';
      return _constantTimeEquals(storedHash, expectedVerifier);
    } catch (_) {
      return false;
    }
  }

  Future<void> initialize(String pin) {
    final epoch = _lockEpoch;
    return _synchronized(() => _initializeInternal(pin, epoch));
  }

  Future<void> _initializeInternal(String pin, int capturedEpoch) async {
    if (kIsWeb) {
      _webKeyStore[_storageKeySalt] = _generateRandomSalt();
      final key = await _deriveKey(pin, _webKeyStore[_storageKeySalt]!);
      _webKeyStore[_storageKeyPinHash] = _verifierForKey(key);
      if (_lockEpoch == capturedEpoch) {
        _derivedKey = key;
        _isUnlocked = true;
        notifyListeners();
      } else {
        key.fillRange(0, key.length, 0);
      }
      return;
    }

    await _recoverSwapIfNeeded();

    final storedSalt = await _platformService.secureRead(_storageKeySalt);
    if (storedSalt != null) {
      final salt = base64Decode(storedSalt);
      final storedHash = await _platformService.secureRead(_storageKeyPinHash);
      if (storedHash == null) {
        throw SystemKeyMissingException('vault_pin_hash missing');
      }
      final parsed = parseVerifier(storedHash);

      final candidateKey = await _deriveKey(pin, storedSalt, parsed.iterations);
      final digest = SHA256Digest().process(candidateKey);
      final expectedVerifier = parsed.version == 3
          ? 'v3:${parsed.iterations}:${base64Encode(digest)}'
          : 'v2:${base64Encode(digest)}';
      final ok = _constantTimeEquals(storedHash, expectedVerifier);
      if (!ok) {
        throw const InvalidPinException();
      }
      final kek = _deriveKek(candidateKey);
      final wrapped =
          await _platformService.secureRead(_storageKeyMasterWrapped);
      Uint8List dek;
      bool needsHwMigration = false;
      if (wrapped == null) {
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
      if (_lockEpoch == capturedEpoch) {
        _derivedKey = dek;
        _isUnlocked = true;
        _needsHardwareMigration = needsHwMigration;
        if (needsHwMigration) {
          _temporaryKek = kek;
        }
        notifyListeners();
      } else {
        dek.fillRange(0, dek.length, 0);
        kek.fillRange(0, kek.length, 0);
      }
      await _platformService.secureWrite('vault_setup_completed', 'true');
      await _platformService.secureDelete('vault_wiped');
      
      final blob = await _platformService.secureRead('recovery_blob');
      if (_lockEpoch == capturedEpoch) {
        _hasRecoveryPhrase = blob != null;
      }
    } else {
      final freshSalt = _generateSecureRandomBytes(16);
      final freshSaltBase64 = base64Encode(freshSalt);
      final candidateKey = await _deriveKey(pin, freshSaltBase64);
      final kek = _deriveKek(candidateKey);

      final innerWrapped = _wrapKey(candidateKey, kek);
      await _keystoreService.ensureKey();
      final hwWrapped = await _keystoreService.wrap(innerWrapped);

      await _platformService.secureDelete(_storageKeyMasterWrapped);
      await _platformService.secureDelete('recovery_blob');
      await _platformService.secureDelete('recovery_salt');
      await _platformService.secureDelete('wrong_attempts');
      await _platformService.secureDelete('lockout_set_wall');
      await _platformService.secureDelete('lockout_set_elapsed');
      await _platformService.secureDelete('lockout_duration_ms');

      await _platformService.secureWrite(
          _storageKeyPinHash, _verifierForKey(candidateKey));
      await _platformService.secureWrite(
          _storageKeyMasterWrapped, 'hw1:$hwWrapped');
      await _platformService.secureWrite(_storageKeySalt, freshSaltBase64);

      if (_lockEpoch == capturedEpoch) {
        _derivedKey = candidateKey;
        _isUnlocked = true;
        _needsHardwareMigration = false;
        _hasRecoveryPhrase = false;
        notifyListeners();
      } else {
        candidateKey.fillRange(0, candidateKey.length, 0);
        kek.fillRange(0, kek.length, 0);
      }
    }
  }

  static const String _storageKeyMasterWrapped = 'master_key_wrapped';
  static const String _storageKeyPinHash = 'vault_pin_hash';
  static const String _storageKeySalt = 'vault_salt';

  static const String _tmpSalt = '_tmp_vault_salt';
  static const String _tmpPinHash = '_tmp_vault_pin_hash';
  static const String _tmpMasterWrapped = '_tmp_master_key_wrapped';
  static const String _bakSalt = '_bak_vault_salt';
  static const String _bakPinHash = '_bak_vault_pin_hash';
  static const String _bakMasterWrapped = '_bak_master_key_wrapped';
  static const String _swapMarker = '_swap_in_progress';

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
    _lockEpoch++;
    final keyToZero = _derivedKey;
    final kekToZero = _temporaryKek;
    _derivedKey = null;
    _temporaryKek = null;

    _synchronized(() async {
      _lockInternal(keyToZero, kekToZero);
    }).catchError((e, st) {
      debugPrint('Error during vault lock zeroing: $e\n$st');
    });
  }

  /// Clears in-memory keys and marks the vault as locked.
  ///
  /// CRITICAL / LOAD-BEARING:
  /// In addition to zeroing [keyToZero] and [kekToZero] (the instances captured at the
  /// moment [lock] was synchronously invoked), the block below inspecting [_derivedKey]
  /// and [_temporaryKek] MUST NOT BE REMOVED.
  ///
  /// With request-time lock epoch capture in place, all ordinary in-flight operations
  /// detect intervening locks at commit time and abort their own key assignments.
  /// This block serves as a last-resort safety net (defense-in-depth) with no remaining
  /// ordinary execution path that reaches it; it catches and zero-fills key material from
  /// any future guarded operations added to the codebase without an epoch check,
  /// guaranteeing that the vault always finishes in a completely locked state with zero plaintext key
  /// material remaining in instance fields.
  void _lockInternal(Uint8List? keyToZero, Uint8List? kekToZero) {
    try {
      if (keyToZero != null) {
        keyToZero.fillRange(0, keyToZero.length, 0);
      }
      if (kekToZero != null) {
        kekToZero.fillRange(0, kekToZero.length, 0);
      }
      if (_derivedKey != null) {
        _derivedKey!.fillRange(0, _derivedKey!.length, 0);
        _derivedKey = null;
      }
      if (_temporaryKek != null) {
        _temporaryKek!.fillRange(0, _temporaryKek!.length, 0);
        _temporaryKek = null;
      }
    } finally {
      _isUnlocked = false;
      notifyListeners();
    }
  }

  void clearKey() {
    lock();
  }

  bool _isStoringRecovery = false;

  Future<void> storeRecoveryBlob([List<String>? recoveryWords]) {
    final epoch = _lockEpoch;
    return _synchronized(() => _storeRecoveryBlobInternal(recoveryWords, epoch));
  }

  Future<void> _storeRecoveryBlobInternal([List<String>? recoveryWords, int? capturedEpoch]) async {
    if (_isStoringRecovery) return;
    _isStoringRecovery = true;
    try {
      final rawKey = _derivedKey;
      if (!_isUnlocked || rawKey == null) {
        throw Exception('Vault is locked; cannot store recovery blob');
      }

      final words = recoveryWords ?? _recoveryWords;
      if (words == null || words.length != 12) {
        throw Exception('Invalid or missing recovery phrase');
      }

      final salt = _generateSecureRandomBytes(16);
      final recoveryKey = await RecoveryPhrase.deriveKeyAsync(words, salt);
      final iv = _generateSecureRandomBytes(_ivLength);
      final cipher = _createCipher(recoveryKey, iv, true);
      final encryptedMasterKey = cipher.process(rawKey);

      final blob = Uint8List(iv.length + encryptedMasterKey.length);
      blob.setRange(0, iv.length, iv);
      blob.setRange(iv.length, blob.length, encryptedMasterKey);

      if (capturedEpoch != null && _lockEpoch != capturedEpoch) {
        return;
      }

      await _platformService.secureWrite('recovery_blob', base64Encode(blob));
      await _platformService.secureWrite('recovery_salt', base64Encode(salt));
      _hasRecoveryPhrase = true;
    } finally {
      _isStoringRecovery = false;
    }
  }

  Future<void> changePin(String newPin) async {
    final rawKey = _derivedKey;
    if (!_isUnlocked || rawKey == null) {
      throw Exception('Vault must be unlocked before changing the PIN');
    }
    final epoch = _lockEpoch;
    final capturedDek = Uint8List.fromList(rawKey);
    return _synchronized(() => _changePinInternal(newPin, capturedDek, epoch));
  }

  Future<void> _changePinInternal(String newPin, Uint8List capturedDek, int capturedEpoch) async {
    final dek = capturedDek;

    await _recoverSwapIfNeeded();

    final salt = _generateSecureRandomBytes(16);
    final saltBase64 = base64Encode(salt);
    final newCandidateKey = await _deriveKey(newPin, saltBase64);
    final hashVerifier = _verifierForKey(newCandidateKey);
    final newKek = _deriveKek(newCandidateKey);
    final innerWrapped = _wrapKey(dek, newKek);

    await _keystoreService.ensureKey();
    final hwWrapped = await _keystoreService.wrap(innerWrapped);
    final wrappedValue = 'hw1:$hwWrapped';

    await _platformService.secureWrite(_tmpSalt, saltBase64);
    await _platformService.secureWrite(_tmpPinHash, hashVerifier);
    await _platformService.secureWrite(_tmpMasterWrapped, wrappedValue);

    final readSalt = await _platformService.secureRead(_tmpSalt);
    final readHash = await _platformService.secureRead(_tmpPinHash);
    final readWrapped = await _platformService.secureRead(_tmpMasterWrapped);

    if (readSalt == null || readHash == null || readWrapped == null) {
      await _cleanupTempKeys();
      throw StateError('Failed to verify staged vault triple');
    }

    if (readSalt != saltBase64 ||
        readHash != hashVerifier ||
        readWrapped != wrappedValue) {
      await _cleanupTempKeys();
      throw StateError('Failed to verify staged vault triple');
    }

    final parsedStaged = parseVerifier(readHash);
    final verifyDigest = SHA256Digest().process(newCandidateKey);
    final expectedStagedVerifier = parsedStaged.version == 3
        ? 'v3:${parsedStaged.iterations}:${base64Encode(verifyDigest)}'
        : 'v2:${base64Encode(verifyDigest)}';
    if (!_constantTimeEquals(readHash, expectedStagedVerifier)) {
      await _cleanupTempKeys();
      throw StateError('Staged verifier mismatch');
    }
    final verifyKek = newKek;
    if (!readWrapped.startsWith('hw1:')) {
      await _cleanupTempKeys();
      throw StateError('Staged wrapped key missing hw1 prefix');
    }
    try {
      final verifyInner = await _keystoreService.unwrap(readWrapped.substring(4));
      if (verifyInner == 'KEY_INVALID') {
        await _cleanupTempKeys();
        throw StateError('Staged wrapped key failed hardware unwrap');
      }
      final verifyDek = _unwrapKey(verifyInner, verifyKek);
      if (!_constantTimeBytesEqual(verifyDek, dek)) {
        await _cleanupTempKeys();
        throw StateError('Staged DEK does not match current DEK');
      }
    } catch (e) {
      await _cleanupTempKeys();
      if (e is StateError) rethrow;
      throw StateError('Staged wrapped key failed verification: $e');
    }

    final canonSalt = await _platformService.secureRead(_storageKeySalt);
    final canonHash = await _platformService.secureRead(_storageKeyPinHash);
    final canonWrapped =
        await _platformService.secureRead(_storageKeyMasterWrapped);
    if (canonSalt != null) {
      await _platformService.secureWrite(_bakSalt, canonSalt);
    }
    if (canonHash != null) {
      await _platformService.secureWrite(_bakPinHash, canonHash);
    }
    if (canonWrapped != null) {
      await _platformService.secureWrite(_bakMasterWrapped, canonWrapped);
    }

    await _platformService.secureWrite(_swapMarker, 'pin:staged');

    await _platformService.secureWrite(_storageKeySalt, saltBase64);
    await _platformService.secureWrite(_storageKeyPinHash, hashVerifier);
    await _platformService.secureWrite(_storageKeyMasterWrapped, wrappedValue);

    await _platformService.secureWrite(_swapMarker, 'pin:swapped');

    await _cleanupSwapArtifacts();

    if (!kIsWeb) {
      await _platformService.secureWrite('vault_pin', newPin);
      await _platformService.secureWrite('wrong_attempts', '0');
      await _platformService.secureWrite('vault_setup_completed', 'true');
      await _platformService.secureDelete('vault_wiped');
    }
    if (_lockEpoch == capturedEpoch) {
      _derivedKey = dek;
      _needsHardwareMigration = false;
      notifyListeners();
    } else {
      dek.fillRange(0, dek.length, 0);
    }
  }

  Future<void> migrateToHardwareBinding() {
    final epoch = _lockEpoch;
    return _synchronized(() => _migrateToHardwareBindingInternal(epoch));
  }

  Future<void> _migrateToHardwareBindingInternal(int capturedEpoch) async {
    final rawDek = _derivedKey;
    final rawKek = _temporaryKek;
    if (!_isUnlocked || rawDek == null || rawKek == null) {
      throw Exception('Vault locked or missing KEK');
    }
    if (!_needsHardwareMigration) return;

    final dek = rawDek;
    final kek = rawKek;

    final innerWrapped = _wrapKey(dek, kek);
    await _keystoreService.ensureKey();
    final hwWrapped = await _keystoreService.wrap(innerWrapped);
    final wrappedValue = 'hw1:$hwWrapped';

    await _platformService.secureWrite(_tmpMasterWrapped, wrappedValue);

    final readWrapped = await _platformService.secureRead(_tmpMasterWrapped);
    if (readWrapped == null) {
      await _cleanupTempKeys();
      throw StateError('Failed to read back staged master key');
    }
    if (!readWrapped.startsWith('hw1:')) {
      await _cleanupTempKeys();
      throw StateError('Staged wrapped key missing hw1 prefix');
    }

    try {
      final verifyInner = await _keystoreService.unwrap(readWrapped.substring(4));
      if (verifyInner == 'KEY_INVALID') {
        await _cleanupTempKeys();
        throw StateError('Staged wrapped key failed hardware unwrap');
      }
      final verifyDek = _unwrapKey(verifyInner, kek);
      if (!_constantTimeBytesEqual(verifyDek, dek)) {
        await _cleanupTempKeys();
        throw StateError('Staged DEK does not match current DEK');
      }
    } catch (e) {
      await _cleanupTempKeys();
      if (e is StateError) rethrow;
      throw StateError('Staged wrapped key failed verification: $e');
    }

    final canonWrapped =
        await _platformService.secureRead(_storageKeyMasterWrapped);
    if (canonWrapped != null) {
      await _platformService.secureWrite(_bakMasterWrapped, canonWrapped);
    }
    await _platformService.secureWrite(_swapMarker, 'hw:staged');
    await _platformService.secureWrite(_storageKeyMasterWrapped, wrappedValue);
    await _platformService.secureWrite(_swapMarker, 'hw:swapped');
    await _cleanupSwapArtifacts();

    _needsHardwareMigration = false;
    kek.fillRange(0, kek.length, 0);
    _temporaryKek = null;
    if (_lockEpoch == capturedEpoch) {
      notifyListeners();
    }
  }

  Future<bool> recoverWithPhrase(List<String> recoveryWords) {
    final epoch = _lockEpoch;
    return _synchronized(() => _recoverWithPhraseInternal(recoveryWords, epoch));
  }

  Future<bool> _recoverWithPhraseInternal(List<String> recoveryWords, int capturedEpoch) async {
    final storedBlob = await _platformService.secureRead('recovery_blob');
    final storedSalt = await _platformService.secureRead('recovery_salt');
    if (storedBlob == null || storedSalt == null) {
      return false;
    }

    try {
      final salt = base64Decode(storedSalt);
      final blob = base64Decode(storedBlob);

      final recoveryKey = await RecoveryPhrase.deriveKeyAsync(recoveryWords, salt);

      if (blob.length < _ivLength) return false;
      final iv = blob.sublist(0, _ivLength);
      final encryptedMasterKey = blob.sublist(_ivLength);

      final cipher = _createCipher(recoveryKey, iv, false);
      final masterKey = cipher.process(encryptedMasterKey);

      if (masterKey.length != _keyLength) return false;

      if (_lockEpoch == capturedEpoch) {
        _derivedKey = masterKey;
        _isUnlocked = true;
        _recoveryWords = recoveryWords;
        notifyListeners();
        return true;
      } else {
        masterKey.fillRange(0, masterKey.length, 0);
        return false;
      }
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

  /// Returns the device-local system key stored in secure storage under 'system_key'.
  /// Used ONLY for legacy blobs and reading legacy c1 CTR media. It is NOT backed up in
  /// exports and cannot be restored from the recovery phrase; data encrypted with it is lost on reinstall.
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
    await cryptoIsolateEncryptFile(
      key: Uint8List.fromList(_derivedKey!),
      iv: iv,
      srcPath: src.path,
      destPath: dest.path,
    );
  }

  Future<void> decryptStreamSystem(File src, File dest) async {
    int magicType = 0; // 0 = legacy, 1 = v1 (CBC), 2 = c1 (CTR, system key), 3 = c2 (CTR, master key)
    final raf = await src.open(mode: FileMode.read);
    try {
      final magicBuffer = Uint8List(_mediaMagic.length);
      final magicRead = await raf.readInto(magicBuffer);
      
      if (magicRead == _mediaMagic.length) {
        bool isV1 = true;
        bool isC1 = true;
        bool isC2 = true;
        for (int i = 0; i < _mediaMagic.length; i++) {
          if (magicBuffer[i] != _mediaMagic[i]) isV1 = false;
          if (magicBuffer[i] != _mediaMagicCtr[i]) isC1 = false;
          if (magicBuffer[i] != _mediaMagicCtrV2[i]) isC2 = false;
        }
        if (isV1) magicType = 1;
        else if (isC1) magicType = 2;
        else if (isC2) magicType = 3;
      }

      if (magicType == 1) {
        if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
        
        final iv = Uint8List(_ivLength);
        final ivRead = await raf.readInto(iv);
        if (ivRead < _ivLength) {
          throw const CorruptedMediaFileException();
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
            throw const CorruptedMediaFileException();
          }

          if (heldPlaintextBlock != null) {
            final padLength = heldPlaintextBlock[15];
            if (padLength > 0 && padLength <= 16) {
              await destRaf.writeFrom(heldPlaintextBlock.sublist(0, 16 - padLength));
            } else {
              throw const CorruptedMediaFileException();
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
        if (ivRead < 16) throw const CorruptedMediaFileException();

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
      } else if (magicType == 3) {
        if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
        final iv = Uint8List(16);
        final ivRead = await raf.readInto(iv);
        if (ivRead < 16) throw const CorruptedMediaFileException();

        final destRaf = await dest.open(mode: FileMode.write);
        try {
          final aes = AESEngine()..init(true, KeyParameter(_derivedKey!));
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
      final length = await src.length();
      if (length < 32 || length % 16 != 0) {
        throw const CorruptedMediaFileException();
      }
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
      bool isC2 = true;
      for (int i = 0; i < _mediaMagic.length; i++) {
        if (ciphertext[i] != _mediaMagic[i]) isV1 = false;
        if (ciphertext[i] != _mediaMagicCtr[i]) isC1 = false;
        if (ciphertext[i] != _mediaMagicCtrV2[i]) isC2 = false;
      }
      if (isV1) magicType = 1;
      else if (isC1) magicType = 2;
      else if (isC2) magicType = 3;
    }

    if (magicType == 1) {
      final actualCiphertext = ciphertext.sublist(_mediaMagic.length);
      try {
        return decrypt(actualCiphertext);
      } on ArgumentError {
        throw const CorruptedMediaFileException();
      } on RangeError {
        throw const CorruptedMediaFileException();
      } catch (e) {
        if (e is SystemKeyMissingException || e is StateError) rethrow;
        if (e.toString().contains('Vault is locked')) rethrow;
        throw const CorruptedMediaFileException();
      }
    } else if (magicType == 2) {
      final actualCiphertext = ciphertext.sublist(_mediaMagic.length);
      if (actualCiphertext.length < 16) throw const CorruptedMediaFileException();
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
    } else if (magicType == 3) {
      if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
      final actualCiphertext = ciphertext.sublist(_mediaMagic.length);
      if (actualCiphertext.length < 16) throw const CorruptedMediaFileException();
      final iv = actualCiphertext.sublist(0, 16);
      final encrypted = actualCiphertext.sublist(16);
      
      final aes = AESEngine()..init(true, KeyParameter(_derivedKey!));
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
      if (ciphertext.length < 32 || ciphertext.length % 16 != 0) {
        throw const CorruptedMediaFileException();
      }
      return _decryptLegacySystem(ciphertext);
    }
  }

  Future<Uint8List> _decryptLegacySystem(Uint8List ciphertext) async {
    if (ciphertext.isEmpty) return Uint8List(0);
    final key = await _getSystemKey();
    if (ciphertext.length < _ivLength) throw const CorruptedMediaFileException();
    final iv = ciphertext.sublist(0, _ivLength);
    final encrypted = ciphertext.sublist(_ivLength);
    try {
      final cipher = _createCipher(key, iv, false);
      return cipher.process(encrypted);
    } on ArgumentError {
      throw const CorruptedMediaFileException();
    } on RangeError {
      throw const CorruptedMediaFileException();
    } catch (e) {
      if (e is SystemKeyMissingException || e is StateError) rethrow;
      if (e.toString().contains('Vault is locked')) rethrow;
      throw const CorruptedMediaFileException();
    }
  }

  /// Generates the versioned PIN verifier string ('v3:<iterations>:<base64(SHA256(key))>')
  String _verifierForKey(Uint8List key, [int iterations = kPbkdf2Iterations]) {
    return formatVerifier(key, iterations);
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

  // ---------------------------------------------------------------------------
  // Atomic swap helpers for changePin
  // ---------------------------------------------------------------------------

  /// Recovers from an interrupted atomic swap in [changePin].
  ///
  /// If a crash occurred mid-swap, the canonical triple may be in an
  /// inconsistent state. This method detects the condition via the swap
  /// marker and either completes the cleanup (if canonical already matches the
  /// staged values) or rolls back from the backup.
  Future<void> _recoverSwapIfNeeded() async {
    final marker = await _platformService.secureRead(_swapMarker);
    if (marker == null) {
      // No swap in progress. Clean up any orphaned temp keys.
      await _cleanupTempKeys();
      return;
    }

    // 1. If marker ends in ':swapped', canonical write completed.
    // The new state is authoritative; never restore from backup.
    if (marker.endsWith(':swapped')) {
      await _cleanupSwapArtifacts();
      return;
    }

    // 2. If marker is 'hw:staged', hardware migration was interrupted.
    if (marker == 'hw:staged') {
      final bakWrappedVal =
          await _platformService.secureRead(_bakMasterWrapped);
      if (bakWrappedVal != null) {
        await _platformService.secureWrite(
            _storageKeyMasterWrapped, bakWrappedVal);
        await _cleanupSwapArtifacts();
        return;
      }
      // Incomplete backup: do NOT delete anything.
      throw VaultSwapRecoveryException(
        'Interrupted hardware migration swap detected with incomplete backup data; cannot safely recover.',
      );
    }

    // 3. For 'pin:staged', legacy literal 'true', or any unrecognised marker:
    // treat as staged full PIN swap.
    final bakSaltVal = await _platformService.secureRead(_bakSalt);
    final bakHashVal = await _platformService.secureRead(_bakPinHash);
    final bakWrappedVal =
        await _platformService.secureRead(_bakMasterWrapped);

    if (bakSaltVal != null && bakHashVal != null && bakWrappedVal != null) {
      await _platformService.secureWrite(_storageKeySalt, bakSaltVal);
      await _platformService.secureWrite(_storageKeyPinHash, bakHashVal);
      await _platformService.secureWrite(
          _storageKeyMasterWrapped, bakWrappedVal);
      await _cleanupSwapArtifacts();
      return;
    }

    // Incomplete backup: do NOT delete anything.
    throw VaultSwapRecoveryException(
      'Interrupted vault swap detected with incomplete backup data; cannot safely recover.',
    );
  }

  Future<void> _cleanupTempKeys() async {
    await _platformService.secureDelete(_tmpSalt);
    await _platformService.secureDelete(_tmpPinHash);
    await _platformService.secureDelete(_tmpMasterWrapped);
  }

  Future<void> _cleanupSwapArtifacts() async {
    await _platformService.secureDelete(_swapMarker);
    await _cleanupTempKeys();
    await _platformService.secureDelete(_bakSalt);
    await _platformService.secureDelete(_bakPinHash);
    await _platformService.secureDelete(_bakMasterWrapped);
  }

  bool _constantTimeBytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
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

  Future<Uint8List> _deriveKey(String pin, String saltBase64, [int iterations = kPbkdf2Iterations]) async {
    final passwordBytes = Uint8List.fromList(utf8.encode(pin));
    final saltBytes = base64Decode(saltBase64);
    return await derivePbkdf2Async(
      passwordBytes,
      saltBytes,
      iterations,
      kDerivedKeyLength,
    );
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

  /// Encrypts [src] to [dest] using AES-CTR with magic "MVKEYc2\0" keyed by the master DEK (_derivedKey).
  /// Files written in this format are fully recoverable from the 12-word recovery phrase upon reinstall.
  Future<void> encryptStreamSystemCtr(File src, File dest) async {
    if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
    final iv = _generateSecureRandomBytes(16);
    final raf = await dest.open(mode: FileMode.write);
    try {
      await raf.writeFrom(_mediaMagicCtrV2);
      await raf.writeFrom(iv);

      final aes = AESEngine()..init(true, KeyParameter(_derivedKey!));
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
        bool isC2 = true;
        for (int i = 0; i < 8; i++) {
          if (magicBuffer[i] != _mediaMagic[i]) isV1 = false;
          if (magicBuffer[i] != _mediaMagicCtr[i]) isC1 = false;
          if (magicBuffer[i] != _mediaMagicCtrV2[i]) isC2 = false;
        }
        if (isV1) magicType = 1;
        else if (isC1) magicType = 2;
        else if (isC2) magicType = 3;
      }

      if (magicType == 2 || magicType == 3) {
        final fileLength = await src.length();
        final maxReadable = fileLength - 24;
        if (offset >= maxReadable || offset < 0) return Uint8List(0);
        
        int actualLength = length;
        if (offset + length > maxReadable) {
          actualLength = maxReadable - offset;
        }
        if (actualLength <= 0) return Uint8List(0);

        final Uint8List key;
        if (magicType == 3) {
          if (!_isUnlocked || _derivedKey == null) throw Exception('Vault is locked');
          key = _derivedKey!;
        } else {
          key = await _getSystemKey();
        }
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

        final aes = AESEngine()..init(true, KeyParameter(key));
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
