// lib/vault/export/vault_importer.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';

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

      // Decrypt master key to verify phrase correctness
      final cipher = CBCBlockCipher(AESEngine());
      final paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cipher);
      paddedCipher.init(
        false,
        PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(recoveryKey), iv), null),
      );

      Uint8List masterKey;
      try {
        masterKey = paddedCipher.process(encryptedMasterKey);
      } catch (_) {
        return false; // Decryption failed: wrong phrase
      }

      if (masterKey.length != 32) {
        return false; // Invalid master key length: wrong phrase
      }

      // ─── Phrase verified successfully. Restoring data ─────────────────

      // 1. Retrieve and delete old encrypted files from app storage
      const storage = FlutterSecureStorage();
      final List<String> oldFileIds = [];
      if (kIsWeb) {
        final oldPhotosMeta = await storage.read(key: 'vault_photos_meta');
        final oldAudioMeta = await storage.read(key: 'vault_audio_meta');
        oldFileIds.addAll(_extractIds(oldPhotosMeta));
        oldFileIds.addAll(_extractIds(oldAudioMeta));
      } else {
        final filesDbPath = p.join(await getDatabasesPath(), 'vault_files.db');
        if (await File(filesDbPath).exists()) {
          final db = await openDatabase(filesDbPath);
          try {
            final maps = await db.query('photos');
            oldFileIds.addAll(maps.map((m) => m['id'] as String));
          } catch (_) {}
          await db.close();
        }
        final audioDbPath = p.join(await getDatabasesPath(), 'vault_audio.db');
        if (await File(audioDbPath).exists()) {
          final db = await openDatabase(audioDbPath);
          try {
            final maps = await db.query('audio');
            oldFileIds.addAll(maps.map((m) => m['id'] as String));
          } catch (_) {}
          await db.close();
        }
      }

      final appDir = await getApplicationDocumentsDirectory();
      for (final id in oldFileIds) {
        final f = File('${appDir.path}/$id');
        if (await f.exists()) {
          await f.delete();
        }
      }

      // 2. Restore new encrypted files to disk
      if (payload.containsKey('encrypted_files')) {
        final encryptedFiles = payload['encrypted_files'] as Map<String, dynamic>;
        for (final entry in encryptedFiles.entries) {
          final id = entry.key;
          final base64Data = entry.value as String;
          final fileBytes = base64Decode(base64Data);
          final f = File('${appDir.path}/$id');
          await f.writeAsBytes(fileBytes, flush: true);
        }
      }

      // 3. Overwrite secure storage keys
      final secureKeys = [
        'vault_photos_meta',
        'vault_audio_meta',
        'vault_notes',
        'recovery_blob',
        'recovery_salt',
        'vault_salt',
        'vault_pin_hash',
      ];
      for (final key in secureKeys) {
        final val = payload[key] as String?;
        if (val != null) {
          await storage.write(key: key, value: val);
        } else {
          await storage.delete(key: key);
        }
      }

      // 4. Overwrite SQLite databases on Android/non-web
      if (!kIsWeb) {
        // Restore photos db
        final photosMetaStr = payload['vault_photos_meta'] as String?;
        if (photosMetaStr != null && photosMetaStr.isNotEmpty) {
          final List<dynamic> decodedPhotos = jsonDecode(photosMetaStr);
          final dbPath = p.join(await getDatabasesPath(), 'vault_files.db');
          final db = await openDatabase(
            dbPath,
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE photos(
                  id TEXT PRIMARY KEY,
                  mimeType TEXT,
                  size INTEGER,
                  createdAt TEXT
                )
              ''');
            },
          );
          await db.delete('photos');
          for (final photo in decodedPhotos) {
            final map = Map<String, dynamic>.from(photo);
            await db.insert('photos', map, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await db.close();
        }

        // Restore audio db
        final audioMetaStr = payload['vault_audio_meta'] as String?;
        if (audioMetaStr != null && audioMetaStr.isNotEmpty) {
          final List<dynamic> decodedAudio = jsonDecode(audioMetaStr);
          final dbPath = p.join(await getDatabasesPath(), 'vault_audio.db');
          final db = await openDatabase(
            dbPath,
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE audio(
                  id TEXT PRIMARY KEY,
                  title TEXT,
                  durationMs INTEGER,
                  mimeType TEXT,
                  size INTEGER,
                  createdAt TEXT
                )
              ''');
            },
          );
          await db.delete('audio');
          for (final audio in decodedAudio) {
            final map = Map<String, dynamic>.from(audio);
            await db.insert('audio', map, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await db.close();
        }

        // Restore notes db
        final notesStr = payload['vault_notes'] as String?;
        if (notesStr != null && notesStr.isNotEmpty) {
          final List<dynamic> decodedNotes = jsonDecode(notesStr);
          final dbPath = p.join(await getDatabasesPath(), 'vault_notes.db');
          final db = await openDatabase(
            dbPath,
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE notes(
                  id TEXT PRIMARY KEY,
                  title TEXT,
                  encryptedBody TEXT,
                  created_at TEXT,
                  updated_at TEXT
                )
              ''');
            },
          );
          await db.delete('notes');
          for (final note in decodedNotes) {
            final map = Map<String, dynamic>.from(note);
            final dbMap = {
              'id': map['id'],
              'title': map['title'],
              'encryptedBody': map['encryptedBody'],
              'created_at': map['createdAt'],
              'updated_at': map['updatedAt'],
            };
            await db.insert('notes', dbMap, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          await db.close();
        }
      }

      // 5. Load derived key into VaultCrypto singleton
      final cryptoSuccess = await VaultCrypto.instance.recoverWithPhrase(recoveryWords);
      return cryptoSuccess;
    } catch (_) {
      return false;
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
