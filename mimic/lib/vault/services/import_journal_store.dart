import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../crypto/vault_crypto.dart';
import 'media_import_policy.dart';

const int kImportJournalSchemaVersion = 1;
const String kImportJournalDbFileName = 'import_jobs.db';

/// Process-wide hook registry so security wipe services can invalidate any active
/// import coordinator / open journal handles before deleting database artifacts.
class ImportJournalWipeRegistry {
  ImportJournalWipeRegistry._();
  static final Set<Future<void> Function()> _hooks = {};

  static void Function() register(Future<void> Function() hook) {
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }

  static Future<void> runAll() async {
    for (final hook in List<Future<void> Function()>.from(_hooks)) {
      try {
        await hook();
      } catch (_) {}
    }
  }
}

/// Durable lifecycle state for a persisted gallery import job.
enum ImportJobState {
  queued,
  preparing,
  encrypting,
  committing,
  pausedLocked,
  needsSource,
  savedOriginalKept,
  awaitingDeleteConfirmation,
  saved,
  failed,
  cancelled,
}

enum ImportJournalErrorKind {
  locked,
  corrupt,
  storageOrDbFailure,
  payloadAuthFailure,
}

class ImportJournalException implements Exception {
  final ImportJournalErrorKind kind;
  final String safeMessage;

  const ImportJournalException(this.kind, this.safeMessage);

  @override
  String toString() => 'ImportJournalException($kind): $safeMessage';
}

/// Sensitive job metadata encrypted with the unlocked vault key before hitting SQLite.
class ImportJobSensitivePayload {
  final String sourceAssetId;
  final String displayName;
  final String mimeType;
  final int durationSeconds;
  final int? expectedSizeBytes;
  final String? contentHash;
  final String? errorDetail;
  final bool originalDeletedConfirmed;

  const ImportJobSensitivePayload({
    required this.sourceAssetId,
    required this.displayName,
    required this.mimeType,
    this.durationSeconds = 0,
    this.expectedSizeBytes,
    this.contentHash,
    this.errorDetail,
    this.originalDeletedConfirmed = false,
  });

  ImportJobSensitivePayload copyWith({
    String? sourceAssetId,
    String? displayName,
    String? mimeType,
    int? durationSeconds,
    int? expectedSizeBytes,
    String? contentHash,
    String? errorDetail,
    bool clearErrorDetail = false,
    bool? originalDeletedConfirmed,
  }) {
    return ImportJobSensitivePayload(
      sourceAssetId: sourceAssetId ?? this.sourceAssetId,
      displayName: displayName ?? this.displayName,
      mimeType: mimeType ?? this.mimeType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      expectedSizeBytes: expectedSizeBytes ?? this.expectedSizeBytes,
      contentHash: contentHash ?? this.contentHash,
      errorDetail: clearErrorDetail ? null : (errorDetail ?? this.errorDetail),
      originalDeletedConfirmed:
          originalDeletedConfirmed ?? this.originalDeletedConfirmed,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'sourceAssetId': sourceAssetId,
    'displayName': displayName,
    'mimeType': mimeType,
    'durationSeconds': durationSeconds,
    if (expectedSizeBytes != null) 'expectedSizeBytes': expectedSizeBytes,
    if (contentHash != null) 'contentHash': contentHash,
    if (errorDetail != null) 'errorDetail': errorDetail,
    'originalDeletedConfirmed': originalDeletedConfirmed,
  };

  static ImportJobSensitivePayload fromJson(Map<String, dynamic> json) {
    return ImportJobSensitivePayload(
      sourceAssetId: json['sourceAssetId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Media item',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      expectedSizeBytes: (json['expectedSizeBytes'] as num?)?.toInt(),
      contentHash: json['contentHash'] as String?,
      errorDetail: json['errorDetail'] as String?,
      originalDeletedConfirmed:
          json['originalDeletedConfirmed'] as bool? ?? false,
    );
  }
}

/// Complete durable import job record combining opaque scheduling columns and
/// decrypted sensitive payload (in memory while unlocked only).
class DurableImportJob {
  final String jobId;
  final String batchId;
  final String destId;
  final int enqueueOrder;
  final ImportMediaKind mediaKind;
  final VaultImportScope scope;
  final ImportJobState state;
  final int attemptCount;
  final String? stagingName;
  final String? committedVaultId;
  final String? errorCode;
  final bool needsDeleteConfirm;
  final int createdAtMs;
  final int updatedAtMs;
  final ImportJobSensitivePayload payload;

  const DurableImportJob({
    required this.jobId,
    required this.batchId,
    required this.destId,
    required this.enqueueOrder,
    required this.mediaKind,
    required this.scope,
    required this.state,
    required this.attemptCount,
    this.stagingName,
    this.committedVaultId,
    this.errorCode,
    this.needsDeleteConfirm = false,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.payload,
  });

  bool get isCommittedToVault =>
      committedVaultId != null && committedVaultId!.isNotEmpty;

  bool get isFinishedTerminal =>
      state == ImportJobState.saved ||
      state == ImportJobState.savedOriginalKept ||
      state == ImportJobState.cancelled ||
      state == ImportJobState.failed;

  bool get isRunnableOnResume =>
      state == ImportJobState.queued ||
      state == ImportJobState.preparing ||
      state == ImportJobState.encrypting ||
      state == ImportJobState.committing ||
      state == ImportJobState.pausedLocked;

  DurableImportJob copyWith({
    ImportJobState? state,
    int? attemptCount,
    String? stagingName,
    bool clearStagingName = false,
    String? committedVaultId,
    String? errorCode,
    bool clearErrorCode = false,
    bool? needsDeleteConfirm,
    int? updatedAtMs,
    ImportJobSensitivePayload? payload,
  }) {
    return DurableImportJob(
      jobId: jobId,
      batchId: batchId,
      destId: destId,
      enqueueOrder: enqueueOrder,
      mediaKind: mediaKind,
      scope: scope,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      stagingName: clearStagingName ? null : (stagingName ?? this.stagingName),
      committedVaultId: committedVaultId ?? this.committedVaultId,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      needsDeleteConfirm: needsDeleteConfirm ?? this.needsDeleteConfirm,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      payload: payload ?? this.payload,
    );
  }
}

/// Opaque scheduling-only view read without exposing or needing sensitive strings.
class OpaqueImportJobRow {
  final String jobId;
  final String batchId;
  final String destId;
  final int enqueueOrder;
  final ImportMediaKind mediaKind;
  final VaultImportScope scope;
  final ImportJobState state;
  final int attemptCount;
  final String? stagingName;
  final String? committedVaultId;
  final String? errorCode;
  final bool needsDeleteConfirm;
  final int createdAtMs;
  final int updatedAtMs;
  final String payloadEnc;

  const OpaqueImportJobRow({
    required this.jobId,
    required this.batchId,
    required this.destId,
    required this.enqueueOrder,
    required this.mediaKind,
    required this.scope,
    required this.state,
    required this.attemptCount,
    required this.stagingName,
    required this.committedVaultId,
    required this.errorCode,
    required this.needsDeleteConfirm,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.payloadEnc,
  });
}

/// Versioned encrypted SQLite persistence for gallery import jobs.
class ImportJournalStore {
  final VaultCrypto _crypto;
  final Future<String> Function()? _dbPathOverride;
  final DatabaseFactory? _databaseFactoryOverride;

  Database? _db;
  int _nextOrderFloor = 0;

  ImportJournalStore(
    this._crypto, {
    Future<String> Function()? dbPathOverride,
    DatabaseFactory? databaseFactoryOverride,
  }) : _dbPathOverride = dbPathOverride,
       _databaseFactoryOverride = databaseFactoryOverride;

  Future<String> resolveDbPath() async {
    final override = _dbPathOverride;
    if (override != null) {
      return override();
    }
    final dir = await getDatabasesPath();
    return p.join(dir, kImportJournalDbFileName);
  }

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    final path = await resolveDbPath();
    try {
      final parent = Directory(p.dirname(path));
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final factory = _databaseFactoryOverride ?? databaseFactory;
      final db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: kImportJournalSchemaVersion,
          onCreate: (db, version) async {
            await _createSchemaV1(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 1) {
              await _createSchemaV1(db);
            }
          },
        ),
      );
      try {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.rawQuery('PRAGMA synchronous = NORMAL');
      } catch (_) {}
      _db = db;
      return db;
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    } on FileSystemException {
      throw const ImportJournalException(
        ImportJournalErrorKind.storageOrDbFailure,
        'Import journal storage unavailable',
      );
    }
  }

  Future<void> _createSchemaV1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_jobs (
        job_id TEXT PRIMARY KEY,
        batch_id TEXT NOT NULL,
        dest_id TEXT NOT NULL,
        enqueue_order INTEGER NOT NULL,
        media_kind TEXT NOT NULL,
        scope TEXT NOT NULL,
        state TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        staging_name TEXT,
        committed_vault_id TEXT,
        error_code TEXT,
        needs_delete_confirm INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        payload_enc TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_jobs_order ON import_jobs (enqueue_order ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_jobs_batch ON import_jobs (batch_id)',
    );
  }

  ImportJournalException _classifyDbError(DatabaseException e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('not a database') ||
        msg.contains('corrupt') ||
        msg.contains('malformed')) {
      return const ImportJournalException(
        ImportJournalErrorKind.corrupt,
        'Import journal database is damaged',
      );
    }
    return const ImportJournalException(
      ImportJournalErrorKind.storageOrDbFailure,
      'Import journal database error',
    );
  }

  String _encryptPayload(ImportJobSensitivePayload payload) {
    if (!_crypto.isUnlocked) {
      throw const ImportJournalException(
        ImportJournalErrorKind.locked,
        'Vault is locked',
      );
    }
    return _crypto.encryptString(jsonEncode(payload.toJson()));
  }

  ImportJobSensitivePayload _decryptPayload(String payloadEnc) {
    if (!_crypto.isUnlocked) {
      throw const ImportJournalException(
        ImportJournalErrorKind.locked,
        'Vault is locked',
      );
    }
    try {
      final raw = _crypto.decryptString(payloadEnc);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ImportJobSensitivePayload.fromJson(map);
    } on Exception {
      throw const ImportJournalException(
        ImportJournalErrorKind.payloadAuthFailure,
        'Could not authenticate encrypted job payload',
      );
    }
  }

  Map<String, Object?> _toDbMap(DurableImportJob job) {
    return {
      'job_id': job.jobId,
      'batch_id': job.batchId,
      'dest_id': job.destId,
      'enqueue_order': job.enqueueOrder,
      'media_kind': job.mediaKind.name,
      'scope': job.scope.storageValue,
      'state': job.state.name,
      'attempt_count': job.attemptCount,
      'staging_name': job.stagingName,
      'committed_vault_id': job.committedVaultId,
      'error_code': job.errorCode,
      'needs_delete_confirm': job.needsDeleteConfirm ? 1 : 0,
      'created_at_ms': job.createdAtMs,
      'updated_at_ms': job.updatedAtMs,
      'payload_enc': _encryptPayload(job.payload),
    };
  }

  static ImportJobState _parseState(String raw) {
    for (final value in ImportJobState.values) {
      if (value.name == raw) return value;
    }
    return ImportJobState.failed;
  }

  static ImportMediaKind _parseKind(String raw) {
    return raw == ImportMediaKind.video.name
        ? ImportMediaKind.video
        : ImportMediaKind.photo;
  }

  OpaqueImportJobRow _fromDbRow(Map<String, Object?> row) {
    return OpaqueImportJobRow(
      jobId: row['job_id'] as String,
      batchId: row['batch_id'] as String,
      destId: row['dest_id'] as String,
      enqueueOrder: (row['enqueue_order'] as num).toInt(),
      mediaKind: _parseKind(row['media_kind'] as String),
      scope: VaultImportScope.fromStorageValue(row['scope'] as String),
      state: _parseState(row['state'] as String),
      attemptCount: (row['attempt_count'] as num).toInt(),
      stagingName: row['staging_name'] as String?,
      committedVaultId: row['committed_vault_id'] as String?,
      errorCode: row['error_code'] as String?,
      needsDeleteConfirm:
          ((row['needs_delete_confirm'] as num?)?.toInt() ?? 0) == 1,
      createdAtMs: (row['created_at_ms'] as num).toInt(),
      updatedAtMs: (row['updated_at_ms'] as num).toInt(),
      payloadEnc: row['payload_enc'] as String,
    );
  }

  Future<int> reserveEnqueueOrderBlock(int count) async {
    if (count <= 0) return _nextOrderFloor;
    final db = await _getDb();
    try {
      final rows = await db.rawQuery(
        'SELECT COALESCE(MAX(enqueue_order), 0) AS max_order FROM import_jobs',
      );
      final dbMax = (rows.first['max_order'] as num?)?.toInt() ?? 0;
      if (dbMax > _nextOrderFloor) {
        _nextOrderFloor = dbMax;
      }
      final start = _nextOrderFloor + 1;
      _nextOrderFloor += count;
      return start;
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  Future<int> allocateEnqueueOrderFloor() => reserveEnqueueOrderBlock(1);

  Future<void> upsertBatch(List<DurableImportJob> jobs) => insertBatch(jobs);

  Future<void> insertBatch(List<DurableImportJob> jobs) async {
    if (jobs.isEmpty) return;
    final db = await _getDb();
    try {
      final rows = jobs.map(_toDbMap).toList(growable: false);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final row in rows) {
          batch.insert(
            'import_jobs',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  Future<void> upsertJob(DurableImportJob job) async {
    final db = await _getDb();
    try {
      final map = _toDbMap(job);
      await db.insert(
        'import_jobs',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  /// Updates opaque scheduling fields while locked or transitioning on lock,
  /// without needing plaintext key re-encryption when payload didn't change.
  Future<void> updateOpaqueState({
    required String jobId,
    required ImportJobState state,
    int? attemptCount,
    String? stagingName,
    bool clearStagingName = false,
    String? committedVaultId,
    String? errorCode,
    bool clearErrorCode = false,
    bool? needsDeleteConfirm,
    required int updatedAtMs,
  }) async {
    final db = await _getDb();
    try {
      final updates = <String, Object?>{
        'state': state.name,
        'updated_at_ms': updatedAtMs,
      };
      if (attemptCount != null) updates['attempt_count'] = attemptCount;
      if (clearStagingName) {
        updates['staging_name'] = null;
      } else if (stagingName != null) {
        updates['staging_name'] = stagingName;
      }
      if (committedVaultId != null) {
        updates['committed_vault_id'] = committedVaultId;
      }
      if (clearErrorCode) {
        updates['error_code'] = null;
      } else if (errorCode != null) {
        updates['error_code'] = errorCode;
      }
      if (needsDeleteConfirm != null) {
        updates['needs_delete_confirm'] = needsDeleteConfirm ? 1 : 0;
      }
      await db.update(
        'import_jobs',
        updates,
        where: 'job_id = ?',
        whereArgs: [jobId],
      );
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  Future<bool> _existsOnDisk() async {
    if (_db != null && _db!.isOpen) return true;
    final path = await resolveDbPath();
    return File(path).exists();
  }

  /// Pauses all non-terminal queued/in-flight jobs in one transaction without
  /// requiring decryption keys if locking has already begun.
  Future<void> markActiveJobsPausedOnLock(int updatedAtMs) async {
    if (!await _existsOnDisk()) return;
    final db = await _getDb();
    try {
      await db.update(
        'import_jobs',
        {
          'state': ImportJobState.pausedLocked.name,
          'staging_name': null,
          'error_code': 'locked',
          'updated_at_ms': updatedAtMs,
        },
        where: 'state IN (?, ?, ?, ?)',
        whereArgs: [
          ImportJobState.queued.name,
          ImportJobState.preparing.name,
          ImportJobState.encrypting.name,
          ImportJobState.committing.name,
        ],
      );
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  Future<List<OpaqueImportJobRow>> readOpaqueRows() async {
    if (!await _existsOnDisk()) return const [];
    final db = await _getDb();
    try {
      final rows = await db.query('import_jobs', orderBy: 'enqueue_order ASC');
      return rows.map(_fromDbRow).toList(growable: false);
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  /// Loads and decrypts persisted jobs for the currently unlocked vault key.
  /// Any rows whose authenticated payload fails to decrypt under the current
  /// vault key are isolated cleanly and skipped rather than leaking across keys.
  Future<({List<DurableImportJob> jobs, int undecryptableCount})>
  loadDecryptedJobs() async {
    if (!_crypto.isUnlocked) {
      throw const ImportJournalException(
        ImportJournalErrorKind.locked,
        'Vault is locked',
      );
    }
    final opaque = await readOpaqueRows();
    final out = <DurableImportJob>[];
    int undecryptable = 0;
    for (final row in opaque) {
      try {
        final payload = _decryptPayload(row.payloadEnc);
        out.add(
          DurableImportJob(
            jobId: row.jobId,
            batchId: row.batchId,
            destId: row.destId,
            enqueueOrder: row.enqueueOrder,
            mediaKind: row.mediaKind,
            scope: row.scope,
            state: row.state,
            attemptCount: row.attemptCount,
            stagingName: row.stagingName,
            committedVaultId: row.committedVaultId,
            errorCode: row.errorCode,
            needsDeleteConfirm: row.needsDeleteConfirm,
            createdAtMs: row.createdAtMs,
            updatedAtMs: row.updatedAtMs,
            payload: payload,
          ),
        );
      } on ImportJournalException catch (e) {
        if (e.kind == ImportJournalErrorKind.payloadAuthFailure) {
          undecryptable += 1;
        } else {
          rethrow;
        }
      }
    }
    return (jobs: out, undecryptableCount: undecryptable);
  }

  Future<void> deleteJobs(List<String> jobIds) async {
    if (jobIds.isEmpty) return;
    final db = await _getDb();
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final id in jobIds) {
          batch.delete('import_jobs', where: 'job_id = ?', whereArgs: [id]);
        }
        await batch.commit(noResult: true);
      });
    } on DatabaseException catch (e) {
      throw _classifyDbError(e);
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// Permanently invalidates and removes all import journal data and SQLite files.
  Future<void> wipeAll() async {
    try {
      if (_db != null && _db!.isOpen) {
        await _db!.delete('import_jobs');
      }
    } catch (_) {}
    await close();
    _nextOrderFloor = 0;

    final path = await resolveDbPath();
    final factory = _databaseFactoryOverride ?? databaseFactory;
    try {
      await factory.deleteDatabase(path);
    } catch (_) {}
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      try {
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }
}
