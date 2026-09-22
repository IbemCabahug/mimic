// lib/vault/crypto/legacy_blob_migration.dart
//
// F24 — migrate legacy blob formats to c2 while the system_key can still
// read them.
//
// Three historical on-disk formats predate c2 (MVKEYc2\0, AES-CTR under the
// master DEK): cbcV1 (MVKEYv1\0, AES-CBC under the DEK), ctrV1/c1
// (MVKEYc1\0, AES-CTR under the device-local system key) and legacyNoHeader
// (raw IV prefix, AES-CBC under the system key). The system key is NOT
// PIN-derived and is NOT covered by the recovery phrase — it dies with an
// uninstall, so anything keyed to it is one reinstall away from being lost
// forever, and portable exports (F9) cannot honestly cover it.
//
// This service converts every system-keyed blob to c2 under the live master
// DEK. Per file: decrypt to a temp plaintext, re-encrypt to a temp c2 blob,
// VERIFY by decrypting the new blob back and comparing SHA-256 digests
// against the plaintext, then atomically rename it over the original. The
// original file is never touched until the verified replacement exists, so a
// crash mid-migration leaves the old (still readable, on this device) blob
// in place. Temp plaintexts are secure-deleted.
//
// NOT done here, deliberately: removing the legacy decrypt paths. That is
// only honest once diagnostics show zero legacy blobs in the wild, because
// an interrupted migration (app killed mid-run) must still be able to read
// the files it has not reached yet.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/auto_lock.dart';
import '../util/storage_space.dart';
import 'media_format.dart';
import 'vault_crypto.dart';

/// Outcome of one [LegacyBlobMigration.migrateAll] run.
class LegacyMigrationReport {
  /// Files seen in the vault directory.
  final int scanned;

  /// Files already keyed by the master DEK (c2, or the older DEK-keyed CBC
  /// v1) — nothing to do.
  final int alreadyModern;

  /// Files converted to c2 and verified.
  final int migrated;

  /// Files that could not be converted (corrupt header/length, decrypt
  /// failure, verify mismatch, or vault locked mid-run). Left untouched.
  final int failed;

  /// Files skipped for now because free disk space could not safely hold the
  /// working copies. Retried on the next run.
  final int deferred;

  final List<String> failedIds;
  final List<String> deferredIds;

  const LegacyMigrationReport({
    required this.scanned,
    required this.alreadyModern,
    required this.migrated,
    required this.failed,
    required this.deferred,
    required this.failedIds,
    required this.deferredIds,
  });

  Map<String, dynamic> toJson() => {
        'scanned': scanned,
        'alreadyModern': alreadyModern,
        'migrated': migrated,
        'failed': failed,
        'deferred': deferred,
        'failedIds': failedIds,
        'deferredIds': deferredIds,
      };

  static LegacyMigrationReport fromJson(Map<String, dynamic> json) =>
      LegacyMigrationReport(
        scanned: (json['scanned'] as num?)?.toInt() ?? 0,
        alreadyModern: (json['alreadyModern'] as num?)?.toInt() ?? 0,
        migrated: (json['migrated'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        deferred: (json['deferred'] as num?)?.toInt() ?? 0,
        failedIds: (json['failedIds'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        deferredIds: (json['deferredIds'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
      );
}

/// A minimal [Sink] for the chunked SHA-256 conversion, so this file does
/// not need package:convert (which is only a transitive dependency here).
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class LegacyBlobMigration {
  LegacyBlobMigration({VaultCrypto? crypto}) : _crypto = crypto ?? VaultCrypto.instance;

  final VaultCrypto _crypto;

  /// SharedPreferences key holding the last run's summary JSON.
  static const String lastRunPrefsKey = 'legacy_blob_migration_last_run';

  /// Working-copy suffixes. A leftover from a killed run is swept on the next
  /// run; the original is only ever replaced by an atomic rename.
  static const String _plainSuffix = '.f24_plain';
  static const String _c2Suffix = '.f24_c2';
  static const String _verifySuffix = '.f24_verify';

  /// Converts up to [maxFiles] legacy blobs (0 = no limit) and returns the
  /// run's honest report. Safe to call again: already-modern files are
  /// skipped, failed files are retried, deferred files wait for space.
  Future<LegacyMigrationReport> migrateAll({int maxFiles = 0}) async {
    final report = await _run(maxFiles: maxFiles);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastRunPrefsKey, jsonEncode(report.toJson()));
    } catch (_) {
      // The persisted summary is a convenience for diagnostics, not a
      // correctness requirement; a failed write changes nothing.
    }
    return report;
  }

  Future<LegacyMigrationReport> _run({required int maxFiles}) async {
    final vaultDir = Directory('${(await _docsDir()).path}/vault_files');
    if (!await vaultDir.exists()) {
      return const LegacyMigrationReport(
        scanned: 0,
        alreadyModern: 0,
        migrated: 0,
        failed: 0,
        deferred: 0,
        failedIds: [],
        deferredIds: [],
      );
    }

    await _sweepStaleTemps(vaultDir);

    var scanned = 0;
    var alreadyModern = 0;
    var migrated = 0;
    var failed = 0;
    var deferred = 0;
    final failedIds = <String>[];
    final deferredIds = <String>[];
    var converted = 0;

    await for (final entity in vaultDir.list()) {
      if (maxFiles > 0 && converted >= maxFiles) break;
      if (entity is! File) continue;
      if (entity.path.endsWith(_plainSuffix) ||
          entity.path.endsWith(_c2Suffix) ||
          entity.path.endsWith(_verifySuffix)) {
        continue;
      }

      scanned++;
      final id = entity.uri.pathSegments.last;

      List<int> head;
      try {
        final raf = await entity.open(mode: FileMode.read);
        try {
          head = await raf.read(8);
        } finally {
          await raf.close();
        }
      } catch (_) {
        failed++;
        failedIds.add(id);
        continue;
      }

      final format = classifyMediaHeader(head);
      if (format == MediaBlobFormat.ctrV2 || format == MediaBlobFormat.cbcV1) {
        alreadyModern++;
        continue;
      }

      // ctrV1 (system-key CTR) or legacyNoHeader (system-key CBC): the two
      // formats that die with the device key. Convert them.
      try {
        final ok = await _migrateFile(entity);
        if (ok) {
          migrated++;
          converted++;
        } else {
          deferred++;
          deferredIds.add(id);
        }
      } catch (_) {
        failed++;
        failedIds.add(id);
        await _cleanupTemps(entity);
      }
    }

    return LegacyMigrationReport(
      scanned: scanned,
      alreadyModern: alreadyModern,
      migrated: migrated,
      failed: failed,
      deferred: deferred,
      failedIds: failedIds,
      deferredIds: deferredIds,
    );
  }

  /// Converts one blob. Returns false when deferred (not enough free space
  /// for the verified working copies); throws on real failures. The original
  /// file is replaced only after the verified c2 replacement exists.
  Future<bool> _migrateFile(File original) async {
    final size = await original.length();
    final dirPath = original.parent.path;

    // Working copies: plaintext + c2 + verification plaintext coexist with
    // the original during verification. Require 3x the blob plus margin, so
    // a nearly-full disk defers the file instead of filling itself.
    final freeBytes = await StorageSpace.availableBytes(dirPath);
    final requiredBytes = size * 3 + (8 * 1024 * 1024);
    if (freeBytes < requiredBytes) {
      return false;
    }

    final plainTmp = File('${original.path}$_plainSuffix');
    final c2Tmp = File('${original.path}$_c2Suffix');
    final verifyTmp = File('${original.path}$_verifySuffix');

    try {
      // 1. Decrypt the legacy blob (routes c1 / legacyNoHeader internally).
      await _crypto.decryptStreamSystem(original, plainTmp);

      // 2. Re-encrypt under the master DEK as c2. encryptStreamSystemCtr is
      //    the c2 writer (MVKEYc2\0 + IV + CTR under the DEK, run in the
      //    background isolate) — encryptStreamSystem writes the older CBC v1
      //    format, which is NOT the migration target.
      await _crypto.encryptStreamSystemCtr(plainTmp, c2Tmp);

      // 3. Verify: decrypt the new blob back and compare digests. A migration
      //    that cannot prove itself must not replace the original.
      await _crypto.decryptStreamSystem(c2Tmp, verifyTmp);
      final plainDigest = await _fileDigest(plainTmp);
      final verifyDigest = await _fileDigest(verifyTmp);

      final headerOk = await _hasClassification(c2Tmp, MediaBlobFormat.ctrV2);
      if (!headerOk || plainDigest.toString() != verifyDigest.toString()) {
        throw StateError('F24 verification mismatch for ${original.path}');
      }

      // 4. Atomic replace, then destroy the plaintext working copies.
      await c2Tmp.rename(original.path);
      await AutoLock.secureDeleteFile(plainTmp);
      await AutoLock.secureDeleteFile(verifyTmp);
      return true;
    } catch (_) {
      await _cleanupTemps(original);
      rethrow;
    }
  }

  /// Deletes leftover working copies from a run that was killed mid-file.
  /// The originals were never touched (only the final rename replaces them),
  /// so this only ever discards recoverable partials.
  Future<void> _sweepStaleTemps(Directory vaultDir) async {
    await for (final entity in vaultDir.list()) {
      if (entity is! File) continue;
      if (entity.path.endsWith(_plainSuffix) ||
          entity.path.endsWith(_c2Suffix) ||
          entity.path.endsWith(_verifySuffix)) {
        try {
          await AutoLock.secureDeleteFile(entity);
        } catch (_) {}
      }
    }
  }

  Future<void> _cleanupTemps(File original) async {
    for (final suffix in [_plainSuffix, _c2Suffix, _verifySuffix]) {
      final tmp = File('${original.path}$suffix');
      if (await tmp.exists()) {
        try {
          await AutoLock.secureDeleteFile(tmp);
        } catch (_) {}
      }
    }
  }

  Future<bool> _hasClassification(File file, MediaBlobFormat expected) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final head = await raf.read(8);
      return classifyMediaHeader(head) == expected;
    } catch (_) {
      return false;
    } finally {
      await raf.close();
    }
  }

  Future<Digest> _fileDigest(File file) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.value!;
  }

  /// The app documents directory, resolved the same way the exporter does it.
  /// The injected [PlatformService] is accepted for symmetry/future use; the
  /// directory itself comes from path_provider, which the tests mock.
  Future<Directory> _docsDir() async {
    if (!kIsWeb) {
      return getApplicationDocumentsDirectory();
    }
    throw StateError('LegacyBlobMigration is not supported on web');
  }
}

