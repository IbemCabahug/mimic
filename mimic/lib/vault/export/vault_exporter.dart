// lib/vault/export/vault_exporter.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../services/file_vault_service.dart';
import '../services/video_vault_service.dart';
import '../services/document_vault_service.dart';
import '../services/vault_backup_status.dart';
import 'mimic_v2_format.dart';


/// Handles exporting and sharing the entire Mimic Vault as a single
/// `.mimic` binary backup file.
///
/// File format (v2):
/// ```
/// [4 bytes]     ASCII magic: M M I C
/// [1 byte]      Version: 0x02
/// [8 bytes]     Unix-millisecond timestamp, big-endian int64
/// [4 bytes]     Metadata-length N, big-endian uint32
/// [N bytes]     JSON metadata (UTF-8 encoded, NO media blobs)
/// [BLOB]*       Length-prefixed blob entries (streamed from disk)
/// [32 bytes]    SHA-256 trailer (incremental hash of everything above)
/// ```
class VaultExporter {
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
  /// into a JSON payload, wraps it in the `.mimic` v2 binary container with
  /// streaming blob writes, and saves the result to the device's Downloads
  /// directory.
  ///
  /// Returns the written [File].
  static Future<File> buildExportFile(dynamic ref, {String? overwritePath}) async {
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

    // ── 2. Gather file IDs ───────────────────────────────────────────
    final appDir = await getApplicationDocumentsDirectory();

    final photoIds = _extractIds(payload['vault_photos_meta']);
    final videoIds = _extractIds(payload['vault_videos_meta']);
    final documentIds = _extractIds(payload['vault_documents_meta']);
    final noteIds = _extractIds(payload['vault_notes']);

    // Collect all media IDs that will become blobs
    final allMediaIds = <String>[...photoIds, ...videoIds, ...documentIds];

    // ── 3. Build the v2 metadata JSON (NO encrypted_files map) ───────
    // Include an authoritative list of file IDs that will be streamed.
    payload['blob_ids'] = allMediaIds;
    // Do NOT include 'encrypted_files' — blobs are streamed separately.
    payload.remove('encrypted_files');

    final jsonString = jsonEncode(payload);
    final Uint8List metadataBytes = Uint8List.fromList(utf8.encode(jsonString));

    // ── 4. Write v2 container to a temp file ─────────────────────────
    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    final File outputFile;
    if (overwritePath != null) {
      outputFile = File(overwritePath);
    } else {
      final downloadsDir = await _getDownloadsDirectory();
      final fileName = 'backup_data_$nowMs.dat';
      outputFile = File('${downloadsDir.path}/$fileName');
    }

    final tempFile = File('${outputFile.path}.part');

    try {
      final sink = tempFile.openWrite();
      final writer = MimicV2Writer(sink);

      writer.writeHeader(nowMs, metadataBytes);

      for (final id in allMediaIds) {
        final blobFile = File('${appDir.path}/vault_files/$id');
        if (await blobFile.exists()) {
          final blobLength = await blobFile.length();
          await writer.writeBlob(id, blobLength, blobFile.openRead());
        }
      }

      await writer.finish();
      await sink.close();

      // Rename temp → final
      await tempFile.rename(outputFile.path);
    } catch (e) {
      // Clean up partial temp file on any error
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      rethrow;
    }

    // ── 5. Record export status ──────────────────────────────────────
    final totalCount = photoIds.length + videoIds.length + documentIds.length + noteIds.length;
    final status = await VaultBackupStatus.init();
    await status.recordExport(totalCount, outputFile.path);

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
