// lib/vault/services/video_vault_service.dart
import 'dart:convert';
import 'dart:io';

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

  VideoVaultService(this._platformService, this._crypto);

  Future<void> _ensureDb() async {
    if (kIsWeb) return;
    _db ??= await openDatabase(
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

  Future<Uint8List?> getVideo(String id) async {
    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;
    return await _crypto.decryptSystem(encrypted);
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

  Future<List<String>> pickAndEncryptVideo(BuildContext context) async {
    try {
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          requestType: RequestType.video,
        ),
      );
      if (assets == null || assets.isEmpty) return [];

      final savedIds = <String>[];
      for (final asset in assets) {
        final file = await asset.originFile;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final name = asset.title;
        final mime = await asset.mimeTypeAsync ?? 'video/mp4';
        final durationS = asset.duration;
        final id = await saveVideo(bytes, mime, durationS, originalName: name);
        savedIds.add(id);
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
      return savedIds;
    } catch (e) {
      debugPrint('pickAndEncryptVideo failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import videos: $e')),
        );
      }
      return [];
    }
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
}

final videoVaultServiceProvider = Provider<VideoVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return VideoVaultService(platformService, crypto);
});
