// lib/vault/export/vault_exporter.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

/// Handles exporting and sharing the entire Mimic Vault as a single
/// `.mimic` binary backup file.
///
/// File format:
/// ```
/// [4 bytes]     ASCII magic: M I M C
/// [1 byte]      Version: 0x01
/// [32 bytes]    SHA-256 checksum of the JSON payload bytes
/// [8 bytes]     Unix-millisecond timestamp, big-endian int64
/// [remaining]   JSON payload bytes (UTF-8 encoded)
/// ```
class VaultExporter {
  // ─── ASCII magic header ───────────────────────────────────────────
  static const List<int> _magic = [0x4D, 0x4D, 0x49, 0x43]; // M M I C
  static const int _version = 0x01;

  // ─── Secure-storage keys that hold vault data ─────────────────────
  static const List<String> _secureKeys = [
    // Photo metadata (JSON array of PhotoMeta maps)
    'vault_photos_meta',
    // Video metadata (JSON array of VideoMeta maps)
    'vault_videos_meta',
    // Document metadata (JSON array of DocumentMeta maps)
    'vault_documents_meta',
    // Notes (JSON array of Note maps – titles & encrypted bodies)
    'vault_notes',
    // Recovery phrase blob (base64-encoded AES-encrypted mnemonic)
    'recovery_blob',
    // Recovery phrase salt (base64-encoded salt used during recovery)
    'recovery_salt',
    // Vault salt (base64-encoded PBKDF2 salt for key derivation)
    'vault_salt',
    // PIN hash (used to verify the PIN on unlock)
    'vault_pin_hash',
  ];

  // ───────────────────────────────────────────────────────────────────
  //  buildExportFile
  // ───────────────────────────────────────────────────────────────────

  /// Reads all encrypted vault data from flutter_secure_storage, bundles it
  /// into a JSON payload, wraps it in the `.mimic` binary container, and
  /// saves the result to the device's Downloads directory.
  ///
  /// Returns the written [File].
  static Future<File> buildExportFile() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    // ── 1. Collect all secure-storage entries into a payload map ──────
    final Map<String, dynamic> payload = {};

    for (final key in _secureKeys) {
      final value = await storage.read(key: key);
      if (value != null && value.isNotEmpty) {
        payload[key] = value;
      }
    }

    // ── 1.5. If not web, populate payload with SQLite database records ──
    if (!kIsWeb) {
      // 1. Photos
      final photosDbPath = p.join(await getDatabasesPath(), 'vault_files.db');
      if (await File(photosDbPath).exists()) {
        final db = await openDatabase(photosDbPath);
        try {
          final maps = await db.query('photos');
          if (maps.isNotEmpty) {
            payload['vault_photos_meta'] = jsonEncode(maps);
          }
        } catch (_) {}
        await db.close();
      }

      // 2. Videos
      final videosDbPath = p.join(await getDatabasesPath(), 'vault_videos.db');
      if (await File(videosDbPath).exists()) {
        final db = await openDatabase(videosDbPath);
        try {
          final maps = await db.query('videos');
          if (maps.isNotEmpty) {
            payload['vault_videos_meta'] = jsonEncode(maps);
          }
        } catch (_) {}
        await db.close();
      }

      // 3. Notes
      final notesDbPath = p.join(await getDatabasesPath(), 'vault_notes.db');
      if (await File(notesDbPath).exists()) {
        final db = await openDatabase(notesDbPath);
        try {
          final maps = await db.query('notes');
          if (maps.isNotEmpty) {
            final noteList = maps.map((map) {
              return {
                'id': map['id'],
                'title': map['title'],
                'encryptedBody': map['encryptedBody'],
                'createdAt': map['created_at'],
                'updatedAt': map['updated_at'],
              };
            }).toList();
            payload['vault_notes'] = jsonEncode(noteList);
          }
        } catch (_) {}
        await db.close();
      }
    }

    // ── 2. Read encrypted files from the app-documents directory ──────
    //    Photos and audio are stored as individual encrypted blobs whose
    //    filenames match UUID ids listed in vault_photos_meta / vault_audio_meta.
    final appDir = await getApplicationDocumentsDirectory();
    final Map<String, String> encryptedFiles = {};

    // Gather IDs from photo metadata
    final photoIds = _extractIds(payload['vault_photos_meta']);
    for (final id in photoIds) {
      final file = File('${appDir.path}/vault_files/$id');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        encryptedFiles[id] = base64Encode(bytes);
      }
    }

    // Gather IDs from video metadata
    final videoIds = _extractIds(payload['vault_videos_meta']);
    for (final id in videoIds) {
      final file = File('${appDir.path}/vault_files/$id');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        encryptedFiles[id] = base64Encode(bytes);
      }
    }

    // Gather IDs from document metadata
    final documentIds = _extractIds(payload['vault_documents_meta']);
    for (final id in documentIds) {
      final file = File('${appDir.path}/vault_files/$id');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        encryptedFiles[id] = base64Encode(bytes);
      }
    }

    if (encryptedFiles.isNotEmpty) {
      payload['encrypted_files'] = encryptedFiles;
    }

    // ── 3. Encode JSON payload ───────────────────────────────────────
    final jsonString = jsonEncode(payload);
    final Uint8List jsonBytes = Uint8List.fromList(utf8.encode(jsonString));

    // ── 4. Compute SHA-256 checksum over the JSON payload bytes ──────
    final Digest checksum = sha256.convert(jsonBytes);
    final Uint8List checksumBytes = Uint8List.fromList(checksum.bytes);

    // ── 5. Timestamp: current Unix milliseconds as big-endian int64 ──
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final ByteData timestampData = ByteData(8);
    timestampData.setInt64(0, nowMs, Endian.big);
    final Uint8List timestampBytes = timestampData.buffer.asUint8List();

    // ── 6. Assemble the .mimic binary ────────────────────────────────
    final builder = BytesBuilder(copy: false);
    builder.add(_magic);                       // 4 bytes  – magic
    builder.addByte(_version);                 // 1 byte   – version
    builder.add(checksumBytes);                // 32 bytes – SHA-256
    builder.add(timestampBytes);               // 8 bytes  – timestamp
    builder.add(jsonBytes);                    // N bytes  – payload

    final Uint8List fileBytes = builder.toBytes();

    // ── 7. Write to the Downloads directory ──────────────────────────
    final downloadsDir = await _getDownloadsDirectory();
    final fileName = 'Mimic_Backup_$nowMs.mimic';
    final outputFile = File('${downloadsDir.path}/$fileName');
    await outputFile.writeAsBytes(fileBytes, flush: true);

    return outputFile;
  }

  // ───────────────────────────────────────────────────────────────────
  //  shareFile
  // ───────────────────────────────────────────────────────────────────

  /// Opens the native Android share sheet for the given [file].
  static Future<void> shareFile(File file) async {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'Mimic Vault Backup',
    );
  }

  // ───────────────────────────────────────────────────────────────────
  //  Private helpers
  // ───────────────────────────────────────────────────────────────────

  /// Attempts to resolve the device Downloads directory.
  /// Falls back to external storage root, then to app documents directory.
  static Future<Directory> _getDownloadsDirectory() async {
    // On Android, the public Downloads folder lives at
    // /storage/emulated/0/Download
    final downloadsPath = Directory('/storage/emulated/0/Download');
    if (await downloadsPath.exists()) {
      return downloadsPath;
    }

    // Fallback: external storage directory (may be null on some devices,
    // and throws UnsupportedError on non-Android platforms)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return extDir;
      }
    } catch (_) {
      // Not on Android – fall through to app documents directory
    }

    // Last resort: application documents directory
    return await getApplicationDocumentsDirectory();
  }

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
