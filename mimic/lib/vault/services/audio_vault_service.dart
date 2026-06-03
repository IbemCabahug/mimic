// lib/vault/services/audio_vault_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

class AudioMeta {
  final String id;
  final String title;
  final int durationMs;
  final String mimeType;
  final int size;
  final DateTime createdAt;

  AudioMeta({
    required this.id,
    required this.title,
    required this.durationMs,
    required this.mimeType,
    required this.size,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'durationMs': durationMs,
        'mimeType': mimeType,
        'size': size,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AudioMeta.fromMap(Map<String, dynamic> map) => AudioMeta(
        id: map['id'] as String,
        title: map['title'] as String,
        durationMs: map['durationMs'] as int,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

class AudioVaultService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _dbName = 'vault_audio.db';
  static const String _tableName = 'audio';
  Database? _db;

  AudioVaultService(this._platformService, this._crypto);

  Future<void> _ensureDb() async {
    if (kIsWeb) return;
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName(
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
  }

  Future<String> saveAudio(Uint8List bytes, String mimeType, {String? title, int? durationMs}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final encrypted = _crypto.encrypt(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final meta = AudioMeta(
      id: id,
      title: title ?? 'Recording ${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      durationMs: durationMs ?? 0,
      mimeType: mimeType,
      size: bytes.length,
      createdAt: now,
    );

    await _saveMeta(meta);
    return id;
  }

  Future<Uint8List?> getAudio(String id) async {
    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;
    return _crypto.decrypt(encrypted);
  }

  Future<void> deleteAudio(String id) async {
    await _platformService.deleteFile(id);
    await _deleteMeta(id);
  }

  Future<List<AudioMeta>> getAllAudio() async {
    if (kIsWeb) {
      final raw = await _platformService.secureRead('vault_audio_meta');
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => AudioMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }

    await _ensureDb();
    final maps = await _db!.query(_tableName, orderBy: 'createdAt DESC');
    return maps.map((map) => AudioMeta.fromMap(map)).toList();
  }

  Future<void> _saveMeta(AudioMeta meta) async {
    if (kIsWeb) {
      final existing = await getAllAudio();
      existing.removeWhere((m) => m.id == meta.id);
      existing.add(meta);
      await _platformService.secureWrite(
        'vault_audio_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.insert(_tableName, meta.toMap());
  }

  Future<void> _deleteMeta(String id) async {
    if (kIsWeb) {
      final existing = await getAllAudio();
      existing.removeWhere((m) => m.id == id);
      await _platformService.secureWrite(
        'vault_audio_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }

    await _ensureDb();
    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }
}

final audioVaultServiceProvider = Provider<AudioVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return AudioVaultService(platformService, crypto);
});
