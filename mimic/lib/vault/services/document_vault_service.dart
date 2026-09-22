// lib/vault/services/document_vault_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';
import '../security/auto_lock.dart';

class DocumentMeta {
  final String id;
  final String fileName;
  final String fileType;
  final int sizeBytes;
  final DateTime addedAt;
  final bool isTextNote;
  final String folder;

  DocumentMeta({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.sizeBytes,
    required this.addedAt,
    this.isTextNote = false,
    this.folder = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'fileType': fileType,
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
        'isTextNote': isTextNote ? 1 : 0,
        'folder': folder,
      };

  factory DocumentMeta.fromMap(Map<String, dynamic> map) => DocumentMeta(
        id: map['id'] as String,
        fileName: map['fileName'] as String,
        fileType: map['fileType'] as String,
        sizeBytes: map['sizeBytes'] as int,
        addedAt: DateTime.parse(map['addedAt'] as String),
        isTextNote: (map['isTextNote'] as int? ?? 0) == 1,
        folder: map['folder'] as String? ?? '',
      );

  DocumentMeta copyWith({
    String? fileName,
    String? fileType,
    int? sizeBytes,
    DateTime? addedAt,
    bool? isTextNote,
    String? folder,
  }) =>
      DocumentMeta(
        id: id,
        fileName: fileName ?? this.fileName,
        fileType: fileType ?? this.fileType,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        addedAt: addedAt ?? this.addedAt,
        isTextNote: isTextNote ?? this.isTextNote,
        folder: folder ?? this.folder,
      );
}

/// Where a document restore ended up. Explicit instead of nulls and
/// exceptions so the screen can tell the user the truth in every case.
enum DocumentRestoreOutcome {
  /// Plaintext written where the user chose; vault copy deleted.
  restored,

  /// The user cancelled the location picker — nothing was written, the
  /// vault copy is untouched.
  cancelled,

  /// The write to the chosen location failed — the vault copy is untouched.
  saveFailed,

  /// The plaintext WAS written, but the vault copy could not be deleted.
  /// The document now exists in both places and the user must be told.
  restoredButVaultCopyRemains,
}

class DocumentVaultService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  static const String _storageKey = 'vault_documents_meta';

  DocumentVaultService(this._platformService, this._crypto);

  Future<List<DocumentMeta>> listDocuments() async {
    if (kIsWeb) {
      final raw = await _platformService.secureRead(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return _dedupById(decoded
          .map((e) => DocumentMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList());
    }
    // Mobile: secure storage is the source of truth (it always receives the
    // write alongside prefs). Prefs is only a FALLBACK for when secure
    // storage returns nothing — reading prefs first let the two stores
    // diverge, resurfacing stale entries (ghost/duplicate documents) after
    // imports, moves or restores.
    final secureRaw = await _platformService.secureRead(_storageKey);
    if (secureRaw != null && secureRaw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(secureRaw);
        return _dedupById(decoded
            .map((e) => DocumentMeta.fromMap(Map<String, dynamic>.from(e)))
            .toList());
      } catch (_) {
        // fall through to prefs
      }
    }
    return _loadFromPrefs();
  }

  /// Defensive: duplicate ids in the meta list render one document twice.
  /// Keep the first occurrence of each id.
  static List<DocumentMeta> _dedupById(List<DocumentMeta> docs) {
    final seen = <String>{};
    return docs.where((d) => seen.add(d.id)).toList();
  }

  Future<List<DocumentMeta>> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => DocumentMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveMeta(List<DocumentMeta> docs) async {
    final jsonList = docs.map((m) => m.toMap()).toList();
    final encoded = jsonEncode(jsonList);

    if (kIsWeb) {
      await _platformService.secureWrite(_storageKey, encoded);
      return;
    }

    // Mobile: store in both platform service and shared prefs for redundancy
    await _platformService.secureWrite(_storageKey, encoded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, encoded);
  }

  Future<({String id, bool tempCopyRemoved})> importDocument() async {
    final result = await _pickDocument();
    final id = await saveDocumentFromFile(result.srcFile, result.extension, originalName: result.fileName);
    // VERIFIED against file_picker 10.3.10 (this app's pinned version):
    // FileUtils.openFileStream copies the picked content:// URI into
    // context.cacheDir/file_picker/<timestamp>/<name> and returns THAT path, and
    // it is the only path builder for picked files. So `file.path` is never the
    // user's real document and never a download path - it is our own temporary
    // copy, plaintext, sitting in the app's private cache. The user's original
    // in Downloads/Documents is untouched by the picker, and Mimic has no
    // authority over it, so it stays and the screen must say so.
    //
    // Our own copy is a different matter: it is inside our cache, so we do have
    // authority over it, and leaving it behind would strand a readable duplicate
    // of a document the user just chose to protect. Remove it - but only AFTER
    // the encrypted write succeeded, so a failed import never destroys the only
    // copy, and only when it really is inside our temp dir.
    final tempCopyRemoved = await _deletePickedTempCopy(result.pickedPath);
    return (id: id, tempCopyRemoved: tempCopyRemoved);
  }

  /// H7 follow-up (2026-09-17): optional deletion of the ORIGINAL document the
  /// user picked, via Android SAF. The pinned file_picker hands back the
  /// original's content:// URI in `PlatformFile.identifier` (verified: the
  /// FileInfo builder emits Pair("identifier", uri.toString())), and
  /// ACTION_OPEN_DOCUMENT grants temporary read/write access to that URI.
  /// Deleting goes through DocumentsContract.deleteDocument, which only works
  /// when the provider supports FLAG_SUPPORTS_DELETE — anything else (read-only
  /// provider, cloud doc, expired grant) must surface as "kept", never crash.
  ///
  /// The user opts in explicitly per import; this is NEVER automatic. Returns
  /// false (with a reason) when the original could not be removed; the vault
  /// copy is unaffected either way because this runs after the save.
  Future<({String id, bool tempCopyRemoved, bool originalRemoved, String? originalNote})>
      importDocumentAndRemoveOriginal() async {
    final result = await _pickDocument();
    final id = await saveDocumentFromFile(result.srcFile, result.extension,
        originalName: result.fileName);
    final tempCopyRemoved = await _deletePickedTempCopy(result.pickedPath);

    var originalRemoved = false;
    String? originalNote;
    final uri = result.identifier;
    if (uri == null || uri.isEmpty) {
      originalNote = 'Original location unknown — not removed.';
    } else {
      final deleted = await _deleteOriginalHook(uri);
      if (deleted) {
        originalRemoved = true;
      } else {
        originalNote =
            'Could not remove the original (source may not allow it). It was kept.';
      }
    }
    return (
      id: id,
      tempCopyRemoved: tempCopyRemoved,
      originalRemoved: originalRemoved,
      originalNote: originalNote,
    );
  }

  Future<bool> _deleteOriginalHook(String uri) =>
      _deleteOriginalOverride?.call(uri) ??
      const MethodChannel('mimic/documents')
          .invokeMethod<bool>('deleteDocument', {'uri': uri})
          .then((v) => v ?? false)
          .catchError((_) => false);

  Future<bool> Function(String uri)? _deleteOriginalOverride;
  @visibleForTesting
  set deleteOriginalHook(Future<bool> Function(String uri)? hook) =>
      _deleteOriginalOverride = hook;

  /// Shared picker step for both import paths. Returns the temp copy path the
  /// plugin wrote (which is what we encrypt), plus the original's content URI
  /// when the platform provided one (used only for the opt-in original
  /// removal, never for anything automatic).
  Future<
      ({File srcFile, String fileName, String extension, String pickedPath, String? identifier})>
      _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      allowedExtensions: ['txt', 'pdf', 'docx', 'xlsx'],
      type: FileType.custom,
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('No file selected');
    }

    final file = result.files.single;
    if (file.path == null) {
      throw Exception('Couldn\'t read that file. Please try again or use a different file manager.');
    }

    return (
      srcFile: File(file.path!),
      fileName: file.name,
      extension: file.name.split('.').last.toLowerCase(),
      pickedPath: file.path!,
      identifier: file.identifier,
    );
  }

  /// Deletes the plaintext copy file_picker wrote into the app's own temp dir
  /// after a successful import. Returns false when the path is NOT inside our
  /// temp dir: that never happens with the pinned file_picker, but if a future
  /// version starts handing back a real external path, this guard makes the
  /// worst case "we left a file alone" instead of "we deleted the user's file".
  Future<bool> _deletePickedTempCopy(String path) async {
    try {
      final tempRoot = p.normalize(p.absolute((await getTemporaryDirectory()).path));
      final picked = p.normalize(p.absolute(path));
      if (!p.isWithin(tempRoot, picked)) return false;
      final copy = File(picked);
      if (await copy.exists()) await copy.delete();
      return true;
    } catch (e) {
      debugPrint('Failed to remove the picked-document temp copy: $e');
      return false;
    }
  }

  Future<String> saveDocumentFromFile(File src, String mimeType, {String? originalName}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final dest = await _platformService.resolveVaultFile(id);
    await _crypto.encryptStreamSystem(src, dest);

    final size = await src.length();

    final existing = await listDocuments();
    existing.add(DocumentMeta(
      id: id,
      fileName: originalName ?? 'document_$id.$mimeType',
      fileType: mimeType,
      sizeBytes: size,
      addedAt: now,
      isTextNote: false,
    ));
    await _saveMeta(existing);

    return id;
  }

  Future<String> createTextNote(String title, String text) async {
    final id = const Uuid().v4();
    final now = DateTime.now();

    final bytes = Uint8List.fromList(utf8.encode(text));
    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final existing = await listDocuments();
    existing.add(DocumentMeta(
      id: id,
      fileName: title.isEmpty ? 'Note ${now.day}/${now.month}' : title,
      fileType: 'txt',
      sizeBytes: bytes.length,
      addedAt: now,
      isTextNote: true,
    ));
    await _saveMeta(existing);

    return id;
  }

  Future<Uint8List?> getDocumentBytes(String id) async {
    // 2026-09-17: same reason as FileVaultService._readDecryptedBlob — the
    // whole-file AES pass used to run on the UI isolate while a document was
    // being opened. Prefer the worker when the blob is file-backed, and keep
    // the in-memory path as the fallback so web and worker-less states behave
    // exactly as before. The catch below stays unconditional for the same
    // reason as there: the old body returned null on every exception, so no
    // `SystemKeyMissingException` clause is added.
    if (!kIsWeb) {
      try {
        final file = await _platformService.resolveVaultFile(id);
        if (await file.exists()) {
          final fromWorker = await _crypto.tryDecryptFileInWorker(file);
          if (fromWorker != null) return fromWorker;
        }
      } catch (_) {}
    }

    final encrypted = await _platformService.readEncryptedFile(id);
    if (encrypted == null) return null;
    try {
      return await _crypto.decryptSystem(encrypted);
    } catch (e) {
      return null;
    }
  }

  Future<File?> getDocumentToTempFile(String id) async {
    final srcBlob = await _platformService.resolveVaultFile(id);
    if (!srcBlob.existsSync()) return null;

    final tempDir = await getTemporaryDirectory();
    final docsDir = Directory(p.join(tempDir.path, 'vault_docs'));
    if (!docsDir.existsSync()) {
      docsDir.createSync(recursive: true);
    }
    
    final tempFile = File(p.join(docsDir.path, '${id}_view.pdf'));
    
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

  Future<String?> getTextNote(String id) async {
    final bytes = await getDocumentBytes(id);
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  Future<void> updateTextNote(String id, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final encrypted = await _crypto.encryptSystem(bytes);
    await _platformService.saveEncryptedFile(id, encrypted);

    final existing = await listDocuments();
    final index = existing.indexWhere((d) => d.id == id);
    if (index != -1) {
      existing[index] = existing[index].copyWith(
        sizeBytes: bytes.length,
        fileType: 'txt',
        isTextNote: true,
      );
      await _saveMeta(existing);
    }
  }

  Future<void> deleteDocument(String id) async {
    await _platformService.deleteFile(id);
    final existing = await listDocuments();
    existing.removeWhere((d) => d.id == id);
    await _saveMeta(existing);
  }

  /// Danger Zone → Clear All Data support. Removes the document store: the
  /// `vault_documents_meta` key from BOTH stores that hold it on mobile
  /// (secure storage and the SharedPreferences redundancy copy — the old
  /// Clear All Data deleted neither, so documents survived), plus the per-id
  /// web blob entries. Documents on mobile are stored in the shared
  /// `vault_files/` directory, purged by [VaultWipeService]. Access state is
  /// never touched.
  Future<void> wipeAllData() async {
    if (kIsWeb) {
      try {
        for (final doc in await listDocuments()) {
          try {
            await _platformService.deleteFile(doc.id);
          } catch (_) {}
        }
      } catch (_) {}
    }
    try {
      await _platformService.secureDelete(_storageKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }

  Future<void> moveDocument(String id, String folder) async {
    final existing = await listDocuments();
    final index = existing.indexWhere((d) => d.id == id);
    if (index == -1) return;
    existing[index] = existing[index].copyWith(folder: folder);
    await _saveMeta(existing);
  }

  Future<File?> getDocumentForSharing(DocumentMeta doc) async {
    final tempDir = await getTemporaryDirectory();
    final shareDir = Directory(p.join(tempDir.path, 'vault_share'));
    if (!shareDir.existsSync()) {
      shareDir.createSync(recursive: true);
    }
    var safeName = doc.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safeName.trim().isEmpty) safeName = 'document';
    if ((doc.isTextNote || doc.fileType == 'txt') &&
        !safeName.toLowerCase().endsWith('.txt')) {
      safeName = '$safeName.txt';
    }
    final outFile = File(p.join(shareDir.path, safeName));
    try {
      if (doc.isTextNote || doc.fileType == 'txt') {
        final bytes = await getDocumentBytes(doc.id);
        if (bytes == null) return null;
        await outFile.writeAsBytes(bytes);
      } else {
        final srcBlob = await _platformService.resolveVaultFile(doc.id);
        if (!srcBlob.existsSync()) return null;
        await _crypto.decryptStreamSystem(srcBlob, outFile);
      }
      return outFile;
    } catch (e) {
      if (outFile.existsSync()) {
        outFile.deleteSync();
      }
      return null;
    }
  }

  /// Test seam: writes the plaintext to a location the user picks (Android
  /// SAF via file_picker's saveFile — no storage permission needed). Returns
  /// the written path, or null when the user cancelled.
  @visibleForTesting
  Future<String?> saveDocumentToDisk(Uint8List bytes, String fileName) {
    return FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
  }

  /// Restores a document out of the vault: decrypts, asks the user where to
  /// save the plaintext, writes it, and ONLY after a confirmed write deletes
  /// the vault copy. Cancel and write failures leave the vault untouched —
  /// the vault is never the thing that loses the file.
  Future<DocumentRestoreOutcome> restoreDocumentToDisk(String id) async {
    final docs = await listDocuments();
    final index = docs.indexWhere((d) => d.id == id);
    if (index == -1) return DocumentRestoreOutcome.cancelled;
    final doc = docs[index];

    final bytes = await getDocumentBytes(id);
    if (bytes == null) return DocumentRestoreOutcome.saveFailed;

    final String? savedPath;
    try {
      savedPath = await saveDocumentToDisk(bytes, doc.fileName);
    } catch (_) {
      return DocumentRestoreOutcome.saveFailed;
    }
    if (savedPath == null) return DocumentRestoreOutcome.cancelled;

    try {
      await deleteDocument(id);
    } catch (_) {
      // The plaintext was written AND the vault copy remains. Say so — a
      // silent duplicate defeats the vault.
      return DocumentRestoreOutcome.restoredButVaultCopyRemains;
    }
    return DocumentRestoreOutcome.restored;
  }

  Future<void> cleanupShareTemp() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final shareDir = Directory(p.join(tempDir.path, 'vault_share'));
      await AutoLock.secureDeleteDir(shareDir);
    } catch (_) {}
  }
}

final documentVaultServiceProvider = Provider<DocumentVaultService>((ref) {
  final platformService = ref.read(platformServiceProvider);
  final crypto = ref.read(vaultCryptoProvider);
  return DocumentVaultService(platformService, crypto);
});