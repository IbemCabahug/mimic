// lib/vault/services/notes_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

class Note {
  final String id;
  final String title;
  final String encryptedBody;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.encryptedBody,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'encryptedBody': encryptedBody,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String,
        encryptedBody: json['encryptedBody'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class NotesService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _webKey = 'vault_notes';
  Database? _db;
  Future<void>? _openDbFuture;

  int _openCount = 0;

  @visibleForTesting
  int get openCount => _openCount;

  NotesService(this._platformService, this._crypto);

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
        p.join(await getDatabasesPath(), 'vault_notes.db'),
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
    }();
    try {
      await _openDbFuture;
    } catch (_) {
      _openDbFuture = null;
      rethrow;
    }
  }

  Future<void> addNote(Note note) async {
    final encryptedBody = _crypto.encryptString(note.encryptedBody);

    if (kIsWeb) {
      final notes = await _getWebNotes();
      notes.add({
        'id': note.id,
        'title': note.title,
        'encryptedBody': encryptedBody,
        'createdAt': note.createdAt.toIso8601String(),
        'updatedAt': note.updatedAt.toIso8601String(),
      });
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.insert('notes', {
      'id': note.id,
      'title': note.title,
      'encryptedBody': encryptedBody,
      'created_at': note.createdAt.toIso8601String(),
      'updated_at': note.updatedAt.toIso8601String(),
    });
  }

  Future<void> updateNote(Note note) async {
    final encryptedBody = _crypto.encryptString(note.encryptedBody);

    if (kIsWeb) {
      final notes = await _getWebNotes();
      final index = notes.indexWhere((n) => n['id'] == note.id);
      if (index != -1) {
        notes[index] = {
          'id': note.id,
          'title': note.title,
          'encryptedBody': encryptedBody,
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
        };
      }
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.update(
      'notes',
      {
        'title': note.title,
        'encryptedBody': encryptedBody,
        'updated_at': note.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(String id) async {
    if (kIsWeb) {
      final notes = await _getWebNotes();
      notes.removeWhere((n) => n['id'] == id);
      await _platformService.secureWrite(_webKey, jsonEncode(notes));
      return;
    }

    await _ensureDb();
    await _db!.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// Closes the cached SQLite connection and resets the lazy-open state, so
  /// the next call reopens a fresh database instead of serving rows from a
  /// file that no longer exists. Mirrors FileVaultService.closeDatabase —
  /// this is what made notes survive Clear All Data in-session (the old
  /// dialog deleted the WEB-ONLY `vault_notes` key, while the device notes
  /// live in `vault_notes.db`).
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

  /// Danger Zone → Clear All Data support. Removes the notes store: on mobile
  /// the `vault_notes.db` database and every SQLite sidecar file, and the
  /// `vault_notes` metadata key everywhere (web store / legacy key). Notes
  /// have no blob files. Access state is never touched.
  Future<void> wipeAllData() async {
    if (!kIsWeb) {
      await closeDatabase();
      try {
        final dbPath = p.join(await getDatabasesPath(), 'vault_notes.db');
        for (final suffix in const ['', '-journal', '-wal', '-shm']) {
          final artifact = File('$dbPath$suffix');
          if (await artifact.exists()) {
            await artifact.delete();
          }
        }
      } catch (_) {}
    }
    try {
      await _platformService.secureDelete(_webKey);
    } catch (_) {}
  }

  Future<List<Note>> getAllNotes() async {
    if (kIsWeb) {
      final notes = await _getWebNotes();
      return notes.map((n) {
        String decrypted = '';
        try {
          decrypted = _crypto.decryptString(n['encryptedBody'] as String);
        } catch (_) {}
        return Note(
          id: n['id'] as String,
          title: n['title'] as String,
          encryptedBody: decrypted,
          createdAt: DateTime.parse(n['createdAt'] as String),
          updatedAt: DateTime.parse(n['updatedAt'] as String),
        );
      }).toList();
    }

    await _ensureDb();
    List<Map<String, dynamic>> maps;
    try {
      maps = await _db!.query('notes', orderBy: 'updated_at DESC');
    } catch (e) {
      if (e is DatabaseException && e.toString().contains('database_closed')) {
        _db = null;
        await _ensureDb();
        maps = await _db!.query('notes', orderBy: 'updated_at DESC');
      } else {
        rethrow;
      }
    }

    return maps.map((map) {
      String decrypted = '';
      try {
        decrypted = _crypto.decryptString(map['encryptedBody'] as String);
      } catch (_) {}
      return Note(
        id: map['id'] as String,
        title: map['title'] as String,
        encryptedBody: decrypted,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _getWebNotes() async {
    final raw = await _platformService.secureRead(_webKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return List<Map<String, dynamic>>.from(decoded);
  }

  Future<void> restoreNotes(List<dynamic> decodedNotes) async {
    if (kIsWeb) return;
    await _ensureDb();
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS notes(
        id TEXT PRIMARY KEY,
        title TEXT,
        encryptedBody TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await _db!.delete('notes');
    for (final note in decodedNotes) {
      final map = Map<String, dynamic>.from(note);
      final dbMap = {
        'id': map['id'],
        'title': map['title'],
        'encryptedBody': map['encryptedBody'],
        'created_at': map['createdAt'],
        'updated_at': map['updatedAt'],
      };
      await _db!.insert('notes', dbMap, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

final notesServiceProvider = Provider<NotesService>((ref) {
  return NotesService(ref.read(platformServiceProvider), ref.read(vaultCryptoProvider));
});
