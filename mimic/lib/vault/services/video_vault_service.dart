// lib/vault/services/video_vault_service.dart
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

  VideoMeta({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.durationS,
    required this.createdAt,
    this.originalName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mimeType': mimeType,
        'size': size,
        'durationS': durationS,
        'createdAt': createdAt.toIso8601String(),
        'originalName': originalName,
      };

  factory VideoMeta.fromMap(Map<String, dynamic> map) => VideoMeta(
        id: map['id'] as String,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        durationS: map['durationS'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        originalName: map['originalName'] as String?,
      );
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
              originalName TEXT
            )
          ''');
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

  Future<String> saveVideo(Uint8List bytes, String mimeType, int durationS, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final meta = VideoMeta(
      id: id,
      mimeType: mimeType,
      size: bytes.length,
      durationS: durationS,
      createdAt: now,
      originalName: originalName,
    );

    await _saveMeta(meta);
    return id;
  }

  Future<String> saveVideoFromFile(File src, String mimeType, int? durationS, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final dest = await _platformService.resolveVaultFile(id);
    bool writeSucceeded = false;
    try {
      await _crypto.encryptStreamSystem(src, dest);

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

  /// Lazily migrates a video blob from CBC (MVKEYv1), legacy, or c1 (system key) to CTR under master key (MVKEYc2)
  /// for future seekable streaming. Conversions from c1 and legacy sources are gated by a plaintext container
  /// sanity check; if the device-local key was regenerated, conversion is skipped leaving the original untouched.
  Future<void> ensureVideoStreamable(String id) async {
    final blobFile = await _platformService.resolveVaultFile(id);
    if (!blobFile.existsSync()) return;

    String sourceKind = 'legacy';

    // Read the first 8 bytes to check the magic header
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
        if (isCtrV2) return; // Already c2 (CTR under master key) — nothing to do
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

    try {
      // Step 1: decrypt existing blob to plaintext temp file
      await _crypto.decryptStreamSystem(blobFile, plainTemp);

      // Step 1b: Gate c1 and legacy conversions on plaintext video container sanity check
      if (sourceKind == 'c1' || sourceKind == 'legacy') {
        final headRaf = await plainTemp.open(mode: FileMode.read);
        final head = Uint8List(12);
        final headRead = await headRaf.readInto(head);
        await headRaf.close();

        if (headRead < 12 || !looksLikeVideoContainer(head)) {
          debugPrint('ensureVideoStreamable($id) skipped: plaintext did not look like a video');
          await AutoLock.secureDeleteFile(plainTemp);
          try { if (await ctrTemp.exists()) await ctrTemp.delete(); } catch (_) {}
          return;
        }
      }

      // Step 2: re-encrypt plaintext as c2 (CTR under master key) to a second temp file
      await _crypto.encryptStreamSystemCtr(plainTemp, ctrTemp);

      // Step 3: atomic rename of ctrTemp OVER the original blob
      await ctrTemp.rename(blobFile.path);

      // Step 4: clean up plaintext temp
      await AutoLock.secureDeleteFile(plainTemp);
    } catch (_) {
      // Best-effort: clean up temps, leave original blob untouched
      await AutoLock.secureDeleteFile(plainTemp);
      try { if (await ctrTemp.exists()) await ctrTemp.delete(); } catch (_) {}
    }
  }

  Future<File?> getVideoToTempFile(String id) async {
    final srcBlob = await _platformService.resolveVaultFile(id);
    if (!srcBlob.existsSync()) return null;

    // Best-effort lazy migration to CTR; failure never blocks playback
    try {
      await ensureVideoStreamable(id);
    } catch (_) {}

    final tempDir = await getTemporaryDirectory();
    final playbackDir = Directory(p.join(tempDir.path, 'vault_playback'));
    if (!playbackDir.existsSync()) {
      playbackDir.createSync(recursive: true);
    }
    
    final tempFile = File(p.join(playbackDir.path, '${id}_play.mp4'));
    
    try {
      await _crypto.decryptStreamSystem(srcBlob, tempFile);
      return tempFile;
    } catch (e) {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      return null;
    }
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

  Future<({List<String> successfulIds, int totalAttempted, bool stoppedEarly, String? failedFileName, Object? error})> pickAndEncryptVideo(BuildContext context) async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        requestType: RequestType.video,
      ),
    );
    if (assets == null || assets.isEmpty) {
      return (successfulIds: <String>[], totalAttempted: 0, stoppedEarly: false, failedFileName: null, error: null);
    }

    final savedIds = <String>[];
    bool stoppedEarly = false;
    String? failedFileName;
    Object? failureError;

    for (final asset in assets) {
      try {
        final file = await asset.originFile;
        if (file == null) continue;
        final name = asset.title;
        final mime = await asset.mimeTypeAsync ?? 'video/mp4';
        final durationS = asset.duration;
        final id = await saveVideoFromFile(file, mime, durationS, originalName: name);
        savedIds.add(id);
      } catch (e) {
        stoppedEarly = true;
        failedFileName = asset.title ?? 'video';
        failureError = e;
        debugPrint('pickAndEncryptVideo failed on $failedFileName: $e');
        break;
      }
    }

    if (savedIds.length == assets.length) {
      try {
        final deletedIds = await PhotoManager.editor.deleteWithIds(assets.map((a) => a.id).toList());
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
    );
  }

  Future<void> restoreVideoToGallery(String id) async {
    final bytes = await getVideo(id);
    if (bytes == null) throw Exception('Video file not found in vault');

    final videos = await getAllVideos();
    final video = videos.firstWhere((v) => v.id == id);
    final originalName = video.originalName ?? '$id.mp4';

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, originalName));
    try {
      await tempFile.writeAsBytes(bytes);
      await PhotoManager.editor.saveVideo(
        tempFile,
        title: originalName,
      );
      await deleteVideo(id);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
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
        originalName TEXT
      )
    ''');
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
