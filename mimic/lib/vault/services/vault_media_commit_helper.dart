import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/services/platform_service.dart';
import '../crypto/vault_crypto.dart';

const String kImportStagingDirName = '.import_staging';

/// Shared staging, streaming SHA-256, integrity verification, and atomic
/// publish helpers used by both [FileVaultService] and [VideoVaultService].
class VaultMediaCommitHelper {
  const VaultMediaCommitHelper._();

  static Future<File> resolveStagingFile(
    PlatformService platformService,
    String destId,
  ) async {
    final finalFile = await platformService.resolveVaultFile(destId);
    final stagingDir = Directory(
      p.join(finalFile.parent.path, kImportStagingDirName),
    );
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }
    return File(p.join(stagingDir.path, '$destId.part'));
  }

  /// Safely removes ONLY coordinator-owned `.part` staging files inside
  /// `<vaultDir>/.import_staging`. Never cleans unrelated temp directories.
  static Future<void> cleanupStagingDirectory(
    PlatformService platformService,
  ) async {
    try {
      final probe = await platformService.resolveVaultFile('__staging_probe__');
      final stagingDir = Directory(
        p.join(probe.parent.path, kImportStagingDirName),
      );
      if (!await stagingDir.exists()) return;
      await for (final entity in stagingDir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } on UnsupportedError {
      // Web, unsupported platform, or minimal test fake without disk paths.
    } on MissingPluginException {
      // Platform channel unavailable (e.g., widget test teardown race).
    }
  }

  /// Computes a SHA-256 hex digest using fixed 256 KB buffered reads so large
  /// videos/photos never allocate full-file byte arrays in memory and locks can
  /// abort cleanly mid-hash.
  static Future<String> computeFileSha256Streaming(
    File file, {
    bool Function()? shouldAbort,
    void Function(int bytesProcessed)? onBytesProgress,
  }) async {
    if (shouldAbort != null && shouldAbort()) {
      throw const OperationCancelledException();
    }
    late final Digest result;
    final digestSink = ChunkedConversionSink<Digest>.withCallback(
      (chunks) => result = chunks.single,
    );
    final byteSink = sha256.startChunkedConversion(digestSink);
    final raf = await file.open(mode: FileMode.read);
    var totalBytesRead = 0;
    try {
      final buffer = Uint8List(256 * 1024);
      while (true) {
        if (shouldAbort != null && shouldAbort()) {
          throw const OperationCancelledException();
        }
        final bytesRead = await raf.readInto(buffer);
        if (bytesRead <= 0) break;
        if (shouldAbort != null && shouldAbort()) {
          throw const OperationCancelledException();
        }
        byteSink.add(Uint8List.sublistView(buffer, 0, bytesRead));
        totalBytesRead += bytesRead;
        onBytesProgress?.call(totalBytesRead);
      }
      byteSink.close();
      return result.toString();
    } finally {
      await raf.close();
    }
  }

  /// Verifies authenticated output on [stagingFile], re-checks session epoch
  /// and cancellation, and atomically publishes [stagingFile] to [destFile].
  static Future<void> verifyAndPublishStagingFile({
    required File stagingFile,
    required File destFile,
    required VaultCrypto crypto,
    bool verifyIntegrity = true,
    bool Function()? isEpochValid,
    bool Function()? shouldAbort,
  }) async {
    void assertActive() {
      if (shouldAbort != null && shouldAbort()) {
        throw const OperationCancelledException();
      }
      if (!crypto.isUnlocked || (isEpochValid != null && !isEpochValid())) {
        throw const OperationCancelledException(
          'Vault locked or unlock session changed before commit',
        );
      }
    }

    assertActive();
    if (!await stagingFile.exists()) {
      throw const FileSystemException('Encrypted staging file is missing');
    }

    if (verifyIntegrity) {
      final status = await crypto.verifyFileIntegrity(stagingFile);
      if (status != BlobIntegrityStatus.healthy) {
        try {
          if (await stagingFile.exists()) await stagingFile.delete();
        } catch (_) {}
        if (status == BlobIntegrityStatus.vaultLocked) {
          throw const OperationCancelledException(
            'Vault locked during integrity check',
          );
        }
        throw CorruptedMediaFileException(
          'Encrypted staging verification failed: $status',
        );
      }
    }

    assertActive();

    final parent = destFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await destFile.exists()) {
      await destFile.delete();
    }
    try {
      await stagingFile.rename(destFile.path);
    } on FileSystemException {
      // Cross-device fallback if OS separates paths (unexpected under vault_files).
      await stagingFile.copy(destFile.path);
      if (await stagingFile.exists()) {
        await stagingFile.delete();
      }
    }
  }

  /// Safely deletes a blob or staging file when cleaning up an uncommitted failure.
  static Future<void> deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
