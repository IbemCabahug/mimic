// mimic/lib/vault/services/file_vault_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

class PhotoMeta {
  final String id;
  final String mimeType;
  final int size;
  final DateTime createdAt;
  final String? originalName;

  PhotoMeta({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    this.originalName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mimeType': mimeType,
        'size': size,
        'createdAt': createdAt.toIso8601String(),
        'originalName': originalName,
      };

  factory PhotoMeta.fromMap(Map<String, dynamic> map) => PhotoMeta(
        id: map['id'] as String,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        originalName: map['originalName'] as String?,
      );
}

class FileVaultService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _dbName = 'vault_files.db';
  static const String _tableName = 'photos';
  Database? _db;

  FileVaultService(this._platformService, this._crypto);

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
            createdAt TEXT,
            originalName TEXT
          )
        ''');
      },
    );
    try {
      final List<Map<String, dynamic>> columns = await _db!.rawQuery("PRAGMA table_info($_tableName)");
      final hasOriginalName = columns.any((column) => column['name'] == 'originalName');
      if (!hasOriginalName) {
        await _db!.execute("ALTER TABLE $_tableName ADD COLUMN originalName TEXT");
      }
    } catch (e) {
      debugPrint('Error updating schema: $e');
    }
  }

  Future<void> saveFile(String filename, Uint8List bytes) async {
    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(filename, encrypted);
  }

  Future<Uint8List?> readFile(String id) async {
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

  Future<String> savePhoto(Uint8List bytes, String mimeType, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final meta = PhotoMeta(
      id: id,
      mimeType: mimeType,
      size: bytes.length,
      createdAt: now,
      originalName: originalName,
    );

    await _saveMeta(meta);
    return id;
  }

  Future<Uint8List?> getPhoto(String id) async {
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

  Future<void> deletePhoto(String id) async {
    await _platformService.deleteFile(id);
    await _deleteMeta(id);
  }

  Future<List<PhotoMeta>> getAllPhotos() async {
    if (kIsWeb) {
      final raw = await _platformService.secureRead('vault_photos_meta');
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => PhotoMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    await _ensureDb();
    try {
      final maps = await _db!.query(_tableName, orderBy: 'createdAt DESC');
      return maps.map((map) => PhotoMeta.fromMap(map)).toList();
    } catch (e) {
      if (e is DatabaseException && e.toString().contains('database_closed')) {
        _db = null;
        await _ensureDb();
        final maps = await _db!.query(_tableName, orderBy: 'createdAt DESC');
        return maps.map((map) => PhotoMeta.fromMap(map)).toList();
      }
      rethrow;
    }
  }

  Future<void> _saveMeta(PhotoMeta meta) async {
    if (kIsWeb) {
      final existing = await getAllPhotos();
      existing.removeWhere((m) => m.id == meta.id);
      existing.add(meta);
      await _platformService.secureWrite(
        'vault_photos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.insert(_tableName, meta.toMap());
  }

  Future<void> _deleteMeta(String id) async {
    if (kIsWeb) {
      final existing = await getAllPhotos();
      existing.removeWhere((m) => m.id == id);
      await _platformService.secureWrite(
        'vault_photos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> pickAndEncryptImage(BuildContext context) async {
    try {
      final List<AssetEntity>? assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: const AssetPickerConfig(
          requestType: RequestType.image,
        ),
      );
      if (assets == null || assets.isEmpty) return [];

      final savedIds = <String>[];
      for (final asset in assets) {
        final file = await asset.originFile;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final name = asset.title;
        final mime = await asset.mimeTypeAsync ?? 'image/jpeg';
        final id = await savePhoto(bytes, mime, originalName: name);
        savedIds.add(id);
      }

      if (savedIds.length == assets.length) {
        try {
          final deletedIds = await PhotoManager.editor.deleteWithIds(assets.map((a) => a.id).toList());
          if (deletedIds.length < assets.length && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Original photos kept on device.')),
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
      debugPrint('pickAndEncryptImage failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import photos: $e')),
        );
      }
      return [];
    }
  }

  Future<String?> captureAndEncryptImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final id = await savePhoto(bytes, picked.mimeType ?? 'image/jpeg', originalName: p.basename(picked.path));
      return id;
    } catch (e) {
      debugPrint('captureAndEncryptImage failed: $e');
      return null;
    }
  }

  Future<void> restorePhotoToGallery(String id) async {
    final bytes = await getPhoto(id);
    if (bytes == null) throw Exception('Photo file not found in vault');

    final photos = await getAllPhotos();
    final photo = photos.firstWhere((p) => p.id == id);
    final originalName = photo.originalName ?? '$id.jpg';

    await PhotoManager.editor.saveImage(
      bytes,
      filename: originalName,
    );
    await deletePhoto(id);
  }

  Future<void> restorePhotos(List<dynamic> decodedPhotos) async {
    if (kIsWeb) return;
    await _ensureDb();
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName(
        id TEXT PRIMARY KEY,
        mimeType TEXT,
        size INTEGER,
        createdAt TEXT,
        originalName TEXT
      )
    ''');
    await _db!.delete(_tableName);
    for (final photo in decodedPhotos) {
      final map = Map<String, dynamic>.from(photo);
      await _db!.insert(_tableName, map, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

final fileVaultServiceProvider = Provider<FileVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return FileVaultService(platformService, crypto);
});
