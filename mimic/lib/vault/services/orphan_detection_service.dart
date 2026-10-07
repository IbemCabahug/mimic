// lib/vault/services/orphan_detection_service.dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/services/platform_service.dart';
import 'document_vault_service.dart';
import 'file_vault_service.dart';
import 'video_vault_service.dart';

/// The result of an orphan scan across the vault filesystem and databases.
class OrphanScanResult {
  /// Total number of files found inside the vault_files storage directory.
  final int totalFilesOnDisk;

  /// Number of files on disk that match a valid active database ID.
  final int trackedFilesOnDisk;

  /// Valid encrypted blobs on disk with NO matching database record in SQLite or Secure Storage.
  final List<File> unreferencedBlobs;

  /// Stale temporary files (e.g. interrupted import files: `*_import_plain_*`, `*_import_ctr_*`, `_tmp*`).
  final List<File> staleTempFiles;

  /// IDs that are registered in the database, but whose physical file is missing from disk.
  final List<String> missingDatabaseIds;

  /// Total bytes consumed by unreferenced blobs.
  final int unreferencedBytes;

  /// Total bytes consumed by stale temporary files.
  final int staleTempBytes;

  const OrphanScanResult({
    required this.totalFilesOnDisk,
    required this.trackedFilesOnDisk,
    required this.unreferencedBlobs,
    required this.staleTempFiles,
    required this.missingDatabaseIds,
    required this.unreferencedBytes,
    required this.staleTempBytes,
  });

  /// Total count of all orphaned artifacts (ghost blobs + stale temp files).
  int get totalOrphansCount => unreferencedBlobs.length + staleTempFiles.length;

  /// Total bytes recoverable by purging all orphans.
  int get totalReclaimableBytes => unreferencedBytes + staleTempBytes;

  /// Whether any orphaned files exist on disk.
  bool get hasOrphans => totalOrphansCount > 0;
}

/// The result of an orphan purge operation.
class OrphanPurgeResult {
  /// The number of orphaned files successfully deleted from disk.
  final int deletedCount;

  /// Total bytes of storage reclaimed.
  final int reclaimedBytes;

  /// Any files that failed to be deleted due to filesystem/permission errors.
  final List<String> failedDeletions;

  const OrphanPurgeResult({
    required this.deletedCount,
    required this.reclaimedBytes,
    required this.failedDeletions,
  });
}

/// Service that identifies and cleans orphaned files and stale temporary
/// artifacts in the vault storage directory (F11).
class OrphanDetectionService {
  final PlatformService _platformService;
  final FileVaultService _fileVaultService;
  final VideoVaultService _videoVaultService;
  final DocumentVaultService _documentVaultService;

  OrphanDetectionService(
    this._platformService,
    this._fileVaultService,
    this._videoVaultService,
    this._documentVaultService,
  );

  /// Scans the vault directory and reconciles disk files against database entries.
  ///
  /// [tempGracePeriod]: Temporary files modified within this duration are considered
  /// potentially active imports and are NOT classified as stale orphans. Defaults to 5 minutes.
  Future<OrphanScanResult> scanOrphans({
    Duration tempGracePeriod = const Duration(minutes: 5),
  }) async {
    if (_platformService.isWeb()) {
      return const OrphanScanResult(
        totalFilesOnDisk: 0,
        trackedFilesOnDisk: 0,
        unreferencedBlobs: [],
        staleTempFiles: [],
        missingDatabaseIds: [],
        unreferencedBytes: 0,
        staleTempBytes: 0,
      );
    }

    // 1. Gather all tracked IDs from active database and secure storage records.
    final photos = await _fileVaultService.getAllPhotos();
    final videos = await _videoVaultService.getAllVideos();
    final documents = await _documentVaultService.listDocuments();

    final photoIds = photos.map((p) => p.id).toSet();
    final videoIds = videos.map((v) => v.id).toSet();
    final documentIds = documents.map((d) => d.id).toSet();

    final trackedIds = <String>{...photoIds, ...videoIds, ...documentIds};

    // 2. Resolve the vault directory.
    final probeFile = await _platformService.resolveVaultFile('.probe');
    final vaultDir = probeFile.parent;

    if (!await vaultDir.exists()) {
      return OrphanScanResult(
        totalFilesOnDisk: 0,
        trackedFilesOnDisk: 0,
        unreferencedBlobs: const [],
        staleTempFiles: const [],
        missingDatabaseIds: trackedIds.toList(),
        unreferencedBytes: 0,
        staleTempBytes: 0,
      );
    }

    // 3. Inspect directory contents on disk.
    int totalFilesOnDisk = 0;
    int trackedFilesOnDisk = 0;
    final unreferencedBlobs = <File>[];
    final staleTempFiles = <File>[];
    final foundTrackedIds = <String>{};
    int unreferencedBytes = 0;
    int staleTempBytes = 0;

    final now = DateTime.now();
    final entities = vaultDir.listSync(followLinks: false);

    for (final entity in entities) {
      if (entity is! File) continue;

      final filename = p.basename(entity.path);
      if (filename == '.probe') continue;

      totalFilesOnDisk++;

      if (trackedIds.contains(filename)) {
        trackedFilesOnDisk++;
        foundTrackedIds.add(filename);
      } else {
        // Not a tracked ID. Check if it's a temporary import or conversion artifact.
        final isTempArtifact = _isTempFileName(filename);
        final fileStat = entity.statSync();

        if (isTempArtifact) {
          final age = now.difference(fileStat.modified);
          if (age >= tempGracePeriod) {
            staleTempFiles.add(entity);
            staleTempBytes += fileStat.size;
          }
        } else {
          // Regular file with no database row pointing to it: unreferenced blob.
          unreferencedBlobs.add(entity);
          unreferencedBytes += fileStat.size;
        }
      }
    }

    // 4. Find database rows whose backing file is missing on disk.
    final missingDatabaseIds = trackedIds.difference(foundTrackedIds).toList();

    return OrphanScanResult(
      totalFilesOnDisk: totalFilesOnDisk,
      trackedFilesOnDisk: trackedFilesOnDisk,
      unreferencedBlobs: unreferencedBlobs,
      staleTempFiles: staleTempFiles,
      missingDatabaseIds: missingDatabaseIds,
      unreferencedBytes: unreferencedBytes,
      staleTempBytes: staleTempBytes,
    );
  }

  /// Purges unreferenced blobs and stale temporary files from the vault directory.
  ///
  /// [deleteUnreferenced]: Deletes blobs that have no matching database record.
  /// [deleteStaleTemp]: Deletes stale import/conversion temporary files.
  ///
  /// CRITICAL SAFETY INVARIANT: Every file to be deleted is checked against the live
  /// set of database IDs before deletion. If a file name matches an active database ID,
  /// it is NEVER deleted under any circumstances.
  Future<OrphanPurgeResult> purgeOrphans({
    bool deleteUnreferenced = true,
    bool deleteStaleTemp = true,
    Duration tempGracePeriod = const Duration(minutes: 5),
  }) async {
    final scan = await scanOrphans(tempGracePeriod: tempGracePeriod);

    // Re-query database to ensure absolute freshness before deleting anything.
    final photos = await _fileVaultService.getAllPhotos();
    final videos = await _videoVaultService.getAllVideos();
    final documents = await _documentVaultService.listDocuments();

    final liveTrackedIds = <String>{
      ...photos.map((p) => p.id),
      ...videos.map((v) => v.id),
      ...documents.map((d) => d.id),
    };

    final filesToDelete = <File>[];
    if (deleteUnreferenced) {
      filesToDelete.addAll(scan.unreferencedBlobs);
    }
    if (deleteStaleTemp) {
      filesToDelete.addAll(scan.staleTempFiles);
    }

    int deletedCount = 0;
    int reclaimedBytes = 0;
    final failedDeletions = <String>[];

    for (final file in filesToDelete) {
      final filename = p.basename(file.path);

      // SAFETY INVARIANT: never touch an active database record.
      if (liveTrackedIds.contains(filename)) {
        continue;
      }

      try {
        final size = file.lengthSync();
        await file.delete();
        deletedCount++;
        reclaimedBytes += size;
      } catch (e) {
        failedDeletions.add('$filename: $e');
      }
    }

    return OrphanPurgeResult(
      deletedCount: deletedCount,
      reclaimedBytes: reclaimedBytes,
      failedDeletions: failedDeletions,
    );
  }

  /// Identifies temporary files created during import or conversion.
  bool _isTempFileName(String filename) {
    if (filename.contains('_import_plain_')) return true;
    if (filename.contains('_import_ctr_')) return true;
    if (filename.startsWith('_tmp')) return true;
    if (filename.endsWith('.tmp')) return true;
    if (filename.endsWith('.part')) return true;
    return false;
  }
}

final orphanDetectionServiceProvider = Provider<OrphanDetectionService>((ref) {
  return OrphanDetectionService(
    ref.read(platformServiceProvider),
    ref.read(fileVaultServiceProvider),
    ref.read(videoVaultServiceProvider),
    ref.read(documentVaultServiceProvider),
  );
});
