// mimic/lib/vault/services/vault_wipe_service.dart
//
// Danger Zone → Clear All Data. One owner for the full content wipe.
//
// r28 device finding (Vivo V29e, 2026-09-21): the old Settings dialog deleted
// only four secure-storage keys — `break_in_logs`, `vault_photos_meta`,
// `vault_audio_meta`, `vault_notes` — of which the photos and notes keys are
// the WEB-ONLY stores. On a device, photo metadata lives in `vault_files.db`,
// video metadata in `vault_videos.db`, notes in `vault_notes.db`, document
// metadata in `vault_documents_meta` (secure + prefs), and every encrypted
// blob in the shared `vault_files/` directory — none of which were touched.
// The vault kept listing videos, photos, documents and notes, and the video
// thumbnails came straight back because their blobs were still there. Even a
// deleted database keeps serving rows while a connection to it stays open,
// so the services close their cached connections as part of this wipe.
//
// Deliberately NOT touched: the PIN, keystore-wrapped master key, recovery
// blob, duress PIN, unlock gesture, and concealment settings — the checklist
// (Phase 10.1) requires the vault to stay unlockable and setup-able with an
// empty content store afterwards.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/services/platform_service.dart';
import 'document_vault_service.dart';
import 'file_vault_service.dart';
import 'intruder_service.dart';
import 'media_stream_server.dart';
import 'notes_service.dart';
import 'video_vault_service.dart';

class VaultWipeService {
  VaultWipeService(this._platformService, this._fileVault, this._videoVault,
      this._notes, this._documents);

  final PlatformService _platformService;
  final FileVaultService _fileVault;
  final VideoVaultService _videoVault;
  final NotesService _notes;
  final DocumentVaultService _documents;

  /// Content metadata keys removed everywhere (mobile stores AND the
  /// web/legacy keys the old dialog half-targeted). `vault_audio_meta` is
  /// kept in the list for when the F17 audio vault arrives — deleting a
  /// missing key is a no-op today.
  static const List<String> _contentMetaKeys = [
    'break_in_logs',
    'vault_photos_meta',
    'vault_audio_meta',
    'vault_videos_meta',
    'vault_documents_meta',
    'vault_notes',
  ];

  /// Databases wiped here. The photo/video/notes services delete their own
  /// database in `wipeAllData()`; this list re-covers them defensively (plus
  /// every SQLite sidecar) and owns the break-in log DB, which has no
  /// service-owned wipe of its own.
  static const List<String> _databases = [
    'vault_files.db',
    'vault_videos.db',
    'vault_notes.db',
    'breakin_logs.db',
  ];

  Future<void> wipeAllContent() async {
    // 1. Stop any running media stream first — the streaming server holds
    //    open reads on video blobs, and an open handle can keep a deleted
    //    file alive or make the delete fail.
    try {
      await MediaStreamServer.instance.stop();
    } catch (_) {}

    // 2. Each service closes its cached connection and removes its own
    //    database, sidecars and metadata key.
    await _fileVault.wipeAllData();
    await _videoVault.wipeAllData();
    await _notes.wipeAllData();
    await _documents.wipeAllData();

    // 3. Remaining metadata keys (break-in index + legacy/web stores).
    for (final key in _contentMetaKeys) {
      try {
        await _platformService.secureDelete(key);
      } catch (_) {}
    }

    if (kIsWeb) return;

    // 4. Databases + sidecars, including the break-in log DB.
    try {
      final dbDir = await getDatabasesPath();
      for (final name in _databases) {
        await _deleteSqliteArtifacts(p.join(dbDir, name));
      }
    } catch (_) {}

    try {
      final docsDir = await getApplicationDocumentsDirectory();

      // 5. The shared encrypted blob directory (photos + videos + documents;
      //    a directory purge also catches orphaned blobs no meta row names,
      //    e.g. leftovers from an interrupted migration).
      await _emptyDirectory(Directory(p.join(docsDir.path, 'vault_files')));

      // 6. Intruder evidence files sit loose in the documents root.
      final entities = docsDir.listSync();
      for (final entity in entities) {
        if (entity is File &&
            p.basename(entity.path).startsWith(IntruderService.filePrefix) &&
            p.extension(entity.path) == IntruderService.fileExtension) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }

      // 7. Decrypted leftovers in temp: share exports and opened documents.
      final tempDir = await getTemporaryDirectory();
      await _emptyDirectory(Directory(p.join(tempDir.path, 'vault_share')));
      await _emptyDirectory(Directory(p.join(tempDir.path, 'vault_docs')));
    } catch (_) {}
  }

  Future<void> _deleteSqliteArtifacts(String dbPath) async {
    for (final suffix in const ['', '-journal', '-wal', '-shm']) {
      try {
        final artifact = File('$dbPath$suffix');
        if (await artifact.exists()) {
          await artifact.delete();
        }
      } catch (_) {}
    }
  }

  /// Deletes the CONTENTS of [dir], not the directory itself — the vault
  /// services recreate paths inside it on demand, and a missing directory is
  /// handled too, but keeping it avoids a window where a save would fail.
  Future<void> _emptyDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
}

final vaultWipeServiceProvider = Provider<VaultWipeService>((ref) {
  return VaultWipeService(
    ref.read(platformServiceProvider),
    ref.read(fileVaultServiceProvider),
    ref.read(videoVaultServiceProvider),
    ref.read(notesServiceProvider),
    ref.read(documentVaultServiceProvider),
  );
});
