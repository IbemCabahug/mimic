// mimic/lib/vault/services/file_vault_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

class PhotoMeta {
  final String id;
  final String mimeType;
  final int size;
  final DateTime createdAt;

  PhotoMeta({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mimeType': mimeType,
        'size': size,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PhotoMeta.fromMap(Map<String, dynamic> map) => PhotoMeta(
        id: map['id'] as String,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
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
            createdAt TEXT
          )
        ''');
      },
    );
  }

  Future<void> saveFile(String filename, Uint8List bytes) async {
    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(filename, encrypted);
  }

  Future<Uint8List?> readFile(String filename) async {
    final encrypted = await _platformService.readEncryptedFile(filename);
    if (encrypted == null) return null;
    return await _crypto.decryptSystem(encrypted);
  }

  Future<String> savePhoto(Uint8List bytes, String mimeType) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final meta = PhotoMeta(
      id: id,
      mimeType: mimeType,
      size: bytes.length,
      createdAt: now,
    );

    await _saveMeta(meta);
    return id;
  }

  Future<Uint8List?> getPhoto(String id) async {
    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;
    return await _crypto.decryptSystem(encrypted);
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
    final maps = await _db!.query(_tableName, orderBy: 'createdAt DESC');
    return maps.map((map) => PhotoMeta.fromMap(map)).toList();
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

  Future<String?> pickAndEncryptImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final id = await savePhoto(bytes, picked.mimeType ?? 'image/jpeg');
      return id;
    } catch (e) {
      debugPrint('pickAndEncryptImage failed: $e');
      return null;
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
      final id = await savePhoto(bytes, picked.mimeType ?? 'image/jpeg');
      return id;
    } catch (e) {
      debugPrint('captureAndEncryptImage failed: $e');
      return null;
    }
  }
}

final fileVaultServiceProvider = Provider<FileVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return FileVaultService(platformService, crypto);
});
