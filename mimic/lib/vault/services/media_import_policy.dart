import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Shared media import policy across photo and video vault imports.
///
/// Enforces an explicit initial per-selection maximum of 100 items so users
/// are no longer constrained by wechat_assets_picker's default limit of 9,
/// while keeping batch memory usage bounded and supporting appended batches.
const int kMaxMediaImportSelection = 100;

/// User-facing explanation shown when preparing or configuring a media selection.
const String kMediaImportLimitBanner =
    'Select up to $kMaxMediaImportSelection items per batch — you can add more batches anytime.';

/// Reserve buffer required above estimated source size before starting an item.
const int kImportStorageReserveBytes = 8 * 1024 * 1024;

/// Supported vault media categories handled by the import coordinator.
enum ImportMediaKind { photo, video }

/// Captures the vault scope targeted at enqueue time rather than inferring it
/// from whichever screen happens to be visible later.
enum VaultScopeKind { realNormal }

class VaultImportScope {
  final VaultScopeKind kind;

  const VaultImportScope({this.kind = VaultScopeKind.realNormal});

  String get storageValue {
    switch (kind) {
      case VaultScopeKind.realNormal:
        return 'real_normal';
    }
  }

  static VaultImportScope fromStorageValue(String value) {
    return const VaultImportScope(kind: VaultScopeKind.realNormal);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VaultImportScope && other.kind == kind;
  }

  @override
  int get hashCode => kind.hashCode;
}

class MediaImportPolicy {
  const MediaImportPolicy._();

  static const int maxAssetsPerBatch = kMaxMediaImportSelection;

  /// Builds the shared asset picker configuration with an explicit [maxAssets]
  /// bound so picker behavior cannot silently regress to the library default (9).
  static AssetPickerConfig buildPickerConfig(
    ImportMediaKind kind, {
    int maxAssets = maxAssetsPerBatch,
  }) {
    final boundedMax = maxAssets < 1 ? 1 : maxAssets;
    return AssetPickerConfig(
      maxAssets: boundedMax,
      requestType: kind == ImportMediaKind.photo
          ? RequestType.image
          : RequestType.video,
      textDelegate: const EnglishAssetPickerTextDelegate(),
    );
  }
}

/// Lightweight metadata descriptor produced by gallery selection.
///
/// Intentionally holds only durable asset identity and lightweight display/type
/// hints rather than raw file bytes.
class MediaSourceRef {
  final String sourceAssetId;
  final ImportMediaKind kind;
  final String displayName;
  final String mimeType;
  final int durationSeconds;
  final int? expectedSizeBytes;

  const MediaSourceRef({
    required this.sourceAssetId,
    required this.kind,
    required this.displayName,
    required this.mimeType,
    this.durationSeconds = 0,
    this.expectedSizeBytes,
  });
}

enum MediaSourceResolutionStatus {
  ready,
  missing,
  permissionDenied,
  cloudUnavailable,
  unreadable,
}

class ResolvedMediaSource {
  final MediaSourceResolutionStatus status;
  final String? localFilePath;
  final String mimeType;
  final String displayName;
  final int durationSeconds;
  final int? sizeBytes;
  final String? errorCode;
  final String? safeReason;

  const ResolvedMediaSource._({
    required this.status,
    required this.mimeType,
    required this.displayName,
    this.localFilePath,
    this.durationSeconds = 0,
    this.sizeBytes,
    this.errorCode,
    this.safeReason,
  });

  const ResolvedMediaSource.ready({
    required String localFilePath,
    required String mimeType,
    required String displayName,
    int durationSeconds = 0,
    int? sizeBytes,
  }) : this._(
         status: MediaSourceResolutionStatus.ready,
         localFilePath: localFilePath,
         mimeType: mimeType,
         displayName: displayName,
         durationSeconds: durationSeconds,
         sizeBytes: sizeBytes,
       );

  const ResolvedMediaSource.unavailable({
    required MediaSourceResolutionStatus status,
    required String mimeType,
    required String displayName,
    required String errorCode,
    String? safeReason,
  }) : this._(
         status: status,
         mimeType: mimeType,
         displayName: displayName,
         errorCode: errorCode,
         safeReason: safeReason,
       );

  bool get isReady =>
      status == MediaSourceResolutionStatus.ready && localFilePath != null;
}

class MediaDeleteResult {
  final Set<String> deletedIds;
  final Set<String> keptIds;
  final bool permissionDenied;
  final String? errorCode;

  const MediaDeleteResult({
    required this.deletedIds,
    required this.keptIds,
    this.permissionDenied = false,
    this.errorCode,
  });

  bool get allDeleted =>
      keptIds.isEmpty && !permissionDenied && errorCode == null;
}
