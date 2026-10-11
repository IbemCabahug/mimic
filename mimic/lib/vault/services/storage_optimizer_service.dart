// mimic/lib/vault/services/storage_optimizer_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'file_vault_service.dart';
import 'video_vault_service.dart';
import 'document_vault_service.dart';

enum VaultMediaType { photo, video, document }

class OptimizableFile {
  final String id;
  final String name;
  final int sizeBytes;
  final VaultMediaType type;
  final DateTime createdAt;
  /// SHA-256 hash of the raw content bytes. Null for files imported before
  /// hash tracking was added; the optimizer falls back to size-based matching
  /// for those.
  final String? contentHash;

  const OptimizableFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.type,
    required this.createdAt,
    this.contentHash,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class DuplicateGroup {
  final String key;
  final int sizeBytes;
  final List<OptimizableFile> files;

  const DuplicateGroup({
    required this.key,
    required this.sizeBytes,
    required this.files,
  });

  /// The amount of bytes that can be freed by keeping 1 file and deleting all copies.
  int get potentialSavings => sizeBytes * (files.length - 1);

  /// The original file that is kept (first copy).
  OptimizableFile get originalFile => files.first;

  /// The redundant duplicate copies (all copies except the original).
  List<OptimizableFile> get duplicateCopies =>
      files.length > 1 ? files.sublist(1) : const [];
}

class StorageOptimizationReport {
  final int photosBytes;
  final int videosBytes;
  final int docsBytes;
  final int totalBytes;
  final int photoCount;
  final int videoCount;
  final int docCount;
  final List<OptimizableFile> largeFiles;
  final List<DuplicateGroup> duplicateGroups;

  const StorageOptimizationReport({
    required this.photosBytes,
    required this.videosBytes,
    required this.docsBytes,
    required this.totalBytes,
    required this.photoCount,
    required this.videoCount,
    required this.docCount,
    required this.largeFiles,
    required this.duplicateGroups,
  });

  int get potentialDuplicateSavings =>
      duplicateGroups.fold<int>(0, (sum, group) => sum + group.potentialSavings);

  /// All redundant duplicate copies across all groups (preserving originals).
  List<OptimizableFile> get allDuplicateCopies =>
      duplicateGroups.expand((group) => group.duplicateCopies).toList();

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class StorageOptimizerService {
  final FileVaultService fileVaultService;
  final VideoVaultService videoVaultService;
  final DocumentVaultService docVaultService;

  StorageOptimizerService({
    required this.fileVaultService,
    required this.videoVaultService,
    required this.docVaultService,
  });

  Future<StorageOptimizationReport> analyzeVault({
    int largeFileThreshold = 20 * 1024 * 1024, // 20 MB threshold
  }) async {
    final allFiles = <OptimizableFile>[];
    int photosBytes = 0;
    int videosBytes = 0;
    int docsBytes = 0;
    int photoCount = 0;
    int videoCount = 0;
    int docCount = 0;

    // 1. Photos — backfill content hashes for legacy imports without one.
    try {
      final photos = await fileVaultService.getAllPhotos();
      photoCount = photos.length;
      for (final p in photos) {
        final size = p.size;
        photosBytes += size;

        String? hash = p.contentHash;
        if (hash == null || hash.isEmpty) {
          // Legacy import: decrypt the blob and compute its hash, then persist
          // so the next scan doesn't have to decrypt again.
          try {
            final bytes = await fileVaultService.readFile(p.id);
            if (bytes != null && bytes.isNotEmpty) {
              hash = PhotoMeta.computeHash(bytes);
              await fileVaultService.updatePhotoHash(p.id, hash);
            }
          } catch (_) {}
        }

        allFiles.add(OptimizableFile(
          id: p.id,
          name: p.originalName ?? 'Photo_${p.id}',
          sizeBytes: size,
          type: VaultMediaType.photo,
          createdAt: p.createdAt,
          contentHash: hash,
        ));
      }
    } catch (_) {}

    // 2. Videos — backfill content hashes for legacy imports without one.
    try {
      final videos = await videoVaultService.getAllVideos();
      videoCount = videos.length;
      for (final v in videos) {
        final size = v.size;
        videosBytes += size;

        String? hash = v.contentHash;
        if (hash == null || hash.isEmpty) {
          try {
            final bytes = await videoVaultService.getVideo(v.id);
            if (bytes != null && bytes.isNotEmpty) {
              hash = PhotoMeta.computeHash(bytes);
              await videoVaultService.updateVideoHash(v.id, hash);
            }
          } catch (_) {}
        }

        allFiles.add(OptimizableFile(
          id: v.id,
          name: v.originalName ?? 'Video_${v.id}',
          sizeBytes: size,
          type: VaultMediaType.video,
          createdAt: v.createdAt,
          contentHash: hash,
        ));
      }
    } catch (_) {}

    // 3. Documents
    try {
      final docs = await docVaultService.listDocuments();
      docCount = docs.length;
      for (final d in docs) {
        final size = d.sizeBytes;
        docsBytes += size;
        allFiles.add(OptimizableFile(
          id: d.id,
          name: d.fileName,
          sizeBytes: size,
          type: VaultMediaType.document,
          createdAt: d.addedAt,
        ));
      }
    } catch (_) {}

    final totalBytes = photosBytes + videosBytes + docsBytes;

    // Detect large files
    final largeFiles = allFiles.where((f) => f.sizeBytes >= largeFileThreshold).toList()
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    // Detect duplicate files by content hash (preferred) or media type + byte size (legacy fallback)
    final map = <String, List<OptimizableFile>>{};
    for (final f in allFiles) {
      if (f.sizeBytes <= 0) continue;
      // Use the SHA-256 content hash when available; otherwise fall back to
      // the old type+size key for files imported before hash tracking.
      final key = f.contentHash != null
          ? '${f.type.name}_hash_${f.contentHash}'
          : '${f.type.name}_${f.sizeBytes}';
      map.putIfAbsent(key, () => []).add(f);
    }

    final duplicateGroups = <DuplicateGroup>[];
    for (final entry in map.entries) {
      if (entry.value.length > 1) {
        // Sort so the oldest / earliest imported copy is first (the protected original)
        entry.value.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        duplicateGroups.add(DuplicateGroup(
          key: entry.key,
          sizeBytes: entry.value.first.sizeBytes,
          files: entry.value,
        ));
      }
    }

    // Sort duplicates by potential savings descending
    duplicateGroups.sort((a, b) => b.potentialSavings.compareTo(a.potentialSavings));

    return StorageOptimizationReport(
      photosBytes: photosBytes,
      videosBytes: videosBytes,
      docsBytes: docsBytes,
      totalBytes: totalBytes,
      photoCount: photoCount,
      videoCount: videoCount,
      docCount: docCount,
      largeFiles: largeFiles,
      duplicateGroups: duplicateGroups,
    );
  }

  Future<void> deleteOptimizableFile(OptimizableFile file) async {
    switch (file.type) {
      case VaultMediaType.photo:
        await fileVaultService.deletePhoto(file.id);
        break;
      case VaultMediaType.video:
        await videoVaultService.deleteVideo(file.id);
        break;
      case VaultMediaType.document:
        await docVaultService.deleteDocument(file.id);
        break;
    }
  }

  /// Deletes a list of optimizable files and returns the count of successfully deleted files.
  Future<int> deleteOptimizableFiles(List<OptimizableFile> files) async {
    int deletedCount = 0;
    for (final file in files) {
      try {
        await deleteOptimizableFile(file);
        deletedCount++;
      } catch (_) {}
    }
    return deletedCount;
  }
}

final storageOptimizerServiceProvider = Provider<StorageOptimizerService>((ref) {
  return StorageOptimizerService(
    fileVaultService: ref.read(fileVaultServiceProvider),
    videoVaultService: ref.read(videoVaultServiceProvider),
    docVaultService: ref.read(documentVaultServiceProvider),
  );
});
