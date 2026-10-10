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

  const OptimizableFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.type,
    required this.createdAt,
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

    // 1. Photos
    try {
      final photos = await fileVaultService.getAllPhotos();
      photoCount = photos.length;
      for (final p in photos) {
        final size = p.size;
        photosBytes += size;
        allFiles.add(OptimizableFile(
          id: p.id,
          name: p.originalName ?? 'Photo_${p.id}',
          sizeBytes: size,
          type: VaultMediaType.photo,
          createdAt: p.createdAt,
        ));
      }
    } catch (_) {}

    // 2. Videos
    try {
      final videos = await videoVaultService.getAllVideos();
      videoCount = videos.length;
      for (final v in videos) {
        final size = v.size;
        videosBytes += size;
        allFiles.add(OptimizableFile(
          id: v.id,
          name: v.originalName ?? 'Video_${v.id}',
          sizeBytes: size,
          type: VaultMediaType.video,
          createdAt: v.createdAt,
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

    // Detect duplicate files by size and name
    final map = <String, List<OptimizableFile>>{};
    for (final f in allFiles) {
      if (f.sizeBytes <= 0) continue;
      final key = '${f.type.name}_${f.sizeBytes}_${f.name.toLowerCase()}';
      map.putIfAbsent(key, () => []).add(f);
    }

    final duplicateGroups = <DuplicateGroup>[];
    for (final entry in map.entries) {
      if (entry.value.length > 1) {
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
}

final storageOptimizerServiceProvider = Provider<StorageOptimizerService>((ref) {
  return StorageOptimizerService(
    fileVaultService: ref.read(fileVaultServiceProvider),
    videoVaultService: ref.read(videoVaultServiceProvider),
    docVaultService: ref.read(documentVaultServiceProvider),
  );
});
