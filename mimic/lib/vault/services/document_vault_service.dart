// lib/vault/services/document_vault_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
      return decoded
          .map((e) => DocumentMeta.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    // Mobile: try to read from preferences if available (fallback for consistency)
    return _loadFromPrefs();
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

  Future<String> importDocument() async {
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

    final srcFile = File(file.path!);
    final fileName = file.name;
    final extension = fileName.split('.').last.toLowerCase();

    return saveDocumentFromFile(srcFile, extension, originalName: fileName);
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