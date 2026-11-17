import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/platform_service.dart';
import '../crypto/crypto_isolate.dart';
import '../crypto/vault_crypto.dart';
import '../crypto/vault_exceptions.dart';
import '../security/auto_lock.dart';
import '../security/vault_ui_access.dart';
import '../util/storage_space.dart';
import 'background_import_service.dart';
import 'file_vault_service.dart';
import 'import_journal_store.dart';
import 'import_progress.dart';
import 'media_import_policy.dart';
import 'media_picker_adapter.dart';
import 'vault_media_commit_helper.dart';
import 'video_vault_service.dart';

/// Optional deterministic barrier callbacks for testing specific execution
/// boundaries (resolve, hash, encrypt, verify, publish, metadata, delete).
class ImportCoordinatorStageHooks {
  final Future<void> Function(DurableImportJob job)? onBeforeResolve;
  final Future<void> Function(DurableImportJob job)? onBeforeHash;
  final Future<void> Function(DurableImportJob job)? onBeforeEncrypt;
  final Future<void> Function(DurableImportJob job)? onAfterEncryptBeforeVerify;
  final Future<void> Function(DurableImportJob job)? onBeforeCommitPublish;
  final Future<void> Function(DurableImportJob job)? onBeforeCommitMeta;
  final Future<void> Function(List<DurableImportJob> batchJobs)?
  onBeforeDeleteOriginals;

  const ImportCoordinatorStageHooks({
    this.onBeforeResolve,
    this.onBeforeHash,
    this.onBeforeEncrypt,
    this.onAfterEncryptBeforeVerify,
    this.onBeforeCommitPublish,
    this.onBeforeCommitMeta,
    this.onBeforeDeleteOriginals,
  });
}

typedef StorageSpaceProbe = Future<int?> Function();

Future<int?> defaultVaultStorageProbe(PlatformService platformService) async {
  if (kIsWeb) return null;
  try {
    final probe = await platformService.resolveVaultFile('__space_probe__');
    return await StorageSpace.availableBytes(probe.parent.path);
  } catch (_) {
    return null;
  }
}

final importJournalStoreProvider = Provider<ImportJournalStore>((ref) {
  return ImportJournalStore(ref.read(vaultCryptoProvider));
});

final importStorageSpaceProbeProvider = Provider<StorageSpaceProbe>((ref) {
  final platform = ref.read(platformServiceProvider);
  return () => defaultVaultStorageProbe(platform);
});

final importStageHooksProvider = Provider<ImportCoordinatorStageHooks?>((ref) {
  return null;
});

/// App-scoped, non-auto-disposed coordinator for encrypted photo/video gallery imports.
///
/// Owns serial execution, lock-epoch fencing, worker isolate cancellation,
/// encrypted journal recovery, atomic commit reconciliation, and deferred
/// conservative original-media deletion independently of individual UI screens.
class ImportCoordinator extends ChangeNotifier {
  final VaultCrypto _crypto;
  final PlatformService _platformService;
  final FileVaultService _fileVault;
  final VideoVaultService _videoVault;
  final MediaPickerAdapter _pickerAdapter;
  final ImportJournalStore _journal;
  final StorageSpaceProbe _storageProbe;
  final ImportCoordinatorStageHooks? _stageHooks;
  final BackgroundImportBridge _backgroundBridge;
  final VaultUiAccessController? _uiAccess;
  final Uuid _uuid;

  /// Projection synced from [_jobs] for existing [ImportActivityButton],
  /// [ImportStatusCard], and [showImportDetailsSheet] widgets.
  final ImportSession uiSession = ImportSession();

  final List<DurableImportJob> _jobs = [];
  final Set<Object> _foregroundTokens = <Object>{};
  final Set<String> _explicitCancelledJobIds = <String>{};
  final Map<String, ({double? fraction, String? detail})> _activeJobProgress =
      <String, ({double? fraction, String? detail})>{};
  final Map<String, double> _lastUiProgressFraction = <String, double>{};
  final Map<String, int> _lastUiProgressAtMs = <String, int>{};
  int? _lastNotifiedPercent;
  int _lastNotifiedUpdateAtMs = 0;

  bool _disposed = false;
  bool _isWorkerRunning = false;
  bool _lockFreezeRequested = false;
  bool _cancelAllRequested = false;
  bool _deletingOriginals = false;
  int _activeSessionEpoch = -1;
  int _lastSyncedUnlockEpoch = -1;
  int _workerGeneration = 0;
  int _syncingDepth = 0;
  int _libraryRevision = 0;
  int _rejectedStaleCompletionCount = 0;
  int _lastNotifiedCompleted = -1;
  int _lastNotifiedTotal = -1;
  ImportMediaKind? _lastCommittedKind;
  ImportPauseReason _pauseReason = ImportPauseReason.none;
  String? _pauseMessage;
  String? _backgroundServiceWarning;
  BackgroundServiceStartResult? _lastServiceStartResult;

  CryptoIsolateCancelHandle? _activeCancelHandle;
  ImportAuthorizationLease? _activeImportLease;
  Future<void> _opQueue = Future<void>.value();

  late final VoidCallback _removeCryptoListener;
  late final void Function() _removeBeforeLockListener;
  late final void Function() _removeAutoLockListener;
  late final void Function() _removeWipeListener;
  VoidCallback? _removeUiAccessListener;

  ImportCoordinator({
    required VaultCrypto crypto,
    required PlatformService platformService,
    required FileVaultService fileVault,
    required VideoVaultService videoVault,
    required MediaPickerAdapter pickerAdapter,
    required ImportJournalStore journal,
    StorageSpaceProbe? storageProbe,
    ImportCoordinatorStageHooks? stageHooks,
    BackgroundImportBridge? backgroundBridge,
    VaultUiAccessController? uiAccess,
    Uuid? uuid,
  }) : _crypto = crypto,
       _platformService = platformService,
       _fileVault = fileVault,
       _videoVault = videoVault,
       _pickerAdapter = pickerAdapter,
       _journal = journal,
       _storageProbe =
           storageProbe ?? (() => defaultVaultStorageProbe(platformService)),
       _stageHooks = stageHooks,
       _backgroundBridge = backgroundBridge ?? NoopBackgroundImportBridge(),
       _uiAccess = uiAccess,
       _uuid = uuid ?? const Uuid() {
    uiSession.onRequestCancelCallback = () {
      cancelActive().ignore();
    };
    uiSession.onRetryAll = () {
      retryEligible().ignore();
    };
    uiSession.onClearFinished = () {
      clearFinished().ignore();
    };
    uiSession.onConfirmPendingDeletes = () async {
      await confirmPendingDeleteBatches();
    };
    uiSession.onRetryItem = (index) {
      if (index >= 0 && index < _jobs.length) {
        retryJob(_jobs[index].jobId).ignore();
      }
    };
    uiSession.onCancelItem = (index) {
      if (index >= 0 && index < _jobs.length) {
        cancelJob(_jobs[index].jobId).ignore();
      }
    };

    _backgroundBridge.setCommandHandler(_handleBackgroundBridgeCommand);

    _removeBeforeLockListener = _crypto.addBeforeLockListener(
      _handleBeforeLock,
    );
    _removeAutoLockListener = AutoLock().registerOnLock(() {
      _handleBeforeLock(_crypto.lockEpoch);
    });
    _removeWipeListener = ImportJournalWipeRegistry.register(
      handleSecurityWipe,
    );
    _crypto.addListener(_onCryptoChanged);
    _removeCryptoListener = () => _crypto.removeListener(_onCryptoChanged);

    if (_uiAccess != null) {
      void onUiAccessChanged() {
        if (_disposed) return;
        if (hasForegroundUi && _crypto.isUnlocked) {
          triggerPendingDeleteConfirmationsIfForeground().ignore();
        }
      }

      _uiAccess.addListener(onUiAccessChanged);
      _removeUiAccessListener = () =>
          _uiAccess.removeListener(onUiAccessChanged);
    }

    if (_crypto.isUnlocked) {
      _activeSessionEpoch = _crypto.lockEpoch;
      _syncAfterUnlock(_crypto.lockEpoch).ignore();
    }
  }

  List<DurableImportJob> get jobs =>
      _crypto.isUnlocked ? List.unmodifiable(_jobs) : const [];

  List<DurableImportJob> jobsForScope(VaultImportScope scope) {
    if (!_crypto.isUnlocked) return const [];
    return List.unmodifiable(_jobs.where((j) => j.scope == scope));
  }

  bool get isWorking =>
      _crypto.isUnlocked &&
      !_lockFreezeRequested &&
      (_isWorkerRunning ||
          _syncingDepth > 0 ||
          (_pauseReason == ImportPauseReason.none &&
              _jobs.any(
                (j) =>
                    j.state == ImportJobState.queued ||
                    j.state == ImportJobState.preparing ||
                    j.state == ImportJobState.encrypting ||
                    j.state == ImportJobState.committing,
              )));

  bool get isPaused =>
      _crypto.isUnlocked &&
      !isWorking &&
      (_pauseReason != ImportPauseReason.none ||
          _jobs.any((j) => j.state == ImportJobState.pausedLocked));

  ImportPauseReason get pauseReason => _pauseReason;
  String? get pauseMessage => _pauseMessage;
  String? get backgroundServiceWarning => _backgroundServiceWarning;
  BackgroundServiceStartResult? get lastServiceStartResult =>
      _lastServiceStartResult;
  int get libraryRevision => _libraryRevision;
  ImportMediaKind? get lastCommittedKind => _lastCommittedKind;
  bool get hasForegroundUi =>
      _foregroundTokens.isNotEmpty &&
      (_uiAccess?.isUiAuthorized ?? true) &&
      !(_uiAccess?.isBackgroundConcealed ?? false);

  @visibleForTesting
  int get rejectedStaleCompletionCount => _rejectedStaleCompletionCount;

  @visibleForTesting
  bool get isWorkerRunningForTest => _isWorkerRunning;

  @visibleForTesting
  bool get hasActiveImportLeaseForTest =>
      _activeImportLease != null && _activeImportLease!.isActive;

  /// Registers a mounted unlocked foreground UI token (no BuildContext or callback retained).
  Object acquireForegroundUi() {
    final token = Object();
    _foregroundTokens.add(token);
    if (hasForegroundUi && _crypto.isUnlocked) {
      triggerPendingDeleteConfirmationsIfForeground().ignore();
    }
    return token;
  }

  void releaseForegroundUi(Object token) {
    _foregroundTokens.remove(token);
  }

  Future<T> _serializeOp<T>(Future<T> Function() action) {
    final next = _opQueue.then((_) => action());
    _opQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  void _onCryptoChanged() {
    if (_disposed) return;
    if (_crypto.isUnlocked) {
      final epoch = _crypto.lockEpoch;
      if (_lastSyncedUnlockEpoch != epoch) {
        _lockFreezeRequested = false;
        _activeSessionEpoch = epoch;
        _syncAfterUnlock(epoch).ignore();
      }
    } else {
      _handleBeforeLock(_crypto.lockEpoch);
    }
  }

  /// Synchronous lock freeze: immediately halts dispatch, invalidates running
  /// generation, aborts worker isolates, releases lease, and switches UI projection.
  void _handleBeforeLock(int newEpoch) {
    if (_disposed) return;
    _lockFreezeRequested = true;
    _activeSessionEpoch = -1;
    _workerGeneration++;
    _isWorkerRunning = false;
    _clearActiveProgress();
    final lease = _activeImportLease;
    _activeImportLease = null;
    if (lease != null && !lease.isReleased) {
      lease.release();
    }
    _backgroundBridge.stopImportService().ignore();

    final cancelHandle = _activeCancelHandle;
    _activeCancelHandle = null;
    if (cancelHandle != null) {
      cancelHandle.abort().ignore();
    }

    bool changed = false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (job.isRunnableOnResume &&
          !_explicitCancelledJobIds.contains(job.jobId)) {
        _jobs[i] = job.copyWith(
          state: ImportJobState.pausedLocked,
          clearStagingName: true,
          errorCode: 'locked',
          updatedAtMs: nowMs,
        );
        changed = true;
      }
    }
    if (changed || _jobs.isNotEmpty) {
      _pauseReason = ImportPauseReason.locked;
      _pauseMessage = 'Paused when vault locked.';
    }
    _projectSession();
    _safeNotify();

    unawaited(_persistPauseAndCleanupOnLock(nowMs));
  }

  void _handleAuthorizationRevoked(String reason) {
    if (_disposed) return;
    _pauseActiveWork(
      reason: ImportPauseReason.locked,
      message: reason == 'import_stall_timeout'
          ? 'Paused — background import stalled.'
          : reason == 'import_ceiling_exceeded'
          ? 'Paused — background time limit reached. Unlock to resume.'
          : 'Paused when authorization ended.',
      releaseLease: false,
    ).ignore();
  }

  void _handleBackgroundBridgeCommand(BackgroundImportCommand command) {
    if (_disposed ||
        !_crypto.isUnlocked ||
        _lockFreezeRequested ||
        _activeSessionEpoch != _crypto.lockEpoch) {
      return;
    }
    if ((command == BackgroundImportCommand.pauseRequested ||
            command == BackgroundImportCommand.serviceTimedOut ||
            command == BackgroundImportCommand.serviceStoppedByOs) &&
        !_isWorkerRunning) {
      return;
    }
    switch (command) {
      case BackgroundImportCommand.pauseRequested:
        _pauseActiveWork(
          reason: ImportPauseReason.userPaused,
          message: 'Paused from notification. Tap Retry to continue.',
          releaseLease: true,
        ).ignore();
        break;
      case BackgroundImportCommand.cancelRequested:
        cancelActive().ignore();
        break;
      case BackgroundImportCommand.serviceTimedOut:
        _pauseActiveWork(
          reason: ImportPauseReason.serviceTimedOut,
          message: 'Background processing limit reached. Tap Retry to resume.',
          releaseLease: true,
        ).ignore();
        break;
      case BackgroundImportCommand.serviceStoppedByOs:
        _pauseActiveWork(
          reason: ImportPauseReason.serviceStopped,
          message: 'Background service stopped. Tap Retry to resume.',
          releaseLease: true,
        ).ignore();
        break;
    }
  }

  Future<void> pauseFromUser() => _pauseActiveWork(
    reason: ImportPauseReason.userPaused,
    message: 'Import paused. Tap Retry to resume.',
    releaseLease: true,
  );

  Future<void> _pauseActiveWork({
    required ImportPauseReason reason,
    required String message,
    required bool releaseLease,
  }) async {
    if (_disposed) return;
    _lockFreezeRequested = true;
    _workerGeneration++;
    _isWorkerRunning = false;
    _clearActiveProgress();
    _pauseReason = reason;
    _pauseMessage = message;
    final cancelHandle = _activeCancelHandle;
    _activeCancelHandle = null;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dirty = <DurableImportJob>[];
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (!job.isCommittedToVault &&
          (job.state == ImportJobState.preparing ||
              job.state == ImportJobState.encrypting ||
              job.state == ImportJobState.committing ||
              (reason == ImportPauseReason.locked &&
                  job.state == ImportJobState.queued))) {
        final nextState = reason == ImportPauseReason.locked
            ? ImportJobState.pausedLocked
            : ImportJobState.queued;
        final updated = job.copyWith(
          state: nextState,
          clearStagingName: true,
          errorCode: reason.name,
          updatedAtMs: nowMs,
        );
        _jobs[i] = updated;
        dirty.add(updated);
      }
    }
    _projectSession();
    _safeNotify();

    if (cancelHandle != null) {
      await cancelHandle.abort();
    }
    await _backgroundBridge.stopImportService();

    if (dirty.isNotEmpty && _crypto.isUnlocked) {
      try {
        await _journal.upsertBatch(dirty);
      } catch (_) {}
    } else if (dirty.isNotEmpty) {
      try {
        await _journal.markActiveJobsPausedOnLock(nowMs);
      } catch (_) {}
    }
    await VaultMediaCommitHelper.cleanupStagingDirectory(_platformService);

    if (!_disposed) {
      _projectSession();
      _safeNotify();
    }

    if (releaseLease) {
      final lease = _activeImportLease;
      _activeImportLease = null;
      lease?.release();
    } else {
      _activeImportLease = null;
    }
  }

  Future<void> _persistPauseAndCleanupOnLock(int nowMs) async {
    try {
      await _journal.markActiveJobsPausedOnLock(nowMs);
    } catch (_) {}
    await VaultMediaCommitHelper.cleanupStagingDirectory(_platformService);
  }

  /// Permanently invalidates all pending and completed journal data and cleans
  /// staging during panic/duress/content wipe so nothing can resurrect.
  Future<void> handleSecurityWipe() async {
    _lockFreezeRequested = true;
    _activeSessionEpoch = -1;
    _workerGeneration++;
    _isWorkerRunning = false;
    _cancelAllRequested = false;
    _explicitCancelledJobIds.clear();
    _clearActiveProgress();
    _pauseReason = ImportPauseReason.none;
    _pauseMessage = null;
    _backgroundServiceWarning = null;
    AutoLock().revokeBackgroundImport(
      reason: 'security_wipe',
      lockVault: false,
    );
    final lease = _activeImportLease;
    _activeImportLease = null;
    lease?.release();
    await _backgroundBridge.stopImportService();
    final cancelHandle = _activeCancelHandle;
    _activeCancelHandle = null;
    if (cancelHandle != null) {
      await cancelHandle.abort();
    }
    _jobs.clear();
    _projectSession();
    _safeNotify();
    await VaultMediaCommitHelper.cleanupStagingDirectory(_platformService);
    await _journal.wipeAll();
  }

  /// Triggered automatically when [VaultCrypto] unlocks, and callable explicitly
  /// in deterministic startup/restart tests.
  Future<void> syncAfterUnlock() => _syncAfterUnlock(_crypto.lockEpoch);

  Future<void> _syncAfterUnlock(int unlockEpoch) {
    _syncingDepth++;
    return _serializeOp(() async {
      try {
        if (_disposed ||
            !_crypto.isUnlocked ||
            _crypto.lockEpoch != unlockEpoch) {
          return;
        }
        _lastSyncedUnlockEpoch = unlockEpoch;
        _lockFreezeRequested = false;
        _activeSessionEpoch = unlockEpoch;

        final ({List<DurableImportJob> jobs, int undecryptableCount}) loaded;
        try {
          loaded = await _journal.loadDecryptedJobs();
        } on ImportJournalException catch (e) {
          _pauseReason = ImportPauseReason.databaseFailure;
          _pauseMessage = e.safeMessage;
          _projectSession();
          _safeNotify();
          return;
        }

        if (_disposed ||
            !_crypto.isUnlocked ||
            _crypto.lockEpoch != unlockEpoch) {
          return;
        }

        await VaultMediaCommitHelper.cleanupStagingDirectory(_platformService);

        final reconciled = <DurableImportJob>[];
        final dirty = <DurableImportJob>[];
        bool anyLibraryCommitted = false;
        ImportMediaKind? latestKind;
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        for (final job in loaded.jobs) {
          if (_disposed ||
              !_crypto.isUnlocked ||
              _crypto.lockEpoch != unlockEpoch) {
            return;
          }
          var current = job;
          final isExplicitlyCancelled =
              current.state == ImportJobState.cancelled ||
              _explicitCancelledJobIds.contains(current.jobId);

          if (current.state == ImportJobState.saved || isExplicitlyCancelled) {
            reconciled.add(current);
            continue;
          }

          // Crash-window reconciliation against actual vault DB + authenticated blob:
          final hasMeta = await _hasVaultRecord(
            current.mediaKind,
            current.destId,
          );
          final blobStatus = await _verifyVaultBlob(
            current.mediaKind,
            current.destId,
          );

          if (hasMeta && blobStatus == BlobIntegrityStatus.healthy) {
            // Blob & DB row already committed before crash/lock -> NEVER re-import.
            final targetState = current.payload.originalDeletedConfirmed
                ? ImportJobState.saved
                : (current.state == ImportJobState.awaitingDeleteConfirmation
                      ? ImportJobState.awaitingDeleteConfirmation
                      : ImportJobState.savedOriginalKept);
            current = current.copyWith(
              state: targetState,
              committedVaultId: current.destId,
              clearStagingName: true,
              clearErrorCode: true,
              updatedAtMs: nowMs,
              payload: current.payload.copyWith(clearErrorDetail: true),
            );
            dirty.add(current);
            anyLibraryCommitted = true;
            latestKind = current.mediaKind;
            reconciled.add(current);
            continue;
          }

          if (!hasMeta && blobStatus == BlobIntegrityStatus.healthy) {
            if (current.state == ImportJobState.committing) {
              // Crashed after atomic rename and before metadata row insert:
              await _recoverMetadataOnly(current);
              current = current.copyWith(
                state: ImportJobState.savedOriginalKept,
                committedVaultId: current.destId,
                clearStagingName: true,
                clearErrorCode: true,
                updatedAtMs: nowMs,
                payload: current.payload.copyWith(clearErrorDetail: true),
              );
              dirty.add(current);
              anyLibraryCommitted = true;
              latestKind = current.mediaKind;
              reconciled.add(current);
              continue;
            } else {
              // Orphaned/ambiguous unreferenced blob from pre-commit phase -> clean.
              await _removeVaultBlob(current.mediaKind, current.destId);
            }
          } else if (blobStatus != BlobIntegrityStatus.fileNotFound &&
              blobStatus != BlobIntegrityStatus.vaultLocked) {
            // Damaged/partial blob at dest -> delete so no orphan remains.
            await _removeVaultBlob(current.mediaKind, current.destId);
          }

          if (current.isRunnableOnResume) {
            current = current.copyWith(
              state: ImportJobState.queued,
              clearStagingName: true,
              clearErrorCode: true,
              updatedAtMs: nowMs,
              payload: current.payload.copyWith(clearErrorDetail: true),
            );
            dirty.add(current);
          }
          reconciled.add(current);
        }

        if (_disposed ||
            !_crypto.isUnlocked ||
            _crypto.lockEpoch != unlockEpoch) {
          return;
        }

        if (dirty.isNotEmpty) {
          await _journal.upsertBatch(dirty);
        }

        _jobs
          ..clear()
          ..addAll(reconciled);

        // Re-evaluate batch completion/delete states cleanly across recovered batches.
        final batchIds = _jobs.map((j) => j.batchId).toSet();
        for (final batchId in batchIds) {
          await _evaluateBatchDeleteReadiness(batchId);
        }

        if (anyLibraryCommitted) {
          _libraryRevision++;
          _lastCommittedKind = latestKind;
        }
        _pauseReason = ImportPauseReason.none;
        _pauseMessage = null;
        _cancelAllRequested = false;

        if (_jobs.any((j) => j.state == ImportJobState.queued)) {
          _startWorkerIfNeeded(unlockEpoch);
        } else {
          await triggerPendingDeleteConfirmationsIfForeground();
        }
      } finally {
        _syncingDepth--;
        if (!_disposed) {
          _projectSession();
          _safeNotify();
        }
      }
    });
  }

  /// Appends a newly selected batch of media source references without clearing
  /// or overwriting active/queued/previous work.
  Future<String?> enqueueBatch({
    required List<MediaSourceRef> sources,
    required VaultImportScope scope,
  }) async {
    if (sources.isEmpty) return null;
    if (!_crypto.isUnlocked) {
      throw const ImportJournalException(
        ImportJournalErrorKind.locked,
        'Vault must be unlocked before importing',
      );
    }

    return _serializeOp(() async {
      if (_disposed || !_crypto.isUnlocked) return null;
      final epoch = _crypto.lockEpoch;
      final batchId = _uuid.v4();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final newJobs = <DurableImportJob>[];

      try {
        var nextOrder = await _journal.reserveEnqueueOrderBlock(sources.length);
        for (final src in sources) {
          final order = nextOrder++;
          final destId = _uuid.v4();
          newJobs.add(
            DurableImportJob(
              jobId: _uuid.v4(),
              batchId: batchId,
              destId: destId,
              enqueueOrder: order,
              mediaKind: src.kind,
              scope: scope,
              state: ImportJobState.queued,
              attemptCount: 0,
              createdAtMs: nowMs,
              updatedAtMs: nowMs,
              payload: ImportJobSensitivePayload(
                sourceAssetId: src.sourceAssetId,
                displayName: src.displayName,
                mimeType: src.mimeType,
                durationSeconds: src.durationSeconds,
                expectedSizeBytes: src.expectedSizeBytes,
              ),
            ),
          );
        }
        await _journal.insertBatch(newJobs);
      } on ImportJournalException catch (e) {
        _pauseReason = ImportPauseReason.databaseFailure;
        _pauseMessage = e.safeMessage;
        _projectSession();
        _safeNotify();
        rethrow;
      }

      _jobs.addAll(newJobs);
      _cancelAllRequested = false;
      _pauseReason = ImportPauseReason.none;
      _pauseMessage = null;
      _lockFreezeRequested = false;
      _activeSessionEpoch = epoch;
      _lastSyncedUnlockEpoch = epoch;
      _projectSession();
      _safeNotify();

      _startWorkerIfNeeded(epoch);
      return batchId;
    });
  }

  void _startWorkerIfNeeded(int epoch) {
    if (_disposed ||
        _isWorkerRunning ||
        _lockFreezeRequested ||
        !_crypto.isUnlocked ||
        _crypto.lockEpoch != epoch ||
        _pauseReason != ImportPauseReason.none) {
      return;
    }
    if (!_jobs.any((j) => j.state == ImportJobState.queued)) {
      return;
    }
    _workerGeneration++;
    final gen = _workerGeneration;
    _isWorkerRunning = true;
    unawaited(_workerLoop(epoch, gen));
  }

  bool _isRunValid(int expectedEpoch, int expectedGen, String jobId) {
    return !_disposed &&
        !_lockFreezeRequested &&
        _crypto.isUnlocked &&
        _crypto.lockEpoch == expectedEpoch &&
        _activeSessionEpoch == expectedEpoch &&
        _workerGeneration == expectedGen &&
        !_cancelAllRequested &&
        !_explicitCancelledJobIds.contains(jobId);
  }

  ({int completed, int total}) _progressCounts() {
    final total = _jobs.length;
    var completed = 0;
    for (final j in _jobs) {
      if (j.isCommittedToVault ||
          j.state == ImportJobState.failed ||
          j.state == ImportJobState.needsSource ||
          j.state == ImportJobState.cancelled) {
        completed++;
      }
    }
    return (completed: completed, total: total);
  }

  void _clearActiveProgress([String? jobId]) {
    if (jobId == null) {
      _activeJobProgress.clear();
      _lastUiProgressFraction.clear();
      _lastUiProgressAtMs.clear();
      _lastNotifiedPercent = null;
      _lastNotifiedUpdateAtMs = 0;
      return;
    }
    _activeJobProgress.remove(jobId);
    _lastUiProgressFraction.remove(jobId);
    _lastUiProgressAtMs.remove(jobId);
  }

  int? _currentActivePercent() {
    for (final j in _jobs) {
      if (j.state == ImportJobState.encrypting ||
          j.state == ImportJobState.preparing) {
        final fraction = _activeJobProgress[j.jobId]?.fraction;
        if (fraction != null) {
          return (fraction * 100).round().clamp(0, 99);
        }
        return null;
      }
    }
    return null;
  }

  static String _formatBytesCompact(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatByteProgressDetail({
    required int bytesProcessed,
    required int totalBytes,
    required ImportJobState phase,
    required int attempt,
  }) {
    final phaseWord = phase == ImportJobState.preparing
        ? 'Checking'
        : 'Encrypting';
    final prefix = attempt > 1 ? 'Restarted #$attempt · $phaseWord' : phaseWord;
    if (totalBytes <= 0) return prefix;
    return '$prefix · ${_formatBytesCompact(bytesProcessed)} / ${_formatBytesCompact(totalBytes)}';
  }

  void _onJobBytesProgress({
    required String jobId,
    required int epoch,
    required int gen,
    required int bytesProcessed,
    required int totalBytes,
    required ImportJobState phase,
    required int attempt,
  }) {
    if (!_isRunValid(epoch, gen, jobId)) return;
    final double? fraction = totalBytes > 0
        ? (bytesProcessed / totalBytes).clamp(0.0, 0.99).toDouble()
        : null;
    final detail = _formatByteProgressDetail(
      bytesProcessed: bytesProcessed,
      totalBytes: totalBytes,
      phase: phase,
      attempt: attempt,
    );
    _activeJobProgress[jobId] = (fraction: fraction, detail: detail);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastFraction = _lastUiProgressFraction[jobId];
    final lastAtMs = _lastUiProgressAtMs[jobId] ?? 0;
    final significantFractionDelta = fraction == null
        ? lastFraction == null
        : (lastFraction == null || (fraction - lastFraction).abs() >= 0.01);
    final elapsedEnough = nowMs - lastAtMs >= 250;
    if (lastFraction == null || significantFractionDelta || elapsedEnough) {
      if (fraction != null) {
        _lastUiProgressFraction[jobId] = fraction;
      }
      _lastUiProgressAtMs[jobId] = nowMs;
      _projectSession();
      _safeNotify();
    }
    _maybeUpdateBackgroundProgress();
  }

  void _maybeUpdateBackgroundProgress() {
    if (_disposed || !_isWorkerRunning) return;
    final counts = _progressCounts();
    final activePercent = _currentActivePercent();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final countsChanged =
        counts.completed != _lastNotifiedCompleted ||
        counts.total != _lastNotifiedTotal;
    final percentChangedSignificantly =
        activePercent != _lastNotifiedPercent &&
        (countsChanged ||
            activePercent == null ||
            _lastNotifiedPercent == null ||
            ((activePercent - _lastNotifiedPercent!).abs() >= 2 &&
                nowMs - _lastNotifiedUpdateAtMs >= 750));
    if (!countsChanged && !percentChangedSignificantly) {
      return;
    }
    _lastNotifiedCompleted = counts.completed;
    _lastNotifiedTotal = counts.total;
    _lastNotifiedPercent = activePercent;
    _lastNotifiedUpdateAtMs = nowMs;
    _backgroundBridge
        .updateImportService(
          completed: counts.completed,
          total: counts.total,
          activePercent: activePercent,
        )
        .ignore();
  }

  Future<void> _workerLoop(int epoch, int gen) async {
    final lease = AutoLock().acquireImportAuthorization(
      cryptoEpoch: epoch,
      onRevoke: _handleAuthorizationRevoked,
    );
    _activeImportLease = lease;
    _lastNotifiedCompleted = -1;
    _lastNotifiedTotal = -1;

    final startCounts = _progressCounts();
    try {
      final startRes = await _backgroundBridge.startImportService(
        completed: startCounts.completed,
        total: startCounts.total,
      );
      if (_disposed ||
          _lockFreezeRequested ||
          !_crypto.isUnlocked ||
          _crypto.lockEpoch != epoch ||
          _workerGeneration != gen) {
        return;
      }
      _lastServiceStartResult = startRes;
      if (!startRes.started) {
        _backgroundServiceWarning =
            startRes.safeMessage ??
            'Background service could not start — keep the app open until imports finish.';
      } else if (!startRes.notificationsGranted) {
        _backgroundServiceWarning =
            'Notifications are disabled — import status will not appear in the notification bar.';
      } else {
        _backgroundServiceWarning = null;
      }
      _lastNotifiedCompleted = startCounts.completed;
      _lastNotifiedTotal = startCounts.total;
      _projectSession();
      _safeNotify();
    } catch (_) {
      if (!_disposed) {
        _backgroundServiceWarning =
            'Background service unavailable — keep the app open until imports finish.';
      }
    }

    try {
      while (!_disposed &&
          !_lockFreezeRequested &&
          _crypto.isUnlocked &&
          _crypto.lockEpoch == epoch &&
          _workerGeneration == gen &&
          _pauseReason == ImportPauseReason.none) {
        final nextIndex = _jobs.indexWhere(
          (j) => j.state == ImportJobState.queued,
        );
        if (nextIndex < 0) break;

        final job = _jobs[nextIndex];
        if (_cancelAllRequested ||
            _explicitCancelledJobIds.contains(job.jobId)) {
          await _markExplicitCancelled(job);
          continue;
        }

        lease.recordProgress();
        _maybeUpdateBackgroundProgress();
        await _processSingleJob(job, epoch, gen, lease);
      }
    } finally {
      if (_workerGeneration == gen) {
        _isWorkerRunning = false;
        _clearActiveProgress();
      }
      try {
        await _backgroundBridge.stopImportService();
      } catch (_) {}
      if (identical(_activeImportLease, lease)) {
        _activeImportLease = null;
      }
      if (!_disposed) {
        _projectSession();
        _safeNotify();
      }
      lease.release();
    }
  }

  Future<void> _processSingleJob(
    DurableImportJob initialJob,
    int epoch,
    int gen,
    ImportAuthorizationLease? lease,
  ) async {
    var job = initialJob;
    final attempt = job.attemptCount + 1;
    final stagingName = '${job.destId}_a$attempt.part';
    File? stagingFile;

    Future<bool> commitInMemoryAndJournal(DurableImportJob updated) async {
      if (_disposed ||
          _lockFreezeRequested ||
          !_crypto.isUnlocked ||
          _crypto.lockEpoch != epoch ||
          _workerGeneration != gen) {
        _rejectedStaleCompletionCount++;
        return false;
      }
      final idx = _jobs.indexWhere((j) => j.jobId == updated.jobId);
      if (idx >= 0) {
        _jobs[idx] = updated;
      }
      await _journal.upsertJob(updated);
      _projectSession();
      _safeNotify();
      return true;
    }

    try {
      // Check idempotent pre-commit safety: never duplicate an already-saved item.
      final alreadyHasMeta = await _hasVaultRecord(job.mediaKind, job.destId);
      final existingBlobStatus = await _verifyVaultBlob(
        job.mediaKind,
        job.destId,
      );
      if (alreadyHasMeta && existingBlobStatus == BlobIntegrityStatus.healthy) {
        final done = job.copyWith(
          state: job.payload.originalDeletedConfirmed
              ? ImportJobState.saved
              : ImportJobState.savedOriginalKept,
          committedVaultId: job.destId,
          clearStagingName: true,
          clearErrorCode: true,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (await commitInMemoryAndJournal(done)) {
          await _evaluateBatchDeleteReadiness(done.batchId);
        }
        return;
      }

      // 1. Preparing
      _clearActiveProgress(job.jobId);
      if (attempt > 1) {
        _activeJobProgress[job.jobId] = (
          fraction: null,
          detail: 'Restarted after pause (attempt #$attempt)',
        );
      }
      job = job.copyWith(
        state: ImportJobState.preparing,
        attemptCount: attempt,
        clearErrorCode: true,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(clearErrorDetail: true),
      );
      if (!await commitInMemoryAndJournal(job)) return;

      await _stageHooks?.onBeforeResolve?.call(job);
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      final ref = MediaSourceRef(
        sourceAssetId: job.payload.sourceAssetId,
        kind: job.mediaKind,
        displayName: job.payload.displayName,
        mimeType: job.payload.mimeType,
        durationSeconds: job.payload.durationSeconds,
        expectedSizeBytes: job.payload.expectedSizeBytes,
      );
      final resolved = await _pickerAdapter.resolveSource(ref);
      lease?.recordProgress();

      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      if (!resolved.isReady) {
        if (resolved.status == MediaSourceResolutionStatus.permissionDenied) {
          final needsPermJob = job.copyWith(
            state: ImportJobState.needsSource,
            errorCode: 'permission_denied',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            payload: job.payload.copyWith(
              errorDetail: resolved.safeReason ?? 'Gallery permission denied',
            ),
          );
          await commitInMemoryAndJournal(needsPermJob);
          _pauseReason = ImportPauseReason.permissionDenied;
          _pauseMessage =
              'Gallery permission needed. Grant access and tap Retry.';
          return;
        }
        final stateForOutcome =
            (resolved.status == MediaSourceResolutionStatus.missing ||
                resolved.status == MediaSourceResolutionStatus.cloudUnavailable)
            ? ImportJobState.needsSource
            : ImportJobState.failed;
        final failedJob = job.copyWith(
          state: stateForOutcome,
          errorCode: resolved.errorCode ?? 'source_unreadable',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          payload: job.payload.copyWith(
            errorDetail: resolved.safeReason ?? 'Source file unavailable',
          ),
        );
        await commitInMemoryAndJournal(failedJob);
        return;
      }

      final srcFile = File(resolved.localFilePath!);
      final sourceSize = resolved.sizeBytes ?? await srcFile.length();
      final availableBytes = await _storageProbe();
      if (availableBytes != null &&
          availableBytes < sourceSize + kImportStorageReserveBytes) {
        final reverted = job.copyWith(
          state: ImportJobState.queued,
          attemptCount: job.attemptCount - 1,
          errorCode: 'low_storage',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          payload: job.payload.copyWith(
            errorDetail: 'Paused — insufficient free storage',
          ),
        );
        await commitInMemoryAndJournal(reverted);
        _pauseReason = ImportPauseReason.lowStorage;
        _pauseMessage =
            'Storage is full. Free up device space and tap Retry to resume.';
        return;
      }

      // 2. Hashing
      await _stageHooks?.onBeforeHash?.call(job);
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      final String contentHash;
      try {
        contentHash = job.mediaKind == ImportMediaKind.photo
            ? await _fileVault.computeFileSha256(
                srcFile,
                shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
                onBytesProgress: (bytesProcessed) {
                  lease?.recordProgress();
                  _onJobBytesProgress(
                    jobId: job.jobId,
                    epoch: epoch,
                    gen: gen,
                    bytesProcessed: bytesProcessed,
                    totalBytes: sourceSize,
                    phase: ImportJobState.preparing,
                    attempt: attempt,
                  );
                },
              )
            : await _videoVault.computeFileSha256(
                srcFile,
                shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
                onBytesProgress: (bytesProcessed) {
                  lease?.recordProgress();
                  _onJobBytesProgress(
                    jobId: job.jobId,
                    epoch: epoch,
                    gen: gen,
                    bytesProcessed: bytesProcessed,
                    totalBytes: sourceSize,
                    phase: ImportJobState.preparing,
                    attempt: attempt,
                  );
                },
              );
      } on FileSystemException {
        final failedJob = job.copyWith(
          state: ImportJobState.failed,
          errorCode: 'corrupt_source',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          payload: job.payload.copyWith(
            errorDetail: 'Could not read source media',
          ),
        );
        await commitInMemoryAndJournal(failedJob);
        return;
      }

      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      // 3. Encrypting into coordinator-owned staging file
      _clearActiveProgress(job.jobId);
      if (attempt > 1) {
        _activeJobProgress[job.jobId] = (
          fraction: null,
          detail: 'Restarted #$attempt · Encrypting',
        );
      }
      stagingFile = job.mediaKind == ImportMediaKind.photo
          ? await _fileVault.prepareImportStagingFile('${job.destId}_a$attempt')
          : await _videoVault.prepareImportStagingFile(
              '${job.destId}_a$attempt',
            );

      job = job.copyWith(
        state: ImportJobState.encrypting,
        stagingName: stagingName,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(
          displayName: resolved.displayName,
          mimeType: resolved.mimeType,
          durationSeconds: resolved.durationSeconds,
          expectedSizeBytes: sourceSize,
          contentHash: contentHash,
        ),
      );
      if (!await commitInMemoryAndJournal(job)) {
        _clearActiveProgress(job.jobId);
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
        return;
      }

      await _stageHooks?.onBeforeEncrypt?.call(job);
      if (!_isRunValid(epoch, gen, job.jobId)) {
        _clearActiveProgress(job.jobId);
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      final cancelHandle = CryptoIsolateCancelHandle();
      _activeCancelHandle = cancelHandle;
      try {
        if (job.mediaKind == ImportMediaKind.photo) {
          await _fileVault.encryptPhotoToStaging(
            sourceFile: srcFile,
            stagingFile: stagingFile,
            shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
            cancelHandle: cancelHandle,
            onBytesProgress: (bytesProcessed) {
              lease?.recordProgress();
              _onJobBytesProgress(
                jobId: job.jobId,
                epoch: epoch,
                gen: gen,
                bytesProcessed: bytesProcessed,
                totalBytes: sourceSize,
                phase: ImportJobState.encrypting,
                attempt: attempt,
              );
            },
          );
        } else {
          await _videoVault.encryptVideoToStaging(
            sourceFile: srcFile,
            stagingFile: stagingFile,
            shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
            cancelHandle: cancelHandle,
            onBytesProgress: (bytesProcessed) {
              lease?.recordProgress();
              _onJobBytesProgress(
                jobId: job.jobId,
                epoch: epoch,
                gen: gen,
                bytesProcessed: bytesProcessed,
                totalBytes: sourceSize,
                phase: ImportJobState.encrypting,
                attempt: attempt,
              );
            },
          );
        }
      } finally {
        if (identical(_activeCancelHandle, cancelHandle)) {
          _activeCancelHandle = null;
        }
      }

      lease?.recordProgress();
      await _stageHooks?.onAfterEncryptBeforeVerify?.call(job);
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      // 4. Committing (verify integrity -> atomic rename -> DB metadata -> journal saved)
      _clearActiveProgress(job.jobId);
      job = job.copyWith(
        state: ImportJobState.committing,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (!await commitInMemoryAndJournal(job)) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
        return;
      }

      await _stageHooks?.onBeforeCommitPublish?.call(job);
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }

      if (job.mediaKind == ImportMediaKind.photo) {
        await _fileVault.commitStagedPhoto(
          id: job.destId,
          stagingFile: stagingFile,
          mimeType: resolved.mimeType,
          plaintextSize: sourceSize,
          originalName: resolved.displayName,
          contentHash: contentHash,
          isEpochValid: () => _isRunValid(epoch, gen, job.jobId),
          shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
          onBeforeMetaCommit: _stageHooks?.onBeforeCommitMeta == null
              ? null
              : () => _stageHooks!.onBeforeCommitMeta!(job),
        );
      } else {
        await _videoVault.commitStagedVideo(
          id: job.destId,
          stagingFile: stagingFile,
          mimeType: resolved.mimeType,
          durationS: resolved.durationSeconds,
          plaintextSize: sourceSize,
          originalName: resolved.displayName,
          contentHash: contentHash,
          isEpochValid: () => _isRunValid(epoch, gen, job.jobId),
          shouldAbort: () => !_isRunValid(epoch, gen, job.jobId),
          onBeforeMetaCommit: _stageHooks?.onBeforeCommitMeta == null
              ? null
              : () => _stageHooks!.onBeforeCommitMeta!(job),
        );
      }

      if (!_isRunValid(epoch, gen, job.jobId)) {
        // Epoch changed AFTER commit or during commit -> record completion only if
        // already persisted in DB, otherwise mark rejected.
        _rejectedStaleCompletionCount++;
        return;
      }

      final committedJob = job.copyWith(
        state: ImportJobState.savedOriginalKept,
        committedVaultId: job.destId,
        clearStagingName: true,
        clearErrorCode: true,
        needsDeleteConfirm:
            resolved.localFilePath != null &&
            job.payload.sourceAssetId.isNotEmpty,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(clearErrorDetail: true),
      );
      if (!await commitInMemoryAndJournal(committedJob)) return;

      lease?.recordProgress();
      _maybeUpdateBackgroundProgress();
      _libraryRevision++;
      _lastCommittedKind = committedJob.mediaKind;
      _safeNotify();

      await _evaluateBatchDeleteReadiness(committedJob.batchId);
    } on OperationCancelledException {
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      await _handleInterruptedOutcome(job, epoch, gen);
    } on CorruptedMediaFileException {
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }
      final failedJob = job.copyWith(
        state: ImportJobState.failed,
        clearStagingName: true,
        errorCode: 'corrupt_source',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(
          errorDetail: 'Verification failed or source corrupt',
        ),
      );
      await commitInMemoryAndJournal(failedJob);
    } on ImportJournalException catch (e) {
      if (_workerGeneration == gen && _crypto.lockEpoch == epoch) {
        _clearActiveProgress(job.jobId);
      }
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      _pauseReason = ImportPauseReason.databaseFailure;
      _pauseMessage = e.safeMessage;
      _projectSession();
      _safeNotify();
    } on DatabaseException catch (e) {
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      final isFull = _isDiskFullError(e);
      final reverted = job.copyWith(
        state: ImportJobState.queued,
        clearStagingName: true,
        errorCode: isFull ? 'low_storage' : 'db_failure',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(
          errorDetail: isFull
              ? 'Paused — insufficient free storage'
              : 'Paused — database unavailable',
        ),
      );
      final idx = _jobs.indexWhere((j) => j.jobId == job.jobId);
      if (idx >= 0) _jobs[idx] = reverted;
      _pauseReason = isFull
          ? ImportPauseReason.lowStorage
          : ImportPauseReason.databaseFailure;
      _pauseMessage = isFull
          ? 'Storage is full. Free up device space and tap Retry to resume.'
          : 'Vault database error. Tap Retry to resume safely.';
      _projectSession();
      _safeNotify();
    } on FileSystemException catch (e) {
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }
      if (_isDiskFullError(e)) {
        final reverted = job.copyWith(
          state: ImportJobState.queued,
          attemptCount: job.attemptCount > 0 ? job.attemptCount - 1 : 0,
          clearStagingName: true,
          errorCode: 'low_storage',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          payload: job.payload.copyWith(
            errorDetail: 'Paused — insufficient free storage',
          ),
        );
        await commitInMemoryAndJournal(reverted);
        _pauseReason = ImportPauseReason.lowStorage;
        _pauseMessage =
            'Storage is full. Free up device space and tap Retry to resume.';
      } else {
        final failedJob = job.copyWith(
          state: ImportJobState.failed,
          clearStagingName: true,
          errorCode: 'source_unreadable',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          payload: job.payload.copyWith(errorDetail: 'File read/write failed'),
        );
        await commitInMemoryAndJournal(failedJob);
      }
    } catch (_) {
      if (stagingFile != null) {
        await VaultMediaCommitHelper.deleteIfExists(stagingFile);
      }
      if (!_isRunValid(epoch, gen, job.jobId)) {
        await _handleInterruptedOutcome(job, epoch, gen);
        return;
      }
      final failedJob = job.copyWith(
        state: ImportJobState.failed,
        clearStagingName: true,
        errorCode: 'unknown',
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        payload: job.payload.copyWith(errorDetail: 'Import error'),
      );
      await commitInMemoryAndJournal(failedJob);
    } finally {
      if (_workerGeneration == gen && _crypto.lockEpoch == epoch) {
        _clearActiveProgress(job.jobId);
      }
    }
  }

  Future<void> _handleInterruptedOutcome(
    DurableImportJob job,
    int epoch,
    int gen,
  ) async {
    final isExplicitCancel =
        _cancelAllRequested || _explicitCancelledJobIds.contains(job.jobId);
    if (isExplicitCancel) {
      await _markExplicitCancelled(job);
      return;
    }

    if (_crypto.lockEpoch != epoch ||
        !_crypto.isUnlocked ||
        _workerGeneration != gen) {
      // Stale worker unwinding after lock or re-unlock must NEVER clobber
      // jobs belonging to the newer session.
      _rejectedStaleCompletionCount++;
      _safeNotify();
      return;
    }

    _clearActiveProgress(job.jobId);
    final paused = job.copyWith(
      state: ImportJobState.pausedLocked,
      clearStagingName: true,
      errorCode: 'locked',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final idx = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (idx >= 0) _jobs[idx] = paused;
    try {
      await _journal.updateOpaqueState(
        jobId: job.jobId,
        state: ImportJobState.pausedLocked,
        clearStagingName: true,
        errorCode: 'locked',
        updatedAtMs: paused.updatedAtMs,
      );
    } catch (_) {}
    _projectSession();
    _safeNotify();
  }

  Future<void> _markExplicitCancelled(DurableImportJob job) async {
    if (job.isCommittedToVault) return;
    _clearActiveProgress(job.jobId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cancelled = job.copyWith(
      state: ImportJobState.cancelled,
      clearStagingName: true,
      errorCode: 'cancelled',
      updatedAtMs: nowMs,
      payload: job.payload.copyWith(errorDetail: 'Cancelled by user'),
    );
    final idx = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (idx >= 0) {
      _jobs[idx] = cancelled;
    }
    try {
      if (_crypto.isUnlocked) {
        await _journal.upsertJob(cancelled);
      } else {
        await _journal.updateOpaqueState(
          jobId: job.jobId,
          state: ImportJobState.cancelled,
          clearStagingName: true,
          errorCode: 'cancelled',
          updatedAtMs: nowMs,
        );
      }
    } catch (_) {}
    _projectSession();
    _safeNotify();
  }

  /// Conservative deletion readiness check:
  /// ONLY transitions a batch to [ImportJobState.awaitingDeleteConfirmation]
  /// if EVERY item in the batch is committed cleanly with zero failed,
  /// cancelled, needsSource, paused, or queued items remaining.
  Future<void> _evaluateBatchDeleteReadiness(String batchId) async {
    final batchJobs = _jobs.where((j) => j.batchId == batchId).toList();
    if (batchJobs.isEmpty) return;

    final allCommitted = batchJobs.every(
      (j) =>
          j.isCommittedToVault &&
          (j.state == ImportJobState.savedOriginalKept ||
              j.state == ImportJobState.awaitingDeleteConfirmation ||
              j.state == ImportJobState.saved),
    );
    if (!allCommitted) return;

    final candidates = batchJobs
        .where(
          (j) =>
              !j.payload.originalDeletedConfirmed &&
              j.payload.sourceAssetId.isNotEmpty &&
              j.needsDeleteConfirm,
        )
        .toList();
    if (candidates.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dirty = <DurableImportJob>[];
    for (final c in candidates) {
      final updated = c.copyWith(
        state: ImportJobState.awaitingDeleteConfirmation,
        updatedAtMs: nowMs,
      );
      final idx = _jobs.indexWhere((j) => j.jobId == c.jobId);
      if (idx >= 0) _jobs[idx] = updated;
      dirty.add(updated);
    }
    if (dirty.isNotEmpty && _crypto.isUnlocked) {
      try {
        await _journal.upsertBatch(dirty);
      } catch (_) {}
    }
    _projectSession();
    _safeNotify();

    await triggerPendingDeleteConfirmationsIfForeground();
  }

  Future<void> triggerPendingDeleteConfirmationsIfForeground() async {
    if (_disposed ||
        !_crypto.isUnlocked ||
        !hasForegroundUi ||
        _deletingOriginals) {
      return;
    }
    await confirmPendingDeleteBatches();
  }

  Future<void> confirmPendingDeleteBatches() async {
    if (_disposed ||
        !_crypto.isUnlocked ||
        !(_uiAccess?.isUiAuthorized ?? true) ||
        _deletingOriginals) {
      return;
    }
    final pendingBatchIds = _jobs
        .where((j) => j.state == ImportJobState.awaitingDeleteConfirmation)
        .map((j) => j.batchId)
        .toSet()
        .toList();
    for (final batchId in pendingBatchIds) {
      if (_disposed || !_crypto.isUnlocked) break;
      await confirmAndDeleteOriginalsForBatch(batchId);
    }
  }

  /// Requests OS deletion ONLY for verified committed items in [batchId],
  /// updates ONLY OS-confirmed deleted IDs to `saved`, and marks any
  /// denied/partial leftovers as `savedOriginalKept`.
  Future<void> confirmAndDeleteOriginalsForBatch(String batchId) async {
    if (_disposed ||
        !_crypto.isUnlocked ||
        !(_uiAccess?.isUiAuthorized ?? true) ||
        _deletingOriginals) {
      return;
    }
    final capturedEpoch = _crypto.lockEpoch;
    final batchJobs = _jobs
        .where(
          (j) =>
              j.batchId == batchId &&
              j.isCommittedToVault &&
              !j.payload.originalDeletedConfirmed &&
              j.payload.sourceAssetId.isNotEmpty,
        )
        .toList();
    if (batchJobs.isEmpty) return;

    final allCommitted = _jobs
        .where((j) => j.batchId == batchId)
        .every((j) => j.isCommittedToVault);
    if (!allCommitted) return;

    _deletingOriginals = true;
    final deleteLease = AutoLock().acquireProtectedOperation();
    try {
      await _stageHooks?.onBeforeDeleteOriginals?.call(batchJobs);
      if (!_crypto.isUnlocked || _crypto.lockEpoch != capturedEpoch) {
        _rejectedStaleCompletionCount++;
        return;
      }

      final assetIds = batchJobs
          .map((j) => j.payload.sourceAssetId)
          .toList(growable: false);
      final result = await _pickerAdapter.deleteOriginals(assetIds);

      if (!_crypto.isUnlocked || _crypto.lockEpoch != capturedEpoch) {
        _rejectedStaleCompletionCount++;
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dirty = <DurableImportJob>[];
      for (final j in batchJobs) {
        final deleted = result.deletedIds.contains(j.payload.sourceAssetId);
        final nextState = deleted
            ? ImportJobState.saved
            : ImportJobState.savedOriginalKept;
        final updated = j.copyWith(
          state: nextState,
          needsDeleteConfirm: false,
          errorCode: deleted ? null : result.errorCode,
          clearErrorCode: deleted || result.errorCode == null,
          updatedAtMs: nowMs,
          payload: j.payload.copyWith(
            originalDeletedConfirmed: deleted,
            errorDetail: deleted
                ? null
                : (result.permissionDenied
                      ? 'Original kept — permission denied'
                      : null),
            clearErrorDetail: deleted || !result.permissionDenied,
          ),
        );
        final idx = _jobs.indexWhere((x) => x.jobId == j.jobId);
        if (idx >= 0) _jobs[idx] = updated;
        dirty.add(updated);
      }
      if (dirty.isNotEmpty) {
        try {
          await _journal.upsertBatch(dirty);
        } catch (_) {}
      }
      _projectSession();
      _safeNotify();
    } finally {
      deleteLease.release();
      _deletingOriginals = false;
    }
  }

  /// Explicitly cancels active/queued jobs without disturbing already-committed files.
  Future<void> cancelActive() async {
    if (_disposed || !_crypto.isUnlocked || _lockFreezeRequested) {
      return;
    }
    _cancelAllRequested = true;
    final activeHandle = _activeCancelHandle;
    if (activeHandle != null) {
      await activeHandle.abort();
    }
    final toCancel = _jobs
        .where(
          (j) =>
              !j.isCommittedToVault &&
              (j.state == ImportJobState.queued ||
                  j.state == ImportJobState.preparing ||
                  j.state == ImportJobState.encrypting ||
                  j.state == ImportJobState.pausedLocked),
        )
        .toList();
    for (final j in toCancel) {
      _explicitCancelledJobIds.add(j.jobId);
      await _markExplicitCancelled(j);
    }
    _pauseReason = ImportPauseReason.none;
    _pauseMessage = null;
    _backgroundServiceWarning = null;
    await _backgroundBridge.stopImportService();
    _projectSession();
    _safeNotify();
    if (!_isWorkerRunning) {
      final lease = _activeImportLease;
      _activeImportLease = null;
      lease?.release();
    }
  }

  Future<void> cancelJob(String jobId) async {
    _explicitCancelledJobIds.add(jobId);
    final idx = _jobs.indexWhere((j) => j.jobId == jobId);
    if (idx < 0) return;
    final target = _jobs[idx];
    if (target.isCommittedToVault) return;
    if (target.state == ImportJobState.encrypting ||
        target.state == ImportJobState.preparing) {
      await _activeCancelHandle?.abort();
    }
    await _markExplicitCancelled(target);
  }

  /// Retries all failed, needs-source, pausedLocked, and queue-paused items
  /// WITHOUT re-importing already saved jobs.
  Future<void> retryEligible() async {
    if (!_crypto.isUnlocked || _disposed) return;
    final epoch = _crypto.lockEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final wasPausedQueue = _pauseReason != ImportPauseReason.none;
    _cancelAllRequested = false;
    _lockFreezeRequested = false;
    _pauseReason = ImportPauseReason.none;
    _pauseMessage = null;
    _backgroundServiceWarning = null;

    final dirty = <DurableImportJob>[];
    for (var i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (job.isCommittedToVault || job.state == ImportJobState.cancelled) {
        continue;
      }
      if (job.state == ImportJobState.failed ||
          job.state == ImportJobState.needsSource ||
          job.state == ImportJobState.pausedLocked ||
          (wasPausedQueue && job.state == ImportJobState.queued)) {
        _explicitCancelledJobIds.remove(job.jobId);
        final updated = job.copyWith(
          state: ImportJobState.queued,
          clearStagingName: true,
          clearErrorCode: true,
          updatedAtMs: nowMs,
          payload: job.payload.copyWith(clearErrorDetail: true),
        );
        _jobs[i] = updated;
        dirty.add(updated);
      }
    }
    if (dirty.isNotEmpty) {
      try {
        await _journal.upsertBatch(dirty);
      } catch (e) {
        if (e is ImportJournalException) {
          _pauseReason = ImportPauseReason.databaseFailure;
          _pauseMessage = e.safeMessage;
          _projectSession();
          _safeNotify();
          return;
        }
      }
    }
    _projectSession();
    _safeNotify();
    _startWorkerIfNeeded(epoch);
  }

  Future<void> retryJob(String jobId) async {
    if (!_crypto.isUnlocked || _disposed) return;
    final epoch = _crypto.lockEpoch;
    final idx = _jobs.indexWhere((j) => j.jobId == jobId);
    if (idx < 0) return;
    final job = _jobs[idx];
    if (job.isCommittedToVault) return;
    _explicitCancelledJobIds.remove(jobId);
    _pauseReason = ImportPauseReason.none;
    _pauseMessage = null;
    final updated = job.copyWith(
      state: ImportJobState.queued,
      clearStagingName: true,
      clearErrorCode: true,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      payload: job.payload.copyWith(clearErrorDetail: true),
    );
    _jobs[idx] = updated;
    await _journal.upsertJob(updated);
    _projectSession();
    _safeNotify();
    _startWorkerIfNeeded(epoch);
  }

  /// Clears terminal jobs when explicitly requested by the user.
  Future<void> clearFinished() async {
    if (isWorking) return;
    final toRemove = _jobs.where((j) => j.isFinishedTerminal).toList();
    if (toRemove.isEmpty) return;
    final removeIds = toRemove.map((j) => j.jobId).toList(growable: false);
    _jobs.removeWhere((j) => removeIds.contains(j.jobId));
    _explicitCancelledJobIds.removeAll(removeIds);
    try {
      await _journal.deleteJobs(removeIds);
    } catch (_) {}
    if (_jobs.isEmpty) {
      _pauseReason = ImportPauseReason.none;
      _pauseMessage = null;
      _cancelAllRequested = false;
    }
    _projectSession();
    _safeNotify();
  }

  Future<bool> _hasVaultRecord(ImportMediaKind kind, String id) {
    return kind == ImportMediaKind.photo
        ? _fileVault.hasPhoto(id)
        : _videoVault.hasVideo(id);
  }

  Future<BlobIntegrityStatus> _verifyVaultBlob(
    ImportMediaKind kind,
    String id,
  ) {
    return kind == ImportMediaKind.photo
        ? _fileVault.verifyCommittedPhotoBlob(id)
        : _videoVault.verifyCommittedVideoBlob(id);
  }

  Future<void> _removeVaultBlob(ImportMediaKind kind, String id) {
    return kind == ImportMediaKind.photo
        ? _fileVault.removeUncommittedPhotoBlob(id)
        : _videoVault.removeUncommittedVideoBlob(id);
  }

  Future<void> _recoverMetadataOnly(DurableImportJob job) {
    if (job.mediaKind == ImportMediaKind.photo) {
      return _fileVault.recoverPhotoMetadataOnly(
        id: job.destId,
        mimeType: job.payload.mimeType,
        plaintextSize: job.payload.expectedSizeBytes ?? 0,
        originalName: job.payload.displayName,
        contentHash: job.payload.contentHash ?? '',
      );
    }
    return _videoVault.recoverVideoMetadataOnly(
      id: job.destId,
      mimeType: job.payload.mimeType,
      durationS: job.payload.durationSeconds,
      plaintextSize: job.payload.expectedSizeBytes ?? 0,
      originalName: job.payload.displayName,
      contentHash: job.payload.contentHash ?? '',
    );
  }

  bool _isDiskFullError(Object e) {
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      if (code == 28 || code == 112) return true;
      final lower = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
      return lower.contains('no space') ||
          lower.contains('disk full') ||
          lower.contains('enospc') ||
          lower.contains('space left');
    }
    final lower = e.toString().toLowerCase();
    return lower.contains('database or disk is full') ||
        lower.contains('sqlite_full') ||
        lower.contains('no space');
  }

  ImportFileStatus _mapJobStatus(ImportJobState s) {
    return switch (s) {
      ImportJobState.queued => ImportFileStatus.queued,
      ImportJobState.preparing => ImportFileStatus.preparing,
      ImportJobState.encrypting => ImportFileStatus.encrypting,
      ImportJobState.committing => ImportFileStatus.committing,
      ImportJobState.pausedLocked => ImportFileStatus.pausedLocked,
      ImportJobState.needsSource => ImportFileStatus.needsSource,
      ImportJobState.savedOriginalKept => ImportFileStatus.savedOriginalKept,
      ImportJobState.awaitingDeleteConfirmation =>
        ImportFileStatus.awaitingDeleteConfirmation,
      ImportJobState.saved => ImportFileStatus.saved,
      ImportJobState.failed => ImportFileStatus.failed,
      ImportJobState.cancelled => ImportFileStatus.cancelled,
    };
  }

  void _safeNotify() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void _projectSession() {
    if (_disposed) return;
    if (!_crypto.isUnlocked || _jobs.isEmpty) {
      uiSession.syncFromProjection(
        entries: const [],
        activePosition: 0,
        cancelRequestedFlag: false,
        pauseReasonValue: ImportPauseReason.none,
      );
      return;
    }

    int activePos = 0;
    final entries = <ImportFileEntry>[];
    for (var i = 0; i < _jobs.length; i++) {
      final j = _jobs[i];
      final status = _mapJobStatus(j.state);
      if (activePos == 0 &&
          (status == ImportFileStatus.preparing ||
              status == ImportFileStatus.encrypting ||
              status == ImportFileStatus.committing)) {
        activePos = i + 1;
      }
      final liveProgress =
          (status == ImportFileStatus.preparing ||
              status == ImportFileStatus.encrypting)
          ? _activeJobProgress[j.jobId]
          : null;
      entries.add(
        ImportFileEntry(
          jobId: j.jobId,
          name: j.payload.displayName,
          status: status,
          detail: j.payload.errorDetail ?? liveProgress?.detail,
          progress: liveProgress?.fraction,
        ),
      );
    }
    if (activePos == 0) {
      final qIdx = entries.indexWhere(
        (e) => e.status == ImportFileStatus.queued,
      );
      if (qIdx >= 0) {
        activePos = qIdx + 1;
      } else {
        activePos = entries.length;
      }
    }

    uiSession.syncFromProjection(
      entries: entries,
      activePosition: activePos,
      cancelRequestedFlag: _cancelAllRequested,
      pauseReasonValue: _pauseReason,
      pauseDetail: _pauseMessage,
      backgroundWarning: _backgroundServiceWarning,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _workerGeneration++;
    _removeCryptoListener();
    _removeBeforeLockListener();
    _removeAutoLockListener();
    _removeWipeListener();
    _removeUiAccessListener?.call();
    _backgroundBridge.setCommandHandler(null);
    _backgroundBridge.stopImportService().ignore();
    _activeImportLease?.release();
    _activeImportLease = null;
    _activeCancelHandle?.abort().ignore();
    _activeCancelHandle = null;
    _foregroundTokens.clear();
    _journal.close().ignore();
    uiSession.dispose();
    super.dispose();
  }
}

final importCoordinatorProvider = ChangeNotifierProvider<ImportCoordinator>((
  ref,
) {
  return ImportCoordinator(
    crypto: ref.read(vaultCryptoProvider),
    platformService: ref.read(platformServiceProvider),
    fileVault: ref.read(fileVaultServiceProvider),
    videoVault: ref.read(videoVaultServiceProvider),
    pickerAdapter: ref.read(mediaPickerAdapterProvider),
    journal: ref.read(importJournalStoreProvider),
    storageProbe: ref.read(importStorageSpaceProbeProvider),
    stageHooks: ref.read(importStageHooksProvider),
    backgroundBridge: ref.read(backgroundImportBridgeProvider),
    uiAccess: ref.read(vaultUiAccessProvider),
  );
});
