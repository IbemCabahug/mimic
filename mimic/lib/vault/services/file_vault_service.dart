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
  // Folder feature (mirrors DocumentMeta.folder): '' = Unfiled. Filter-only —
  // the encrypted blob never moves; only this label changes.
  final String folder;

  PhotoMeta({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    this.originalName,
    this.folder = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'mimeType': mimeType,
        'size': size,
        'createdAt': createdAt.toIso8601String(),
        'originalName': originalName,
        'folder': folder,
      };

  factory PhotoMeta.fromMap(Map<String, dynamic> map) => PhotoMeta(
        id: map['id'] as String,
        mimeType: map['mimeType'] as String,
        size: map['size'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        originalName: map['originalName'] as String?,
        // Pre-folder rows (and v2 backup payloads) carry no key — ?? '' keeps
        // them readable as Unfiled instead of throwing.
        folder: map['folder'] as String? ?? '',
      );

  /// Copies this metadata with the given fields replaced.
  PhotoMeta copyWith({
    String? mimeType,
    int? size,
    DateTime? createdAt,
    String? originalName,
    String? folder,
  }) {
    return PhotoMeta(
      id: id,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      originalName: originalName ?? this.originalName,
      folder: folder ?? this.folder,
    );
  }
}

class FileVaultService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _dbName = 'vault_files.db';
  static const String _tableName = 'photos';
  Database? _db;
  Future<void>? _openDbFuture;

  int _openCount = 0;

  @visibleForTesting
  int get openCount => _openCount;

  FileVaultService(this._platformService, this._crypto);

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
              createdAt TEXT,
              originalName TEXT,
              folder TEXT DEFAULT ''
            )
          ''');
        },
        onOpen: (db) async {
          try {
            final List<Map<String, dynamic>> columns = await db.rawQuery("PRAGMA table_info($_tableName)");
            final hasOriginalName = columns.any((column) => column['name'] == 'originalName');
            if (!hasOriginalName) {
              await db.execute("ALTER TABLE $_tableName ADD COLUMN originalName TEXT");
            }
            // Folder feature: pre-folder installs lack the column; same
            // PRAGMA-migrate pattern as originalName above.
            final hasFolder = columns.any((column) => column['name'] == 'folder');
            if (!hasFolder) {
              await db.execute("ALTER TABLE $_tableName ADD COLUMN folder TEXT DEFAULT ''");
            }
          } catch (e) {
            debugPrint('Error updating schema: $e');
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
    bool writeSucceeded = false;
    try {
      await _platformService.saveEncryptedFile(id, encrypted);

      final meta = PhotoMeta(
        id: id,
        mimeType: mimeType,
        size: bytes.length,
        createdAt: now,
        originalName: originalName,
      );

      await _saveMeta(meta);
      writeSucceeded = true;
      return id;
    } finally {
      if (!writeSucceeded) {
        try {
          await _platformService.deleteFile(id);
        } catch (e) {
          debugPrint('Failed to clean up orphan photo file $id: $e');
        }
      }
    }
  }

  /// Reads and decrypts one stored blob, off the UI isolate when possible.
  ///
  /// 2026-09-17: the photo grid draws every visible tile at once, so the old
  /// `readEncryptedFile` + `decryptSystem` pair ran one whole-file AES pass per
  /// tile on the UI isolate, all in the same frame window. Measured on the dev
  /// box: 588 ms for one 3 MB photo, 2134 ms for a nine-tile grid, zero
  /// event-loop ticks — the "hang" reported when re-entering the photo vault.
  /// The worker isolate that already serves video ranges now does this AES pass
  /// too, so the UI keeps painting while tiles fill in.
  ///
  /// The worker path only exists for file-backed blobs (native platforms), is
  /// only tried while the vault is unlocked, and any failure falls through to
  /// the exact previous code path, so behavior and error handling are unchanged
  /// on web and whenever the worker cannot start. Note the deliberate absence of
  /// a `SystemKeyMissingException` clause: the old body caught every exception
  /// and returned null, and `photo_vault_screen.dart:70`'s snackbar was never
  /// reachable from here, so making it reachable now would be an unrequested
  /// behavior change on top of a performance fix.
  Future<Uint8List?> _readDecryptedBlob(String id) async {
    if (!kIsWeb) {
      try {
        final file = await _platformService.resolveVaultFile(id);
        if (await file.exists()) {
          final fromWorker = await _crypto.tryDecryptFileInWorker(file);
          if (fromWorker != null) return fromWorker;
        }
      } catch (_) {
        // Unresolvable path or worker failure: fall through to the in-memory
        // path below, which is the pre-2026-09-17 behavior.
      }
    }

    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;
    try {
      return await _crypto.decryptSystem(encrypted);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> getPhoto(String id) async {
    return _readDecryptedBlob(id);
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

  /// Folder feature: relabels one photo's folder ('' = Unfiled). Filter-only —
  /// the encrypted blob is untouched; only the metadata row is rewritten.
  /// Mirrors DocumentVaultService.moveDocument.
  Future<void> movePhoto(String id, String folder) async {
    if (kIsWeb) {
      final existing = await getAllPhotos();
      final index = existing.indexWhere((m) => m.id == id);
      if (index == -1) return;
      existing[index] = existing[index].copyWith(folder: folder);
      await _platformService.secureWrite(
        'vault_photos_meta',
        jsonEncode(existing.map((m) => m.toMap()).toList()),
      );
      return;
    }
    await _ensureDb();
    final maps = await _db!.query(_tableName, where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return;
    final updated =
        PhotoMeta.fromMap(maps.single).copyWith(folder: folder);
    await _db!.update(_tableName, updated.toMap(),
        where: 'id = ?', whereArgs: [id]);
  }

  Future<({List<String> successfulIds, int totalAttempted, bool stoppedEarly, String? failedFileName, Object? error, bool originalsKept})> pickAndEncryptImage(BuildContext context, {void Function(int index, int positionOneBased, String name)? onFileStart, void Function(int index)? onFileSaved, void Function()? onWaitingDeleteConfirm, void Function(int total)? onPicked, void Function(int index, String detail)? onFileFailed, bool Function()? isCancelled}) async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        requestType: RequestType.image,
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
        try {
          onFileStart?.call(i, i + 1, asset.title ?? 'photo');
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
        final bytes = await file.readAsBytes();
        final name = asset.title;
        final mime = await asset.mimeTypeAsync ?? 'image/jpeg';
        final id = await savePhoto(bytes, mime, originalName: name);
        savedIds.add(id);
        try {
          onFileSaved?.call(i);
        } catch (_) {}
      } catch (e) {
        stoppedEarly = true;
        failedFileName = asset.title ?? 'photo';
        failureError = e;
        try {
          // Deliberately a fixed string, never `e`: a failure detail must not
          // leak a filesystem path to the screen (see the T15 test).
          onFileFailed?.call(i, 'Import failed');
        } catch (_) {}
        debugPrint('pickAndEncryptImage failed on $failedFileName: $e');
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

    return (
      successfulIds: savedIds,
      totalAttempted: assets.length,
      stoppedEarly: stoppedEarly,
      failedFileName: failedFileName,
      error: failureError,
      originalsKept: originalsKept,
    );
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

  /// Restores a photo: writes the decrypted bytes back into the system
  /// gallery, and ONLY after the gallery confirms the write removes the vault
  /// copy. Order matters — deleting before a confirmed write is how photos
  /// get lost; the old code deleted unconditionally after saveImage returned,
  /// whether or not the gallery had actually accepted the file.
  /// [isCancelled] is the restore pill's cancel flag. The photo decrypt is
  /// one in-memory pass with no mid-flight abort point, so the flag is
  /// checked before starting and again after the bytes are loaded — a cancel
  /// pressed during the load still stops before anything reaches the gallery.
  Future<void> restorePhotoToGallery(
    String id, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled != null && isCancelled()) {
      throw const OperationCancelledException();
    }
    final bytes = await getPhoto(id);
    if (bytes == null) throw Exception('Photo file not found in vault');
    if (isCancelled != null && isCancelled()) {
      throw const OperationCancelledException();
    }

    final photos = await getAllPhotos();
    final photo = photos.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Photo metadata not found in vault'),
    );
    final originalName = photo.originalName ?? '$id.jpg';

    // photo_manager 3.9.0 (the pinned plugin) has saveImage return a
    // NON-NULLABLE Future<AssetEntity> and report a refusal by throwing
    // (editor.dart:85 -> plugin.dart:397 in the pub cache), so "the gallery
    // refused" is the catch branch — a null return is impossible and would
    // have been dead code here.
    try {
      await PhotoManager.editor.saveImage(
        bytes,
        filename: originalName,
      );
    } catch (_) {
      // The gallery refused. The vault copy is untouched — say so instead of
      // pretending nothing happened.
      throw Exception('The gallery did not accept the photo. The vault copy was kept.');
    }

    try {
      await deletePhoto(id);
    } catch (_) {
      // The plaintext now exists in the gallery AND the vault. The user must
      // know both copies exist — a silent duplicate defeats the vault.
      throw Exception(
          'Photo was saved to the gallery, but the vault copy could not be deleted. Delete it from the vault manually.');
    }
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
