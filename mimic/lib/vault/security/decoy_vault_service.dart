// mimic/lib/vault/security/decoy_vault_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_kdf.dart';
import '../services/pro_status_service.dart';

/// Stock Decoy Photo item representing benign, plausible private media.
class DecoyPhoto {
  final String id;
  final String title;
  final String caption;
  final List<String> tags;
  final int colorValue;
  final DateTime createdAt;

  const DecoyPhoto({
    required this.id,
    required this.title,
    this.caption = '',
    this.tags = const [],
    this.colorValue = 0xFF4A6572,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'caption': caption,
        'tags': tags,
        'colorValue': colorValue,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory DecoyPhoto.fromMap(Map<String, dynamic> map) => DecoyPhoto(
        id: map['id'] as String,
        title: map['title'] as String? ?? 'Photo',
        caption: map['caption'] as String? ?? '',
        tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        colorValue: (map['colorValue'] as int?) ?? 0xFF4A6572,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

/// Stock Decoy Note item representing ordinary daily notes.
class DecoyNote {
  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;

  const DecoyNote({
    required this.id,
    required this.title,
    required this.content,
    this.tags = const [],
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'tags': tags,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory DecoyNote.fromMap(Map<String, dynamic> map) => DecoyNote(
        id: map['id'] as String,
        title: map['title'] as String? ?? 'Note',
        content: map['content'] as String? ?? '',
        tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          map['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

/// Stock Decoy Document item representing plausible everyday records.
class DecoyDocument {
  final String id;
  final String name;
  final int fileSize;
  final List<String> tags;
  final DateTime updatedAt;

  const DecoyDocument({
    required this.id,
    required this.name,
    required this.fileSize,
    this.tags = const [],
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'fileSize': fileSize,
        'tags': tags,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory DecoyDocument.fromMap(Map<String, dynamic> map) => DecoyDocument(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Document',
        fileSize: (map['fileSize'] as int?) ?? 102400,
        tags: (map['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          map['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

/// Service managing the secondary Decoy PIN ("Ghost Album") and harmless stock content.
/// Completely cryptographically isolated from the user's primary DEK and encrypted databases.
class DecoyVaultService {
  static const String _pinHashKey = 'decoy_pin_hash';
  static const String _pinSaltKey = 'decoy_pin_salt';

  static const String _prefsPhotosKey = 'decoy_vault_photos';
  static const String _prefsNotesKey = 'decoy_vault_notes';
  static const String _prefsDocsKey = 'decoy_vault_documents';

  final PlatformService _platformService;
  final ProStatusService? _proStatusService;

  DecoyVaultService(this._platformService, [this._proStatusService]);

  Future<String> _verifierAsync(String pin, String salt) async {
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final saltBytes = Uint8List.fromList(utf8.encode(salt));
    final derived = await derivePbkdf2Async(
      pinBytes,
      saltBytes,
      kDuressIterations,
      kDerivedKeyLength,
    );
    return 'v2:${base64Encode(derived)}';
  }

  bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var result = 0;
    for (var i = 0; i < ab.length; i++) {
      result |= ab[i] ^ bb[i];
    }
    return result == 0;
  }

  Future<void> setDecoyPin(String pin) async {
    if (kIsWeb) return;
    final salt = _generateSalt();
    final hash = await _verifierAsync(pin, salt);
    await _platformService.secureWrite(_pinHashKey, hash);
    await _platformService.secureWrite(_pinSaltKey, salt);
  }

  /// Verifies the Decoy PIN to unlock the Decoy Vault.
  /// Enforces that the user currently holds active Pro status. If Pro has been
  /// revoked or lapsed, this returns false so the Decoy Vault does not open.
  Future<bool> isDecoyPin(String pin) async {
    if (kIsWeb) return false;
    if (_proStatusService != null) {
      final isPro = await _proStatusService!.isPro();
      if (!isPro) return false;
    }
    return hasStoredDecoyPinMatch(pin);
  }

  /// Verifies if [pin] matches the stored decoy hash, regardless of Pro entitlement.
  /// Used for collision detection when configuring Master PIN or Duress PIN so that
  /// a lapsed user cannot introduce PIN collisions.
  Future<bool> hasStoredDecoyPinMatch(String pin) async {
    if (kIsWeb) return false;
    final storedHash = await _platformService.secureRead(_pinHashKey);
    final storedSalt = await _platformService.secureRead(_pinSaltKey);
    if (storedHash == null || storedSalt == null) return false;
    if (storedHash.startsWith('v2:')) {
      final computed = await _verifierAsync(pin, storedSalt);
      return _constantTimeEquals(storedHash, computed);
    } else {
      final computed = _hashPin(pin, storedSalt);
      return _constantTimeEquals(storedHash, computed);
    }
  }

  /// Checks whether Decoy PIN is active (a PIN is set AND the user has active Pro status).
  Future<bool> isDecoyPinEnabled() async {
    if (kIsWeb) return false;
    if (_proStatusService != null) {
      final isPro = await _proStatusService!.isPro();
      if (!isPro) return false;
    }
    return hasStoredDecoyPin();
  }

  /// Checks whether a Decoy PIN is persisted in secure storage, regardless of Pro status.
  Future<bool> hasStoredDecoyPin() async {
    if (kIsWeb) return false;
    final hash = await _platformService.secureRead(_pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> clearDecoyContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsPhotosKey);
      await prefs.remove(_prefsNotesKey);
      await prefs.remove(_prefsDocsKey);
    } catch (_) {}
  }

  Future<void> clearDecoyPin() async {
    if (kIsWeb) return;
    await _platformService.secureDelete(_pinHashKey);
    await _platformService.secureDelete(_pinSaltKey);
    await clearDecoyContent();
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Decoy Content Operations (Empty by default — populated only by user)
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<DecoyPhoto>> getPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsPhotosKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }
      final List decoded = jsonDecode(jsonStr);
      return decoded.map((m) => DecoyPhoto.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePhotos(List<DecoyPhoto> photos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(photos.map((p) => p.toMap()).toList());
      await prefs.setString(_prefsPhotosKey, jsonStr);
    } catch (_) {}
  }

  Future<void> addPhoto(DecoyPhoto photo) async {
    final list = await getPhotos();
    list.insert(0, photo);
    await savePhotos(list);
  }

  Future<void> deletePhoto(String id) async {
    final list = await getPhotos();
    list.removeWhere((p) => p.id == id);
    await savePhotos(list);
  }

  Future<List<DecoyNote>> getNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsNotesKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }
      final List decoded = jsonDecode(jsonStr);
      return decoded.map((m) => DecoyNote.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNotes(List<DecoyNote> notes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(notes.map((n) => n.toMap()).toList());
      await prefs.setString(_prefsNotesKey, jsonStr);
    } catch (_) {}
  }

  Future<void> saveNote(DecoyNote note) async {
    final list = await getNotes();
    final idx = list.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      list[idx] = note;
    } else {
      list.insert(0, note);
    }
    await saveNotes(list);
  }

  Future<void> deleteNote(String id) async {
    final list = await getNotes();
    list.removeWhere((n) => n.id == id);
    await saveNotes(list);
  }

  Future<List<DecoyDocument>> getDocuments() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsDocsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return [];
      }
      final List decoded = jsonDecode(jsonStr);
      return decoded.map((m) => DecoyDocument.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDocuments(List<DecoyDocument> docs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(docs.map((d) => d.toMap()).toList());
      await prefs.setString(_prefsDocsKey, jsonStr);
    } catch (_) {}
  }

  Future<void> addDocument(DecoyDocument doc) async {
    final list = await getDocuments();
    list.insert(0, doc);
    await saveDocuments(list);
  }

  Future<void> deleteDocument(String id) async {
    final list = await getDocuments();
    list.removeWhere((d) => d.id == id);
    await saveDocuments(list);
  }
}

final decoyVaultServiceProvider = Provider<DecoyVaultService>((ref) {
  return DecoyVaultService(
    ref.read(platformServiceProvider),
    ref.read(proStatusServiceProvider),
  );
});
