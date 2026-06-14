// lib/vault/export/vault_importer.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/platform_service.dart';
import '../services/file_vault_service.dart';
import '../services/video_vault_service.dart';
import '../services/notes_service.dart';

import '../crypto/recovery_phrase.dart';
import '../crypto/vault_crypto.dart';

/// Represents the result of validating a `.mimic` backup file.
class ImportValidationResult {
  final bool isValid;
  final String? reason;

  ImportValidationResult({required this.isValid, this.reason});

  factory ImportValidationResult.valid() => ImportValidationResult(isValid: true);
  factory ImportValidationResult.invalid(String reason) =>
      ImportValidationResult(isValid: false, reason: reason);
}

/// Handles validating and importing backup `.mimic` files.
class VaultImporter {
  // ─── ASCII magic header ───────────────────────────────────────────
  static const List<int> _magic = [0x4D, 0x4D, 0x49, 0x43]; // M M I C
  static const int _version = 0x01;

  // ───────────────────────────────────────────────────────────────────
  //  validateFile
  // ───────────────────────────────────────────────────────────────────

  /// Reads a binary `.mimic` file and verifies the magic header, version,
  /// and SHA-256 checksum of the payload bytes.
  static Future<ImportValidationResult> validateFile(File file) async {
    try {
      if (!await file.exists()) {
        return ImportValidationResult.invalid("File does not exist");
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 45) {
        return ImportValidationResult.invalid("File too short");
      }

      // Check magic header: M M I C (0x4D, 0x4D, 0x49, 0x43)
      if (bytes[0] != _magic[0] ||
          bytes[1] != _magic[1] ||
          bytes[2] != _magic[2] ||
          bytes[3] != _magic[3]) {
        return ImportValidationResult.invalid("Invalid file format: Magic header mismatch");
      }

      // Check version
      final version = bytes[4];
      if (version != _version) {
        return ImportValidationResult.invalid("Unsupported backup version");
      }

      // Verify SHA-256 checksum
      final storedChecksum = bytes.sublist(5, 37);
      final payloadBytes = bytes.sublist(45);
      final computedChecksum = sha256.convert(payloadBytes).bytes;

      bool checksumMatches = true;
      for (int i = 0; i < 32; i++) {
        if (storedChecksum[i] != computedChecksum[i]) {
          checksumMatches = false;
          break;
        }
      }
      if (!checksumMatches) {
        return ImportValidationResult.invalid("File corrupted: checksum mismatch");
      }

      return ImportValidationResult.valid();
    } catch (e) {
      return ImportValidationResult.invalid("Failed to read file: $e");
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  importWithPhrase
  // ───────────────────────────────────────────────────────────────────

  /// Decrypts the backup file using the 12-word recovery phrase.
  /// If successful, writes all encrypted vault data back to local storage and
  /// secure storage/databases, and loads the master key into [VaultCrypto].
  static Future<bool> importWithPhrase(File file, List<String> recoveryWords) async {

    final validationResult = await validateFile(file);
    if (!validationResult.isValid) {
      return false;
    }

    bool phraseVerified = false;

    try {
      final bytes = await file.readAsBytes();
      final payloadBytes = bytes.sublist(45);
      final jsonString = utf8.decode(payloadBytes);
      final Map<String, dynamic> payload = jsonDecode(jsonString);

      // Extract recovery fields
      final recoveryBlobStr = payload['recovery_blob'] as String?;
      final recoverySaltStr = payload['recovery_salt'] as String?;
      if (recoveryBlobStr == null || recoverySaltStr == null) {
        return false;
      }

      final blob = base64Decode(recoveryBlobStr);
      final salt = base64Decode(recoverySaltStr);

      // Derive recovery key
      final recoveryKey = RecoveryPhrase.deriveKey(recoveryWords, salt);

      if (blob.length < 16) return false;
      final iv = blob.sublist(0, 16);
      final encryptedMasterKey = blob.sublist(16);

      final cipher = CBCBlockCipher(AESEngine());
      final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
      paddedCipher.init(
        false,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(recoveryKey), iv), null),
      );

      Uint8List masterKey;
      try {
        masterKey = paddedCipher.process(encryptedMasterKey);
      } catch (e) {
        return false; // Wrong phrase
      }

      if (masterKey.length != 32) {
        return false; // Invalid master key length: wrong phrase
      }

      phraseVerified = true;

      // ─── Phrase verified successfully. Restoring data ─────────────────

      // 1. Retrieve and delete old encrypted files from app storage
      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      
      final platformService = kIsWeb ? WebPlatformService() : AndroidPlatformService();
      final fileService = FileVaultService(platformService, VaultCrypto.instance);
      final videoService = VideoVaultService(platformService, VaultCrypto.instance);
      final notesService = NotesService(platformService, VaultCrypto.instance);
      
      final List<String> oldFileIds = [];
      if (kIsWeb) {
        final oldPhotosMeta = await storage.read(key: 'vault_photos_meta');
        final oldVideosMeta = await storage.read(key: 'vault_videos_meta');
        final oldDocsMeta = await storage.read(key: 'vault_documents_meta');
        oldFileIds.addAll(_extractIds(oldPhotosMeta));
        oldFileIds.addAll(_extractIds(oldVideosMeta));
        oldFileIds.addAll(_extractIds(oldDocsMeta));
      } else {
        try {
          final photos = await fileService.getAllPhotos();
          oldFileIds.addAll(photos.map((p) => p.id));
        } catch (_) {}
        
        try {
          final videos = await videoService.getAllVideos();
          oldFileIds.addAll(videos.map((v) => v.id));
        } catch (_) {}
        
        final oldDocsMeta = await storage.read(key: 'vault_documents_meta');
        oldFileIds.addAll(_extractIds(oldDocsMeta));
      }

      final appDir = await getApplicationDocumentsDirectory();
      for (final id in oldFileIds) {
        final f = File('${appDir.path}/vault_files/$id');
        if (await f.exists()) {
          await f.delete();
        }
      }

      // 2. Restore new encrypted files to disk
      if (payload.containsKey('encrypted_files')) {
        final vaultDir = Directory('${appDir.path}/vault_files');
        if (!await vaultDir.exists()) {
          await vaultDir.create(recursive: true);
        }
        
        final encryptedFiles = payload['encrypted_files'] as Map<String, dynamic>;
        for (final entry in encryptedFiles.entries) {
          final id = entry.key;
          final base64Data = entry.value as String;
          final fileBytes = base64Decode(base64Data);
          final f = File('${vaultDir.path}/$id');
          await f.writeAsBytes(fileBytes, flush: true);
        }
      }

      // 3. Overwrite secure storage keys
      final secureKeys = [
        'vault_photos_meta',
        'vault_videos_meta',
        'vault_documents_meta',
        'vault_notes',
        'recovery_blob',
        'recovery_salt',
        'vault_salt',
        'vault_pin_hash',
      ];
      for (final key in secureKeys) {
        final val = payload[key] as String?;
        if (val != null) {
          try {
            await storage.write(key: key, value: val);
          } catch (e) {
            rethrow;
          }
          if (key == 'vault_documents_meta' && !kIsWeb) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(key, val);
          }
        } else {
          await storage.delete(key: key);
          if (key == 'vault_documents_meta' && !kIsWeb) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(key);
          }
        }
      }

      // 4. Overwrite SQLite databases on Android/non-web
      if (!kIsWeb) {
        // Restore photos db
        final photosMetaStr = payload['vault_photos_meta'] as String?;
        if (photosMetaStr != null && photosMetaStr.isNotEmpty) {
          final List<dynamic> decodedPhotos = jsonDecode(photosMetaStr);
          await fileService.restorePhotos(decodedPhotos);
        }

        // Restore videos db
        final videosMetaStr = payload['vault_videos_meta'] as String?;
        if (videosMetaStr != null && videosMetaStr.isNotEmpty) {
          final List<dynamic> decodedVideos = jsonDecode(videosMetaStr);
          await videoService.restoreVideos(decodedVideos);
        }

        // Restore notes db
        final notesStr = payload['vault_notes'] as String?;
        if (notesStr != null && notesStr.isNotEmpty) {
          final List<dynamic> decodedNotes = jsonDecode(notesStr);
          await notesService.restoreNotes(decodedNotes);
        }
      }

      // 5. Load derived key into VaultCrypto singleton
      final cryptoSuccess = await VaultCrypto.instance.recoverWithPhrase(recoveryWords);
      // Validate blob existence
      final missingIds = <String>[];
      final vaultDir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'vault_files'));
      
      List<String> extractIds(String? jsonStr) {
        if (jsonStr == null || jsonStr.isEmpty) return [];
        try {
          final decoded = jsonDecode(jsonStr) as List<dynamic>;
          return decoded.map((e) => (e as Map)['id'] as String?).whereType<String>().toList();
        } catch (_) { return []; }
      }
      
      final allExpectedIds = [
        ...extractIds(payload['vault_photos_meta'] as String?),
        ...extractIds(payload['vault_videos_meta'] as String?),
      ];
      
      for (final id in allExpectedIds) {
        if (!File('${vaultDir.path}/$id').existsSync()) {
          missingIds.add(id);
        }
      }

      // STEP 4: explicitly write vault_setup_completed flag
      try {
        await storage.write(key: 'vault_setup_completed', value: 'true');
      } catch (_) {}

      if (missingIds.isNotEmpty) {
        throw Exception('Restore incomplete: ${missingIds.length} media file(s) could not be restored');
      }

      return cryptoSuccess;
    } catch (e, st) {
      // Since we got past the phrase check, any other error shouldn't report "Incorrect phrase".
      if (!phraseVerified) return false;
      debugPrint('RESTORE FAIL: $e');
      if (e is Exception && e.toString().contains('Restore incomplete')) {
        throw e;
      }
      throw Exception('Restore failed: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  Private helpers
  // ───────────────────────────────────────────────────────────────────

  /// Parses a JSON-encoded list of metadata maps and extracts each entry's
  /// `'id'` field. Returns an empty list if [rawJson] is `null` or invalid.
  static List<String> _extractIds(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(rawJson);
      return decoded
          .map((e) => (e as Map<String, dynamic>)['id'] as String?)
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
