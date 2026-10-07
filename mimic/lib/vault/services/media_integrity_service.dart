// lib/vault/services/media_integrity_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';
import 'document_vault_service.dart';
import 'file_vault_service.dart';
import 'video_vault_service.dart';

/// The result of an integrity check on a single blob (F10).
class BlobIntegrityReport {
  final String id;
  final BlobIntegrityStatus status;
  final int fileSizeBytes;
  final String? detail;

  const BlobIntegrityReport({
    required this.id,
    required this.status,
    required this.fileSizeBytes,
    this.detail,
  });

  bool get isHealthy => status == BlobIntegrityStatus.healthy;
}

/// A comprehensive summary of an integrity verification sweep across the vault (F10).
class MediaIntegritySummary {
  final int totalChecked;
  final int healthyCount;
  final int corruptedCount;
  final List<BlobIntegrityReport> issues;

  const MediaIntegritySummary({
    required this.totalChecked,
    required this.healthyCount,
    required this.corruptedCount,
    required this.issues,
  });

  bool get hasIssues => issues.isNotEmpty;
}

/// Service that verifies mid-file and cryptographic integrity across vault files (F10).
///
/// Unlike basic format sniffing which only checks the first 8 bytes, this service
/// checks internal structure, block alignment, and streams full HMAC authentication
/// without loading entire files into memory.
class MediaIntegrityService {
  final PlatformService _platformService;
  final VaultCrypto _crypto;
  final FileVaultService _fileVaultService;
  final VideoVaultService _videoVaultService;
  final DocumentVaultService _documentVaultService;

  MediaIntegrityService(
    this._platformService,
    this._crypto,
    this._fileVaultService,
    this._videoVaultService,
    this._documentVaultService,
  );

  /// Checks the integrity of a single vault blob by its [id].
  Future<BlobIntegrityReport> checkBlob(String id) async {
    final file = await _platformService.resolveVaultFile(id);
    if (!await file.exists()) {
      return BlobIntegrityReport(
        id: id,
        status: BlobIntegrityStatus.fileNotFound,
        fileSizeBytes: 0,
        detail: 'File not found on disk',
      );
    }

    final size = await file.length();
    final status = await _crypto.verifyFileIntegrity(file);
    return BlobIntegrityReport(
      id: id,
      status: status,
      fileSizeBytes: size,
      detail: status == BlobIntegrityStatus.healthy ? null : status.name,
    );
  }

  /// Verifies all tracked media files in the vault (photos, videos, documents).
  ///
  /// [onProgress] is invoked after each file is inspected with (completed, total).
  Future<MediaIntegritySummary> verifyAllMedia({
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_platformService.isWeb()) {
      return const MediaIntegritySummary(
        totalChecked: 0,
        healthyCount: 0,
        corruptedCount: 0,
        issues: [],
      );
    }

    final photos = await _fileVaultService.getAllPhotos();
    final videos = await _videoVaultService.getAllVideos();
    final documents = await _documentVaultService.listDocuments();

    final allIds = <String>{
      ...photos.map((p) => p.id),
      ...videos.map((v) => v.id),
      ...documents.map((d) => d.id),
    }.toList();

    int completed = 0;
    int healthy = 0;
    int corrupted = 0;
    final issues = <BlobIntegrityReport>[];

    for (final id in allIds) {
      final report = await checkBlob(id);
      completed++;
      onProgress?.call(completed, allIds.length);

      if (report.isHealthy) {
        healthy++;
      } else {
        corrupted++;
        issues.add(report);
      }
    }

    return MediaIntegritySummary(
      totalChecked: allIds.length,
      healthyCount: healthy,
      corruptedCount: corrupted,
      issues: issues,
    );
  }
}

final mediaIntegrityServiceProvider = Provider<MediaIntegrityService>((ref) {
  return MediaIntegrityService(
    ref.read(platformServiceProvider),
    ref.read(vaultCryptoProvider),
    ref.read(fileVaultServiceProvider),
    ref.read(videoVaultServiceProvider),
    ref.read(documentVaultServiceProvider),
  );
});
