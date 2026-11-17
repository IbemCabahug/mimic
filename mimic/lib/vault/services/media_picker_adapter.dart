import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'media_import_policy.dart';

/// Abstracts gallery permissions, asset picking, durable source re-resolution
/// (`AssetEntity.fromId`), and OS original deletion so both production code and
/// deterministic test harnesses share the same import lifecycle contracts.
abstract class MediaPickerAdapter {
  Future<PermissionState> requestPermission(ImportMediaKind kind);

  Future<List<MediaSourceRef>?> pickAssets(
    BuildContext context, {
    required ImportMediaKind kind,
    int maxAssets = kMaxMediaImportSelection,
  });

  Future<ResolvedMediaSource> resolveSource(MediaSourceRef ref);

  Future<MediaDeleteResult> deleteOriginals(List<String> assetIds);
}

class ProductionMediaPickerAdapter implements MediaPickerAdapter {
  const ProductionMediaPickerAdapter();

  RequestType _requestTypeFor(ImportMediaKind kind) =>
      kind == ImportMediaKind.photo ? RequestType.image : RequestType.video;

  @override
  Future<PermissionState> requestPermission(ImportMediaKind kind) {
    return PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: _requestTypeFor(kind),
          mediaLocation: false,
        ),
      ),
    );
  }

  @override
  Future<List<MediaSourceRef>?> pickAssets(
    BuildContext context, {
    required ImportMediaKind kind,
    int maxAssets = kMaxMediaImportSelection,
  }) async {
    final config = MediaImportPolicy.buildPickerConfig(
      kind,
      maxAssets: maxAssets,
    );
    final selected = await AssetPicker.pickAssets(
      context,
      pickerConfig: config,
      useRootNavigator: false,
    );
    if (selected == null) return null;

    final refs = <MediaSourceRef>[];
    for (final entity in selected) {
      final title = await entity.titleAsync;
      final mime =
          await entity.mimeTypeAsync ??
          (kind == ImportMediaKind.photo ? 'image/jpeg' : 'video/mp4');
      final fallbackExt = kind == ImportMediaKind.photo ? 'jpg' : 'mp4';
      final safeName = title.trim().isNotEmpty
          ? title.trim()
          : '${kind.name}_${refs.length + 1}.$fallbackExt';
      refs.add(
        MediaSourceRef(
          sourceAssetId: entity.id,
          kind: kind,
          displayName: safeName,
          mimeType: mime,
          durationSeconds: kind == ImportMediaKind.video ? entity.duration : 0,
        ),
      );
    }
    return refs;
  }

  @override
  Future<ResolvedMediaSource> resolveSource(MediaSourceRef ref) async {
    try {
      final perm = await requestPermission(ref.kind);
      if (!perm.hasAccess) {
        return ResolvedMediaSource.unavailable(
          status: MediaSourceResolutionStatus.permissionDenied,
          mimeType: ref.mimeType,
          displayName: ref.displayName,
          errorCode: 'permission_denied',
          safeReason: 'Gallery permission required to access source',
        );
      }

      final entity = await AssetEntity.fromId(ref.sourceAssetId);
      if (entity == null) {
        return ResolvedMediaSource.unavailable(
          status: MediaSourceResolutionStatus.missing,
          mimeType: ref.mimeType,
          displayName: ref.displayName,
          errorCode: 'source_missing',
          safeReason: 'Original media item is no longer in library',
        );
      }

      final locallyAvailable = await entity.isLocallyAvailable(isOrigin: true);
      final file = await entity.originFile;
      if (!locallyAvailable && file == null) {
        return ResolvedMediaSource.unavailable(
          status: MediaSourceResolutionStatus.cloudUnavailable,
          mimeType: ref.mimeType,
          displayName: ref.displayName,
          errorCode: 'cloud_unavailable',
          safeReason: 'Original media is not downloaded locally',
        );
      }
      if (file == null || !await file.exists()) {
        return ResolvedMediaSource.unavailable(
          status: MediaSourceResolutionStatus.missing,
          mimeType: ref.mimeType,
          displayName: ref.displayName,
          errorCode: 'source_missing',
          safeReason: 'Source file could not be located on disk',
        );
      }

      int sizeBytes;
      try {
        sizeBytes = await file.length();
      } on FileSystemException {
        return ResolvedMediaSource.unavailable(
          status: MediaSourceResolutionStatus.unreadable,
          mimeType: ref.mimeType,
          displayName: ref.displayName,
          errorCode: 'source_unreadable',
          safeReason: 'Source file could not be read',
        );
      }

      final resolvedMime = await entity.mimeTypeAsync ?? ref.mimeType;
      final resolvedTitle = (await entity.titleAsync).trim();
      return ResolvedMediaSource.ready(
        localFilePath: file.path,
        mimeType: resolvedMime,
        displayName: resolvedTitle.isNotEmpty ? resolvedTitle : ref.displayName,
        durationSeconds: ref.kind == ImportMediaKind.video
            ? entity.duration
            : 0,
        sizeBytes: sizeBytes,
      );
    } on PlatformException catch (e) {
      final isPerm =
          e.code.toLowerCase().contains('permission') ||
          e.code.toLowerCase().contains('denied');
      return ResolvedMediaSource.unavailable(
        status: isPerm
            ? MediaSourceResolutionStatus.permissionDenied
            : MediaSourceResolutionStatus.unreadable,
        mimeType: ref.mimeType,
        displayName: ref.displayName,
        errorCode: isPerm ? 'permission_denied' : 'source_unreadable',
        safeReason: isPerm
            ? 'Gallery permission denied'
            : 'Unable to access gallery item',
      );
    } catch (_) {
      return ResolvedMediaSource.unavailable(
        status: MediaSourceResolutionStatus.unreadable,
        mimeType: ref.mimeType,
        displayName: ref.displayName,
        errorCode: 'source_unreadable',
        safeReason: 'Unable to access gallery item',
      );
    }
  }

  @override
  Future<MediaDeleteResult> deleteOriginals(List<String> assetIds) async {
    final requested = assetIds.where((id) => id.isNotEmpty).toList();
    if (requested.isEmpty) {
      return const MediaDeleteResult(
        deletedIds: <String>{},
        keptIds: <String>{},
      );
    }
    try {
      final deleted = await PhotoManager.editor.deleteWithIds(requested);
      final deletedSet = deleted.where((id) => requested.contains(id)).toSet();
      final keptSet = requested.where((id) => !deletedSet.contains(id)).toSet();
      return MediaDeleteResult(deletedIds: deletedSet, keptIds: keptSet);
    } on PlatformException catch (e) {
      final isPerm =
          e.code.toLowerCase().contains('permission') ||
          e.code.toLowerCase().contains('denied');
      return MediaDeleteResult(
        deletedIds: const <String>{},
        keptIds: requested.toSet(),
        permissionDenied: isPerm,
        errorCode: isPerm ? 'delete_permission_denied' : 'delete_failed',
      );
    } catch (_) {
      return MediaDeleteResult(
        deletedIds: const <String>{},
        keptIds: requested.toSet(),
        errorCode: 'delete_failed',
      );
    }
  }
}

final mediaPickerAdapterProvider = Provider<MediaPickerAdapter>((ref) {
  return const ProductionMediaPickerAdapter();
});
