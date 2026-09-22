// lib/vault/services/video_vault_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';
import '../crypto/media_format.dart';
import '../security/auto_lock.dart';

class VideoMeta {
  final String id;
  final String mimeType;
  final int size;
  final int durationS;
  final DateTime createdAt;
  final String? originalName;
  // Folder feature (mirrors DocumentMeta.folder): '' = Unfiled. Filter-only —
  // the encrypted blob never moves; only this label changes.
  final String folder;

  VideoMeta({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.durationS,
    required this.createdAt,
    this.originalName,
    this.folder = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mimeType': mimeType,
        'size': size,
        'durationS': durationS,
        'createdAt': createdAt.toIso8601String(),
        'originalName': originalName,
        'folder': folder,
      };

  factory VideoMeta.fromMap(Map<String, dynamic> map) => VideoMeta(
        id: map['id'] as String,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        durationS: map['durationS'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        originalName: map['originalName'] as String?,
        // Pre-folder rows (and v2 backup payloads) carry no key — ?? '' keeps
        // them readable as Unfiled instead of throwing.
        folder: map['folder'] as String? ?? '',
      );

  /// Copies this metadata with the given fields replaced.
  VideoMeta copyWith({
    String? mimeType,
    int? size,
    int? durationS,
    DateTime? createdAt,
    String? originalName,
    String? folder,
  }) {
    return VideoMeta(
      id: id,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      durationS: durationS ?? this.durationS,
      createdAt: createdAt ?? this.createdAt,
      originalName: originalName ?? this.originalName,
      folder: folder ?? this.folder,
    );
  }
}

/// Why a video conversion attempt did not end with a streamable blob.
enum VideoMigrationFailure {
  /// Nothing is wrong: the blob was already c2, or the conversion succeeded.
  none,
  /// The decrypted plaintext did not look like a video container we write, so
  /// the destructive re-encrypt was refused and the original was left alone.
  refusedNotAContainer,
  /// The vault locked while the conversion was running, so the keys were gone
  /// and the attempt was abandoned. The original blob is untouched.
  vaultLocked,
  /// The blob could not be read or written.
  io,
  /// Anything else. [VideoMigrationOutcome.detail] names the runtime type.
  unknown,
}

/// How far a conversion attempt got before it stopped.
enum VideoMigrationStage {
  precheck,
  header,
  decrypt,
  containerGate,
  reencrypt,
  rename,
  cleanup,
}

/// The honest result of one conversion attempt, built on every exit path so that
/// a failure can never be silent again (register items H16 and M35).
class VideoMigrationOutcome {
  final String videoId;

  /// One of 'already-c2', 'v1', 'c1', 'legacy' or 'missing'.
  final String sourceKind;

  /// True when the blob is streamable now: it was already c2, or it became c2.
  final bool converted;

  final VideoMigrationFailure failure;

  /// The step that was running when the attempt stopped.
  final VideoMigrationStage? failedAt;

  /// Exception runtime type plus a path-free, length-bounded message. Never
  /// contains key material, and never contains a file path.
  final String? detail;

  /// Bytes of plaintext produced by the decrypt step, before the re-encrypt.
  final int plaintextBytes;

  final int durationMs;

  const VideoMigrationOutcome({
    required this.videoId,
    required this.sourceKind,
    required this.converted,
    required this.failure,
    this.failedAt,
    this.detail,
    this.plaintextBytes = 0,
    this.durationMs = 0,
  });
}

class VideoVaultService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _dbName = 'vault_videos.db';
  static const String _tableName = 'videos';
  Database? _db;
  Future<void>? _openDbFuture;

  int _openCount = 0;

  @visibleForTesting
  int get openCount => _openCount;

  VideoMigrationOutcome? _lastMigrationOutcome;
  final Map<String, VideoMigrationOutcome> _migrationOutcomes = {};

  /// The most recent conversion attempt, whatever its outcome. In-memory
  /// diagnostic state for the current session; never persisted.
  VideoMigrationOutcome? get lastMigrationOutcome => _lastMigrationOutcome;

  /// The most recent conversion attempt for one video, or null when no attempt
  /// has been made in this session.
  VideoMigrationOutcome? migrationOutcomeFor(String id) => _migrationOutcomes[id];

  VideoVaultService(this._platformService, this._crypto);

  Future<void> _ensureDb() async {
    if (kIsWeb) return;
    if (_db != null && _db!.isOpen) return;
    if (_db != null && !_db!.isOpen) {
      _openDbFuture = null;
      _db = null;
    }
    _openDbFuture ??= () async {
      _openCount++;
      _db = await openDatabase(
        p.join(await getDatabasesPath(), _dbName),
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_tableName(
              id TEXT PRIMARY KEY,
              mimeType TEXT,
              size INTEGER,
              durationS INTEGER,
              createdAt TEXT,
              originalName TEXT,
              folder TEXT DEFAULT ''
            )
          ''');
        },
        onOpen: (db) async {
          // Folder feature: pre-folder installs lack the column; photos
          // already migrate originalName this way, so videos follow suit.
          try {
            final List<Map<String, dynamic>> columns =
                await db.rawQuery('PRAGMA table_info($_tableName)');
            final hasFolder =
                columns.any((column) => column['name'] == 'folder');
            if (!hasFolder) {
              await db.execute(
                  'ALTER TABLE $_tableName ADD COLUMN folder TEXT DEFAULT \'\'');
            }
          } catch (e) {
            debugPrint('Error updating video schema: $e');
          }
        },
      );
    }();
    try {
      await _openDbFuture;
    } catch (_) {
      _openDbFuture = null;
      rethrow;
    }
  }

  /// Imports a video from an in-memory byte list.
  ///
  /// Streams through a temp file into the c2 (CTR) media format, so a fresh
  /// import is born streamable: ExoPlayer can range-request it on the very
  /// first play, with no CBC→CTR conversion wait (the low-end-device
  /// first-play stall). The temp plaintext is securely deleted on every path;
  /// a failed import leaves no orphan blob.
  Future<String> saveVideo(Uint8List bytes, String mimeType, int durationS, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final dest = await _platformService.resolveVaultFile(id);
    final stamp = now.millisecondsSinceEpoch;
    final plainTemp = File(p.join(dest.parent.path, '${id}_import_plain_$stamp'));
    final ctrTemp = File(p.join(dest.parent.path, '${id}_import_ctr_$stamp'));
    await dest.parent.create(recursive: true);

    bool writeSucceeded = false;
    try {
      await plainTemp.writeAsBytes(bytes, flush: true);
      await _crypto.encryptStreamSystemCtr(plainTemp, ctrTemp);
      // Atomic swap in the same directory — a crash mid-import can never
      // leave a half-written blob at the final path.
      await ctrTemp.rename(dest.path);

      final meta = VideoMeta(
        id: id,
        mimeType: mimeType,
        size: bytes.length,
        durationS: durationS,
        createdAt: now,
        originalName: originalName,
      );

      await _saveMeta(meta);
      writeSucceeded = true;
      return id;
    } finally {
      // The import plaintext must never survive, success or failure.
      try {
        if (await plainTemp.exists()) {
          await AutoLock.secureDeleteFile(plainTemp);
        }
      } catch (e) {
        debugPrint('Failed to clean up import plaintext temp $id: $e');
      }
      try {
        if (await ctrTemp.exists()) {
          await ctrTemp.delete();
        }
      } catch (e) {
        debugPrint('Failed to clean up import ctr temp $id: $e');
      }
      if (!writeSucceeded) {
        // A failed import must not leave an orphan blob behind.
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (e) {
          debugPrint('Failed to clean up orphan video file $id: $e');
        }
      }
    }
  }

  /// Imports a video from a plaintext file on disk (gallery picker, batch import).
  ///
  /// Encrypts directly to the c2 (CTR) media format, so a fresh import is born
  /// streamable: ExoPlayer can range-request it on the very first play, with
  /// no CBC→CTR conversion wait (the low-end-device first-play stall). The
  /// source is never the destination, and a failed import leaves no orphan
  /// blob at the final path.
  Future<String> saveVideoFromFile(File src, String mimeType, int? durationS, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final dest = await _platformService.resolveVaultFile(id);
    bool writeSucceeded = false;
    try {
      await _crypto.encryptStreamSystemCtr(src, dest);

      final size = await src.length();

      final meta = VideoMeta(
        id: id,
        mimeType: mimeType,
        size: size,
        durationS: durationS ?? 0,
        createdAt: now,
        originalName: originalName,
      );

      await _saveMeta(meta);
      writeSucceeded = true;
      return id;
    } finally {
      if (!writeSucceeded) {
        try {
          if (await dest.exists()) {
            await dest.delete();
          }
        } catch (e) {
          debugPrint('Failed to clean up orphan video file $id: $e');
        }
      }
    }
  }

  Future<Uint8List?> getVideo(String id) async {
    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;

    Uint8List? decrypted;
    try {
      decrypted = await _crypto.decryptSystem(encrypted);
    } catch (e) {
      return null;
    }

    if (_crypto.isLegacySystemBlob(encrypted)) {
      try {
        final reEncrypted = await _crypto.encryptSystem(decrypted);
        await _platformService.saveEncryptedFile(id, reEncrypted);
      } catch (_) {}
    }
    return decrypted;
  }

  /// F23: true when the blob is already c2 (CTR under the master key). The
  /// thumbnail service asks this BEFORE opening a stream, because
  /// `ensureVideoStreamable` would migrate a legacy blob as a side effect, and
  /// drawing a tile must never kick off a full decrypt/re-encrypt.
  Future<bool> isCtrV2Blob(String id) async {
    final file = await _platformService.resolveVaultFile(id);
    if (!file.existsSync()) return false;
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = Uint8List(8);
      final bytesRead = await raf.readInto(magic);
      if (bytesRead != 8) return false;
      for (int i = 0; i < 8; i++) {
        if (magic[i] != kMediaMagicCtrV2[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  /// Lazily migrates a video blob from CBC (MVKEYv1), legacy, or c1 (system key) to CTR under master key (MVKEYc2)
  /// for future seekable streaming. Conversions from c1 and legacy sources are gated by a plaintext container
  /// sanity check; if the device-local key was regenerated, conversion is skipped leaving the original untouched.
  ///
  /// The whole conversion runs inside an auto-lock protected-operation claim, so
  /// the 1-minute background rule cannot lock the vault and delete these temp
  /// files while they are being written (M35). Every exit path returns a
  /// [VideoMigrationOutcome], so a failure is reported instead of swallowed (H16).
  Future<VideoMigrationOutcome> ensureVideoStreamable(String id) async {
    final startedAt = DateTime.now();
    var stage = VideoMigrationStage.precheck;
    var sourceKind = 'legacy';
    var plaintextBytes = 0;

    VideoMigrationOutcome record({
      required bool converted,
      required VideoMigrationFailure failure,
      VideoMigrationStage? failedAt,
      String? detail,
    }) {
      final outcome = VideoMigrationOutcome(
        videoId: id,
        sourceKind: sourceKind,
        converted: converted,
        failure: failure,
        failedAt: failedAt,
        detail: detail,
        plaintextBytes: plaintextBytes,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      _lastMigrationOutcome = outcome;
      _migrationOutcomes[id] = outcome;
      return outcome;
    }

    final blobFile = await _platformService.resolveVaultFile(id);
    if (!blobFile.existsSync()) {
      sourceKind = 'missing';
      return record(
        converted: false,
        failure: VideoMigrationFailure.io,
        failedAt: stage,
        detail: 'Blob file does not exist',
      );
    }

    // Read the first 8 bytes to check the magic header
    stage = VideoMigrationStage.header;
    final raf = await blobFile.open(mode: FileMode.read);
    try {
      final magic = Uint8List(8);
      final bytesRead = await raf.readInto(magic);
      if (bytesRead == 8) {
        bool isCtrV2 = true;
        bool isCtrV1 = true;
        bool isV1 = true;
        for (int i = 0; i < 8; i++) {
          if (magic[i] != kMediaMagicCtrV2[i]) isCtrV2 = false;
          if (magic[i] != kMediaMagicCtrV1[i]) isCtrV1 = false;
          if (magic[i] != kMediaMagicV1[i]) isV1 = false;
        }
        if (isCtrV2) {
          // Already c2 (CTR under master key) — nothing to do
          sourceKind = 'already-c2';
          return record(converted: true, failure: VideoMigrationFailure.none);
        }
        if (isCtrV1) {
          sourceKind = 'c1';
        } else if (isV1) {
          sourceKind = 'v1';
        }
      }
    } finally {
      await raf.close();
    }

    // Migrate: CBC/legacy/c1 -> plaintext -> c2 (CTR under master key), atomic swap
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final plainTemp = File(p.join(tempDir.path, '${id}_migrate_plain_$ts'));
    final ctrTemp = File(p.join(tempDir.path, '${id}_migrate_ctr_$ts'));

    // M35: hold the protected-operation claim for the entire conversion. Without
    // it, a one-minute trip to the background locks the vault, which clears the
    // keys and lets wipeTransientPlaintext delete exactly these two temp files
    // mid-write. The claim is released in the finally below, on every path.
    AutoLock().beginProtectedOperation();
    try {
      // Step 1: decrypt existing blob to plaintext temp file
      stage = VideoMigrationStage.decrypt;
      await _crypto.decryptStreamSystem(blobFile, plainTemp);
      plaintextBytes = await plainTemp.length();

      // Step 1b: Gate c1 and legacy conversions on plaintext video container sanity check
      if (sourceKind == 'c1' || sourceKind == 'legacy') {
        stage = VideoMigrationStage.containerGate;
        final headRaf = await plainTemp.open(mode: FileMode.read);
        final head = Uint8List(12);
        final headRead = await headRaf.readInto(head);
        await headRaf.close();

        if (headRead < 12 || !looksLikeVideoContainer(head)) {
          debugPrint('ensureVideoStreamable($id) skipped: plaintext did not look like a video');
          return record(
            converted: false,
            failure: VideoMigrationFailure.refusedNotAContainer,
            failedAt: stage,
            detail: 'Plaintext did not match a known video container signature',
          );
        }
      }

      // Step 2: re-encrypt plaintext as c2 (CTR under master key) to a second temp file
      stage = VideoMigrationStage.reencrypt;
      await _crypto.encryptStreamSystemCtr(plainTemp, ctrTemp);

      // Step 3: atomic rename of ctrTemp OVER the original blob
      stage = VideoMigrationStage.rename;
      await ctrTemp.rename(blobFile.path);

      return record(converted: true, failure: VideoMigrationFailure.none);
    } catch (e) {
      // The original blob is never touched on a failure path; report why.
      return record(
        converted: false,
        failure: _classifyMigrationFailure(e),
        failedAt: stage,
        detail: _describeMigrationFailure(e),
      );
    } finally {
      // Whatever happened: the transient plaintext must not survive, and no
      // half-written ciphertext temp may be left behind.
      await AutoLock.secureDeleteFile(plainTemp);
      try {
        if (await ctrTemp.exists()) await ctrTemp.delete();
      } catch (_) {}
      AutoLock().endProtectedOperation();
    }
  }

  /// Names a conversion failure. A lock is detected from the vault's own state
  /// rather than from an exception message, because the message is not a
  /// contract.
  VideoMigrationFailure _classifyMigrationFailure(Object error) {
    if (error is FileSystemException) return VideoMigrationFailure.io;
    if (!_crypto.isUnlocked) return VideoMigrationFailure.vaultLocked;
    return VideoMigrationFailure.unknown;
  }

  /// Describes a conversion failure without leaking where the vault lives.
  /// Several platform exception messages embed an absolute path, so any token
  /// containing a path separator is replaced.
  String _describeMigrationFailure(Object error) {
    final collapsed = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final withoutPaths = collapsed.replaceAll(RegExp(r'\S*[/\\]\S*'), '<path>');
    final bounded = withoutPaths.length > 160
        ? '${withoutPaths.substring(0, 160)}...'
        : withoutPaths;
    final typeName = error.runtimeType.toString();
    return bounded.startsWith(typeName) ? bounded : '$typeName: $bounded';
  }

  Future<void> deleteVideo(String id) async {
    await _platformService.deleteFile(id);
    await _deleteMeta(id);
  }

  Future<List<VideoMeta>> getAllVideos() async {
    if (kIsWeb) {
      final raw = await _platformService.secureRead('vault_videos_meta');
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => VideoMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    await _ensureDb();
    final maps = await _db!.query(_tableName, orderBy: 'createdAt DESC');
    return maps.map((map) => VideoMeta.fromMap(map)).toList();
  }

  Future<void> _saveMeta(VideoMeta meta) async {
    if (kIsWeb) {
      final existing = await getAllVideos();
      existing.removeWhere((m) => m.id == meta.id);
      existing.add(meta);
      await _platformService.secureWrite(
        'vault_videos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.insert(_tableName, meta.toMap());
  }

  Future<void> _deleteMeta(String id) async {
    if (kIsWeb) {
      final existing = await getAllVideos();
      existing.removeWhere((m) => m.id == id);
      await _platformService.secureWrite(
        'vault_videos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Folder feature: relabels one video's folder ('' = Unfiled). Filter-only —
  /// the encrypted blob is untouched; only the metadata row is rewritten.
  /// Mirrors DocumentVaultService.moveDocument.
  Future<void> moveVideo(String id, String folder) async {
    if (kIsWeb) {
      final existing = await getAllVideos();
      final index = existing.indexWhere((m) => m.id == id);
      if (index == -1) return;
      existing[index] = existing[index].copyWith(folder: folder);
      await _platformService.secureWrite(
        'vault_videos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }
    await _ensureDb();
    final maps = await _db!.query(_tableName, where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return;
    final updated =
        VideoMeta.fromMap(maps.single).copyWith(folder: folder);
    await _db!.update(_tableName, updated.toMap(),
        where: 'id = ?', whereArgs: [id]);
  }

  /// Closes the cached SQLite connection and resets the lazy-open state, so
  /// the next call reopens a fresh database instead of serving rows from a
  /// file that no longer exists. Mirrors FileVaultService.closeDatabase —
  /// this is what made videos survive Clear All Data in-session.
  Future<void> closeDatabase() async {
    final db = _db;
    _db = null;
    _openDbFuture = null;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  /// Danger Zone → Clear All Data support. Removes THIS vault's video store:
  /// on mobile the metadata database and every SQLite sidecar file, on web the
  /// per-blob entries plus the metadata key. The mobile encrypted blobs in the
  /// shared `vault_files/` directory are purged by [VaultWipeService]; web
  /// blobs live behind the platform service and are deleted per id here.
  /// Access state (PIN, keystore, recovery, duress) is never touched.
  Future<void> wipeAllData() async {
    if (kIsWeb) {
      try {
        for (final meta in await getAllVideos()) {
          try {
            await _platformService.deleteFile(meta.id);
          } catch (_) {}
        }
      } catch (_) {}
    } else {
      await closeDatabase();
      try {
        final dbPath = p.join(await getDatabasesPath(), _dbName);
        for (final suffix in const ['', '-journal', '-wal', '-shm']) {
          final artifact = File('$dbPath$suffix');
          if (await artifact.exists()) {
            await artifact.delete();
          }
        }
      } catch (_) {}
    }
    try {
      await _platformService.secureDelete('vault_videos_meta');
    } catch (_) {}
  }

  Future<({List<String> successfulIds, int totalAttempted, bool stoppedEarly, String? failedFileName, Object? error, bool originalsKept})> pickAndEncryptVideo(BuildContext context, {void Function(int index, int positionOneBased, String name)? onFileStart, void Function(int index)? onFileSaved, void Function()? onWaitingDeleteConfirm, void Function(int total)? onPicked, void Function(int index, String detail)? onFileFailed, bool Function()? isCancelled}) async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        requestType: RequestType.video,
      ),
    );
    if (assets == null || assets.isEmpty) {
      return (successfulIds: <String>[], totalAttempted: 0, stoppedEarly: false, failedFileName: null, error: null, originalsKept: false);
    }

    // The picker just reported the batch size, so the live import card can list
    // the whole queue ("Importing 1/5 ..." with the rest 'Queued') before the
    // first file even starts encrypting.
    try {
      onPicked?.call(assets.length);
    } catch (_) {}

    final savedIds = <String>[];
    bool stoppedEarly = false;
    String? failedFileName;
    Object? failureError;

    for (var i = 0; i < assets.length; i++) {
      // Cancellation only stops the NEXT file: the one in flight always
      // finishes, so the vault never holds a partial entry. Unreached files
      // stay queued; the screen's finalization sweep labels them 'Cancelled'.
      // The batch-delete phase below is naturally skipped on cancel, because
      // savedIds.length no longer equals the batch size — cancelling never
      // pops the OS delete dialog, and saved originals stay on the device
      // (rows honestly read 'Saved, original kept').
      if (isCancelled != null && isCancelled()) break;
      final asset = assets[i];
      try {
        // Live import card: announce each file BEFORE its encrypt pass, so a
        // 2:34 video shows "Encrypting 1/1 ..." instead of a dead screen.
        try {
          onFileStart?.call(i, i + 1, asset.title ?? 'video');
        } catch (_) {}
        final file = await asset.originFile;
        if (file == null) {
          // No readable source: this row is DONE, and it is done
          // unsuccessfully. It is reported by its own index so the live card
          // keeps every label attached to the right file — the caller cannot
          // derive this from the successfulIds count, because a skipped file
          // shifts that count away from the row order.
          try {
            onFileFailed?.call(i, 'File unavailable');
          } catch (_) {}
          continue;
        }
        final name = asset.title;
        final mime = await asset.mimeTypeAsync ?? 'video/mp4';
        final durationS = asset.duration;
        final id = await saveVideoFromFile(file, mime, durationS, originalName: name);
        savedIds.add(id);
        try {
          onFileSaved?.call(i);
        } catch (_) {}
      } catch (e) {
        stoppedEarly = true;
        failedFileName = asset.title ?? 'video';
        failureError = e;
        try {
          // Deliberately a fixed string, never `e`: a failure detail must not
          // leak a filesystem path to the screen (see the T15 test).
          onFileFailed?.call(i, 'Import failed');
        } catch (_) {}
        debugPrint('pickAndEncryptVideo failed on $failedFileName: $e');
        break;
      }
    }

    // Originals stay on the device unless the OS confirms every delete: the
    // user can deny the system dialog, the platform can refuse, or the whole
    // delete phase is skipped when a file failed earlier. The card reports
    // that truth per row instead of always claiming 'Saved'.
    bool originalsKept = true;
    if (savedIds.length == assets.length) {
      // The OS delete-confirmation dialog carries no progress of its own, so
      // the card names this wait explicitly. One call covers the dialog AND
      // the delete pass the OS runs after "Allow" — there is no observable
      // boundary between the two, so one honest label covers both.
      try {
        onWaitingDeleteConfirm?.call();
      } catch (_) {}
      try {
        final deletedIds = await PhotoManager.editor.deleteWithIds(assets.map((a) => a.id).toList());
        if (deletedIds.length >= assets.length) originalsKept = false;
        if (deletedIds.length < assets.length && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Original videos kept on device.')),
          );
        }
      } catch (e) {
        debugPrint('Gallery deletion failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gallery deletion failed.')),
          );
        }
      }
    }

    return (
      successfulIds: savedIds,
      totalAttempted: assets.length,
      stoppedEarly: stoppedEarly,
      failedFileName: failedFileName,
      error: failureError,
      originalsKept: originalsKept,
    );
  }

  /// Restores a video: decrypts the blob straight to a transient temp file
  /// (STREAMED — a multi-GB video is never held in RAM), writes it into the
  /// system gallery via photo_manager, and ONLY after the gallery confirms
  /// the write removes the vault copy. Same no-loss/no-silent-duplicate
  /// contract as restorePhotoToGallery.
  ///
  /// 2026-09-18 (F26 follow-up): the old path decrypted the ENTIRE video into
  /// memory first (`getVideo` -> one byte list) and showed nothing while it
  /// ran, so a 1-3 GB restore was minutes of a dead screen — exactly the
  /// complaint F4's import pill was built to answer for imports. This version
  /// streams the decrypt through the format-routing stream decryptor into the
  /// temp file and reports progress through [onProgress]: a 0..1 percent
  /// while the temp file grows (measured off the file, never invented) and
  /// null once the gallery write starts, because that OS-side copy has no
  /// observable percent (NN/g: percent-done for waits >= 10 s; visibility of
  /// system status always; never fake a percent).
  ///
  /// The temp plaintext lives in `vault_share` — the directory auto-lock's
  /// wipeTransientPlaintext already secure-wipes on lock — and the whole
  /// restore holds the auto-lock protected-operation claim, so a background
  /// trip cannot lock the vault mid-restore and wipe the plaintext half-way
  /// (the M35 rule, applied to this flow).
  Future<void> restoreVideoToGallery(
    String id, {
    void Function(double? progress)? onProgress,
    bool Function()? isCancelled,
    @visibleForTesting Duration progressPollInterval =
        const Duration(milliseconds: 150),
  }) async {
    // The pill's Cancel is a real stop, not just a between-files stop: the
    // streamed decrypt polls [isCancelled] and is killed mid-file, so a
    // cancel during the long decrypt phase leaves the vault copy and the
    // gallery BOTH untouched. The flag is re-checked after the decrypt and
    // before the gallery write; once that opaque OS copy starts the file is
    // committed, and cancel then applies to the remaining files.
    if (isCancelled != null && isCancelled()) {
      throw const OperationCancelledException();
    }
    final videos = await getAllVideos();
    final video = videos.firstWhere(
      (v) => v.id == id,
      orElse: () => throw Exception('Video metadata not found in vault'),
    );
    final originalName = video.originalName ?? '$id.mp4';

    final tempDir = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tempDir.path, 'vault_share'));
    if (!shareDir.existsSync()) shareDir.createSync(recursive: true);
    final tempFile = File(p.join(shareDir.path, originalName));

    // The metadata size IS the plaintext size — exactly what the streamed
    // decrypt writes — so it is the right percent denominator. Absent/zero
    // means the percent cannot be measured and stays null (honest default).
    final expectedBytes = video.size;

    AutoLock().beginProtectedOperation();
    try {
      onProgress?.call(expectedBytes > 0 ? 0.0 : null);

      var streamed = false;
      if (!kIsWeb) {
        try {
          final srcBlob = await _platformService.resolveVaultFile(id);
          if (srcBlob.existsSync()) {
            // Poll the temp file's length while the decrypt runs. A small
            // video may finish between two polls; that is fine — the
            // percent-less save-phase callback still fires below, so the UI
            // never sits at a frozen bar believing the work stalled.
            Timer? poll;
            if (onProgress != null && expectedBytes > 0) {
              poll = Timer.periodic(progressPollInterval, (_) async {
                try {
                  if (await tempFile.exists()) {
                    final len = await tempFile.length();
                    onProgress((len / expectedBytes).clamp(0.0, 0.99));
                  }
                } catch (_) {
                  // A transient read failure says nothing about the
                  // decrypt; the next tick simply tries again.
                }
              });
            }
            try {
              await _crypto.decryptStreamSystem(srcBlob, tempFile,
                  shouldAbort: isCancelled);
              streamed = true;
            } finally {
              poll?.cancel();
            }
          }
        } on OperationCancelledException {
          // The decrypt was killed by the user's Cancel. Rethrow: falling
          // through to the whole-file fallback below would restart the
          // ENTIRE decrypt in RAM — exactly what the user asked to stop.
          // The partial temp plaintext is secure-deleted in the finally
          // below; the vault copy and the gallery are both untouched.
          rethrow;
        } catch (_) {
          // Unresolvable path or decrypt failure: fall through to the
          // in-memory fallback below, which is the pre-streaming behavior
          // and reports its own honest failures. The vault copy is intact
          // either way.
        }
      }

      if (!streamed) {
        // Web and fallback path: the old whole-file behavior.
        final bytes = await getVideo(id);
        if (bytes == null) throw Exception('Video file not found in vault');
        await tempFile.writeAsBytes(bytes);
      }

      // The decrypt finished, but a cancel pressed while it ran must still
      // stop the restore BEFORE anything reaches the gallery: the decrypted
      // work is discarded, the temp plaintext is wiped below, and the vault
      // copy stays. (Past this point the file is committed.)
      if (isCancelled != null && isCancelled()) {
        throw const OperationCancelledException();
      }

      // Gallery write: no measurable percent — report the indeterminate
      // phase so the UI switches from "45%" to "Saving to gallery…" instead
      // of a bar that appears to have stalled.
      onProgress?.call(null);

      // photo_manager 3.9.0 (the pinned plugin) has saveVideo return a
      // NON-NULLABLE Future<AssetEntity> and report a refusal by throwing,
      // so "the gallery refused" is a catch branch — a null return is
      // impossible and would have been dead code here.
      try {
        await PhotoManager.editor.saveVideo(
          tempFile,
          title: originalName,
        );
      } catch (_) {
        // Gallery refused — nothing left the vault. Say so instead of
        // surfacing a raw plugin error.
        throw Exception('The gallery did not accept the video. The vault copy was kept.');
      }
      try {
        await deleteVideo(id);
      } catch (_) {
        // Plaintext now exists in the gallery AND the vault. The user must
        // know both copies exist — a silent duplicate defeats the vault.
        throw Exception(
            'Video was saved to the gallery, but the vault copy could not be deleted. Delete it from the vault manually.');
      }
    } finally {
      AutoLock().endProtectedOperation();
      // Secure-delete the transient plaintext (overwrite-before-delete),
      // matching the AutoLock standard used for every other temp plaintext.
      await AutoLock.secureDeleteFile(tempFile);
    }
  }

  Future<void> restoreVideos(List<dynamic> decodedVideos) async {
    if (kIsWeb) return;
    await _ensureDb();
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName(
        id TEXT PRIMARY KEY,
        mimeType TEXT,
        size INTEGER,
        durationS INTEGER,
        createdAt TEXT,
        originalName TEXT,
        folder TEXT DEFAULT ''
      )
    ''');
    // Folder feature: pre-folder installs may have the table without the
    // column (IF NOT EXISTS above is a no-op then); PRAGMA-migrate it.
    final columns = await _db!.rawQuery('PRAGMA table_info($_tableName)');
    if (!columns.any((column) => column['name'] == 'folder')) {
      await _db!.execute("ALTER TABLE $_tableName ADD COLUMN folder TEXT DEFAULT ''");
    }
    await _db!.delete(_tableName);
    for (final video in decodedVideos) {
      final map = Map<String, dynamic>.from(video);
      await _db!.insert(_tableName, map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

final videoVaultServiceProvider = Provider<VideoVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return VideoVaultService(platformService, crypto);
});
