// lib/vault/security/auto_lock.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../crypto/vault_crypto.dart';
import '../services/media_stream_server.dart';
import '../services/pro_status_service.dart';
import '../services/video_vault_service.dart';
import '../../core/services/platform_service.dart';
import '../../core/router/app_router.dart' as router;
import 'vault_ui_access.dart';

/// Scoped, idempotent protected-operation ownership token.
///
/// Releasing a lease obtained during an earlier unlock session is a no-op once
/// [AutoLock.init], [AutoLock.dispose], or a lock transition advances the
/// session epoch, preventing stale work from releasing a new session's protection.
class AutoLockLease {
  final AutoLock _owner;
  final int _sessionEpoch;
  bool _released = false;

  AutoLockLease._(this._owner, this._sessionEpoch);

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    _owner._releaseProtectedOperationLease(_sessionEpoch);
  }
}

/// Separate background import authorization token held ONLY while a
/// user-initiated import worker is actively making forward progress.
///
/// Independent from UI browsing access ([VaultUiAccessController]) so leaving
/// the app or exceeding the UI timeout locks vault browsing behind auth without
/// aborting active encryption within its bounded stall and non-resetting
/// 30-minute ceiling.
class ImportAuthorizationLease {
  final AutoLock _owner;
  final Object _token;
  bool _released = false;

  ImportAuthorizationLease._(this._owner, this._token);

  bool get isReleased => _released;
  bool get isActive => !_released && _owner._isImportLeaseActive(_token);

  void recordProgress() {
    if (_released) return;
    _owner.recordImportProgress(token: _token);
  }

  void release() {
    if (_released) return;
    _released = true;
    _owner._releaseImportAuthorization(_token);
  }
}

class AutoLock with WidgetsBindingObserver {
  static final AutoLock _instance = AutoLock._internal();
  factory AutoLock() => _instance;
  AutoLock._internal();

  static GlobalKey<NavigatorState> get navigatorKey => router.navigatorKey;

  Timer? _timer;
  Timer? _suspendTimer;
  Timer? _backgroundUiExpiryTimer;
  Timer? _importStallTimer;
  Timer? _importCeilingTimer;
  BuildContext? _context;
  WidgetRef? _ref;
  ProviderContainer? _container;
  DateTime Function() _now = DateTime.now;
  // M20: three different clocks, for three different situations.
  //   foreground idle   5 minutes  — long enough to read a screen, short enough that an
  //                                  abandoned unlocked phone does not stay open.
  //                                  F7: configurable (see _idleTimeout below); the
  //                                  5-minute value is the protective default.
  //   background grace  1 minute   — the app is unattended and out of sight; lock fast. This
  //                                  applies even when a screen has paused the idle clock.
  //                                  NEVER user-configurable (F7 design constraint).
  //   suspendCeiling    30 minutes — final backstop for read-only screens (decision D13).
  //   (The old `_timeout` const is retired: [defaultIdleTimeout] below is
  //   its replacement as the protective default, kept equal at 5 minutes.)
  static const Duration _backgroundGrace = Duration(minutes: 1);
  static const Duration suspendCeiling = Duration(minutes: 30);
  static const Duration defaultImportStallDeadline = Duration(minutes: 2);
  // F7: the foreground idle clock is user-configurable. Free choices run
  // from the protective default up to the free ceiling; Pro choices may
  // extend to the absolute cap (which equals the suspend ceiling on
  // purpose — nothing the user picks can outlive the final backstop).
  // The background grace has no equivalent knob: it stays 1 minute.
  static const Duration defaultIdleTimeout = Duration(minutes: 5);
  static const Duration freeIdleCeiling = Duration(minutes: 10);
  static const Duration absoluteIdleCap = Duration(minutes: 30);
  Duration _idleTimeout = defaultIdleTimeout;
  Duration _importStallDeadline = defaultImportStallDeadline;

  @visibleForTesting
  Duration get idleTimeoutForTesting => _idleTimeout;

  @visibleForTesting
  void setIdleTimeoutForTesting(Duration value) {
    _idleTimeout = value;
  }

  @visibleForTesting
  void setNowForTesting(DateTime Function() fn) {
    _now = fn;
  }

  @visibleForTesting
  void setImportStallDeadlineForTesting(Duration value) {
    _importStallDeadline = value;
  }

  @visibleForTesting
  void resetClockForTesting() {
    _now = DateTime.now;
    _importStallDeadline = defaultImportStallDeadline;
  }

  @visibleForTesting
  void attachContainerForTesting(ProviderContainer? container) {
    _container = container;
  }

  /// F7: loads the persisted foreground-idle choice from secure storage at
  /// unlock ('auto_lock_idle_minutes', whole minutes). A Pro choice above
  /// the free ceiling is honoured ONLY while [isPro] is true — a lapsed
  /// install with a stale Pro value silently degrades to the free ceiling,
  /// never to a lockout and never below the protective default. Never
  /// throws: unreadable storage keeps the default.
  Future<void> loadIdleTimeout({required bool isPro}) async {
    final container = _container;
    if (container == null) return;
    try {
      final stored = await container
          .read(platformServiceProvider)
          .secureRead('auto_lock_idle_minutes');
      final minutes = int.tryParse(stored ?? '');
      if (minutes == null) {
        _idleTimeout = defaultIdleTimeout;
        return;
      }
      final wanted = Duration(minutes: minutes);
      final ceiling = isPro ? absoluteIdleCap : freeIdleCeiling;
      _idleTimeout = wanted < defaultIdleTimeout
          ? defaultIdleTimeout
          : (wanted > ceiling ? ceiling : wanted);
    } catch (_) {
      _idleTimeout = defaultIdleTimeout;
    }
  }

  bool _observerRegistered = false;
  DateTime? _backgroundedAt;
  DateTime _uiLastActivityAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Separate background import authorization state: independent of UI browsing
  // access, bounded by progress stall detection and a non-resetting 30-minute
  // maximum exemption ceiling.
  Object? _activeImportLeaseToken;
  void Function(String reason)? _importRevokeCallback;
  DateTime? _importCeilingDeadline;
  DateTime? _lastImportProgressAt;

  // M22: Android delivers the picker result and the "back in foreground" event
  // independently, and the order is not guaranteed. Cancelling the picker releases the
  // protected-operation claim instantly, so by the time the foreground event arrives
  // the counter is already zero and the 1-minute background rule locks the vault -
  // confirmed on device 2026-08-20. Recording whether a claim was held AT THE MOMENT
  // WE LEFT the foreground removes the race, because that answer cannot change while
  // the app is away. The 30-minute ceiling still applies to the trip.
  bool _protectedOpAtPause = false;
  // M18: six screens share this one pause. A boolean let whichever screen resumed first
  // un-pause the vault for the others. The counter means the idle timer only restarts when
  // the LAST caller has resumed. The 30-minute ceiling (decision D13) is armed by the first
  // caller and is not extended by later ones.
  int _suspendCount = 0;

  // M21: a protected operation is an encrypt or decrypt that is actively writing a file.
  // Locking mid-write clears the keys and deletes the transient plaintext while a blob is
  // half-written, which corrupts it. This is the ONLY exemption from the 1-minute background
  // rule, and it exists to prevent data loss, not for convenience.
  int _protectedOpCount = 0;

  @visibleForTesting
  bool get isSuspended => _suspendCount > 0;

  @visibleForTesting
  int get suspendCount => _suspendCount;

  @visibleForTesting
  bool get isProtectedOperationInFlight => _protectedOpCount > 0;

  @visibleForTesting
  int get protectedOperationCount => _protectedOpCount;

  bool get hasActiveImportAuthorization => _activeImportLeaseToken != null;

  @visibleForTesting
  DateTime? get importCeilingDeadlineForTesting => _importCeilingDeadline;

  @visibleForTesting
  DateTime? get lastImportProgressAtForTesting => _lastImportProgressAt;

  @visibleForTesting
  void setBackgroundedAtForTesting(DateTime? dt) {
    _backgroundedAt = dt;
  }

  /// Initializes the inactivity timer. Called when vault is unlocked or
  /// when UI browsing re-authenticates while a background import continues.
  final List<void Function()> _onLockCallbacks = [];

  /// Registers a callback fired immediately when auto-lock or conceal lock
  /// begins tearing down the active session. Returns an unsubscribe callback.
  void Function() registerOnLock(void Function() callback) {
    _onLockCallbacks.add(callback);
    return () => _onLockCallbacks.remove(callback);
  }

  void _notifyOnLock() {
    for (final cb in List<void Function()>.from(_onLockCallbacks)) {
      try {
        cb();
      } catch (_) {}
    }
  }

  Duration _effectiveBackgroundGrace() => _backgroundGrace;

  VaultUiAccessController? _readUiAccess() {
    final container = _container;
    if (container == null) return null;
    try {
      return container.read(vaultUiAccessProvider);
    } catch (_) {
      return null;
    }
  }

  bool _isUiAuthorizedOrFallbackUnlocked() {
    final uiAccess = _readUiAccess();
    if (uiAccess != null) return uiAccess.isUiAuthorized;
    final container = _container;
    if (container == null) return true;
    try {
      return container.read(vaultCryptoProvider).isUnlocked;
    } catch (_) {
      return false;
    }
  }

  void init(BuildContext context, WidgetRef ref) {
    _sessionEpoch++;
    _context = context;
    _ref = ref;
    _container = ProviderScope.containerOf(context, listen: false);

    final videoVaultService = ref.read(videoVaultServiceProvider);
    final platformService = ref.read(platformServiceProvider);
    MediaStreamServer.instance.init(
      videoVaultService: videoVaultService,
      resolveVaultFile: platformService.resolveVaultFile,
      decryptRange: (f, o, l) =>
          VaultCrypto.instance.decryptRangeSystem(f, o, l),
    );

    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _observerRegistered = true;
    }

    // M19: a suspend that never got its matching resume would leave the counter above zero,
    // and resetTimer() would then never arm the idle timer again for the rest of the session.
    // Unlocking is a clean slate: nobody can legitimately be holding a pause at this moment.
    // F7: the persisted foreground-idle choice loads here too (best-effort).
    _suspendCount = 0;
    _backgroundUiExpiryTimer?.cancel();
    _backgroundUiExpiryTimer = null;
    _backgroundedAt = null;
    unawaited(_loadIdleTimeoutBestEffort());
    _protectedOpCount = 0;
    _protectedOpAtPause = false;
    _readUiAccess()?.restoreUiAccessAfterAuth();

    resetTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        final now = _now();
        if (_backgroundedAt == null) {
          _backgroundedAt = now;
          _protectedOpAtPause = _protectedOpCount > 0;
        }
        _readUiAccess()?.concealForBackground();
        _timer?.cancel(); // foreground idle timer is meaningless in background
        _backgroundUiExpiryTimer?.cancel();
        if (hasActiveImportAuthorization) {
          final grace = _effectiveBackgroundGrace();
          _backgroundUiExpiryTimer = Timer(grace, () {
            if (_backgroundedAt == null) return;
            if (hasActiveImportAuthorization) {
              _requireUiReauthentication(reason: 'background_ui_timeout');
            }
          });
        }
        break;
      case AppLifecycleState.resumed:
        _backgroundUiExpiryTimer?.cancel();
        _backgroundUiExpiryTimer = null;
        final since = _backgroundedAt;
        _backgroundedAt = null;
        final now = _now();
        final bool protectedTrip = _protectedOpCount > 0 || _protectedOpAtPause;
        _protectedOpAtPause = false;

        if (hasActiveImportAuthorization) {
          final ceiling = _importCeilingDeadline;
          final elapsedBg = since == null
              ? Duration.zero
              : now.difference(since);
          final elapsedUiIdle = now.difference(_uiLastActivityAt);
          if ((ceiling != null && !now.isBefore(ceiling)) ||
              elapsedBg >= suspendCeiling) {
            revokeBackgroundImport(
              reason: 'import_ceiling_exceeded',
              lockVault: true,
            );
            break;
          }
          if (!_isUiAuthorizedOrFallbackUnlocked() ||
              (!protectedTrip &&
                  (elapsedBg >= _effectiveBackgroundGrace() ||
                      elapsedUiIdle >= _idleTimeout))) {
            _requireUiReauthentication(reason: 'background_ui_timeout');
            break;
          }
          _readUiAccess()?.clearBackgroundConcealIfAuthorized();
          if (_suspendCount == 0) {
            resetTimer();
          }
          break;
        }

        if (protectedTrip) {
          if (since != null && now.difference(since) >= suspendCeiling) {
            _lockVault();
          } else {
            _readUiAccess()?.clearBackgroundConcealIfAuthorized();
          }
        } else if (since != null &&
            now.difference(since) >= _effectiveBackgroundGrace()) {
          _lockVault();
        } else if (_suspendCount > 0) {
          // Leave it paused, do not restart idle timer
          _readUiAccess()?.clearBackgroundConcealIfAuthorized();
        } else {
          _readUiAccess()?.clearBackgroundConcealIfAuthorized();
          resetTimer();
        }
        break;
      case AppLifecycleState.inactive:
        break; // transient (app switcher / shade) -> ignore, never lock
    }
  }

  /// Resets the UI inactivity timer. Called ONLY on genuine user UI
  /// interactions — never by background import worker progress or batches.
  void resetTimer() {
    _uiLastActivityAt = _now();
    _timer?.cancel();
    if (_suspendCount > 0) return;
    if (_context == null || _ref == null) return;
    _timer = Timer(_idleTimeout, _handleUiIdleTimeout);
  }

  void _handleUiIdleTimeout() {
    if (hasActiveImportAuthorization) {
      _requireUiReauthentication(reason: 'ui_idle_timeout');
      return;
    }
    _lockVault();
  }

  /// F7 helper: reads the Pro flag and the persisted idle choice without
  /// ever throwing; unlock must never fail because a preference was
  /// unreadable. A missing import would be a compile error, not a runtime
  /// one — the Pro service is part of Phase 1 scaffolding.
  Future<void> _loadIdleTimeoutBestEffort() async {
    final container = _container;
    if (container == null) return;
    try {
      final isPro = await container.read(proStatusServiceProvider).isPro();
      await loadIdleTimeout(isPro: isPro);
    } catch (_) {}
  }

  void suspend() {
    _suspendCount++;
    if (_suspendCount == 1) {
      _timer?.cancel();
      _timer = null;
      _suspendTimer?.cancel();
      _suspendTimer = Timer(suspendCeiling, _lockVault);
    }
  }

  void resume() {
    if (_suspendCount > 0) {
      _suspendCount--;
      if (_suspendCount == 0) {
        _suspendTimer?.cancel();
        _suspendTimer = null;
        resetTimer();
      }
    }
  }

  int _sessionEpoch = 0;

  void _releaseProtectedOperationLease(int epoch) {
    if (epoch != _sessionEpoch) return;
    endProtectedOperation();
  }

  /// Acquires an epoch-scoped, idempotent lease for a protected operation.
  AutoLockLease acquireProtectedOperation() {
    beginProtectedOperation();
    return AutoLockLease._(this, _sessionEpoch);
  }

  void beginProtectedOperation() {
    _protectedOpCount++;
    suspend();
  }

  void endProtectedOperation() {
    if (_protectedOpCount > 0) {
      _protectedOpCount--;
      resume();
    }
  }

  /// Acquires a bounded, progress-checked background import authorization lease
  /// separate from UI access.
  ///
  /// The 30-minute maximum exemption window ([suspendCeiling]) is armed once at
  /// the start of continuous import authorization and is NEVER extended when
  /// additional batches are appended.
  ImportAuthorizationLease acquireImportAuthorization({
    required int cryptoEpoch,
    ProviderContainer? container,
    void Function(String reason)? onRevoke,
  }) {
    if (container != null) {
      _container ??= container;
    }
    final now = _now();
    final token = Object();
    _activeImportLeaseToken = token;
    _importRevokeCallback = onRevoke;
    _lastImportProgressAt = now;

    // Non-resetting 30-minute exemption window: do NOT push deadline out if
    // already armed during this active authorization window.
    if (_importCeilingDeadline == null) {
      _importCeilingDeadline = now.add(suspendCeiling);
      _importCeilingTimer?.cancel();
      _importCeilingTimer = Timer(suspendCeiling, () {
        revokeBackgroundImport(
          reason: 'import_ceiling_exceeded',
          lockVault: true,
        );
      });
    }

    _armImportStallTimer();
    return ImportAuthorizationLease._(this, token);
  }

  bool _isImportLeaseActive(Object token) =>
      identical(_activeImportLeaseToken, token);

  /// Records genuine worker progress (e.g., resolved/hashed/chunk/committed)
  /// so the bounded stall watchdog stays green while active work flows.
  ///
  /// Explicitly NEVER resets the UI inactivity timer ([_uiLastActivityAt]).
  void recordImportProgress({Object? token}) {
    if (_activeImportLeaseToken == null) return;
    if (token != null && !identical(_activeImportLeaseToken, token)) return;
    final prev = _lastImportProgressAt;
    final now = _now();
    _lastImportProgressAt = now;
    if (_importStallTimer == null ||
        _importStallDeadline <= const Duration(seconds: 5) ||
        prev == null ||
        now.difference(prev) >= const Duration(seconds: 2)) {
      _armImportStallTimer();
    }
  }

  void _armImportStallTimer() {
    _importStallTimer?.cancel();
    if (_activeImportLeaseToken == null) return;
    _importStallTimer = Timer(_importStallDeadline, _handleImportStallTimeout);
  }

  void _handleImportStallTimeout() {
    final token = _activeImportLeaseToken;
    if (token == null) return;
    final lastProgress = _lastImportProgressAt;
    if (lastProgress != null &&
        _now().difference(lastProgress) < _importStallDeadline) {
      final remaining = _importStallDeadline - _now().difference(lastProgress);
      _importStallTimer = Timer(remaining, _handleImportStallTimeout);
      return;
    }
    revokeBackgroundImport(
      reason: 'import_stall_timeout',
      lockVault: !_isUiAuthorizedOrFallbackUnlocked(),
    );
  }

  @visibleForTesting
  void checkImportWatchdogsNow() {
    final token = _activeImportLeaseToken;
    if (token == null) return;
    final now = _now();
    final ceiling = _importCeilingDeadline;
    if (ceiling != null && !now.isBefore(ceiling)) {
      revokeBackgroundImport(
        reason: 'import_ceiling_exceeded',
        lockVault: true,
      );
      return;
    }
    final lastProgress = _lastImportProgressAt;
    if (lastProgress != null &&
        now.difference(lastProgress) >= _importStallDeadline) {
      revokeBackgroundImport(
        reason: 'import_stall_timeout',
        lockVault: !_isUiAuthorizedOrFallbackUnlocked(),
      );
    }
  }

  void _releaseImportAuthorization(Object token) {
    if (!identical(_activeImportLeaseToken, token)) return;
    _clearImportLeaseState(clearCeiling: true);
    if (!_isUiAuthorizedOrFallbackUnlocked()) {
      _lockVault();
    }
  }

  void _clearImportLeaseState({required bool clearCeiling}) {
    _activeImportLeaseToken = null;
    _importRevokeCallback = null;
    _importStallTimer?.cancel();
    _importStallTimer = null;
    _lastImportProgressAt = null;
    if (clearCeiling) {
      _importCeilingTimer?.cancel();
      _importCeilingTimer = null;
      _importCeilingDeadline = null;
    }
  }

  /// Revokes any active background import authorization immediately, notifying
  /// the coordinator to halt dispatch/abort active worker isolates. If
  /// [lockVault] is true (or when explicit security actions call [revokeAllAndLock]),
  /// the vault key is destroyed too.
  void revokeBackgroundImport({
    String reason = 'security_revoked',
    bool lockVault = false,
  }) {
    final cb = _importRevokeCallback;
    _clearImportLeaseState(clearCeiling: true);
    if (cb != null) {
      try {
        cb(reason);
      } catch (_) {}
    }
    if (lockVault) {
      _lockVault();
    }
  }

  /// Explicit security override (manual lock, panic, duress, decoy, wipe):
  /// revokes background import authorization, cancels running workers, clears
  /// vault keys, wipes transient plaintext, and resets UI state.
  void revokeAllAndLock({
    String reason = 'manual_lock',
    VaultCrypto? fallbackCrypto,
  }) {
    revokeBackgroundImport(reason: reason, lockVault: false);
    _notifyOnLock();
    VaultCrypto? crypto = fallbackCrypto;
    final container = _container;
    if (crypto == null && container != null) {
      try {
        crypto = container.read(vaultCryptoProvider);
      } catch (_) {}
    }
    crypto?.clearKey();
    _readUiAccess()?.resetForLock();
    unawaited(MediaStreamServer.instance.stop());
    unawaited(wipeTransientPlaintext());
    dispose();
  }

  void _requireUiReauthentication({required String reason}) {
    _timer?.cancel();
    _timer = null;
    _backgroundUiExpiryTimer?.cancel();
    _backgroundUiExpiryTimer = null;
    _readUiAccess()?.requireReauthentication(reason: reason);
    unawaited(MediaStreamServer.instance.stop());
    unawaited(wipeTransientPlaintext());
    AutoLock.navigatorKey.currentState?.pushNamedAndRemoveUntil(
      router.AppRouter.vaultPinRoute,
      router.AppRouter.isNotVaultRoute,
    );
  }

  /// Full teardown for the conceal path: stops the media server, wipes transient
  /// plaintext, and cancels the idle timer and lifecycle observer. Fire-and-forget
  /// so that concealment navigation is never delayed by disk I/O.
  void tearDownForConceal() {
    revokeBackgroundImport(reason: 'conceal', lockVault: false);
    _notifyOnLock();
    _readUiAccess()?.resetForLock();
    unawaited(MediaStreamServer.instance.stop());
    unawaited(wipeTransientPlaintext());
    dispose();
  }

  /// Cancels the timer and stops the media server. Called when manually locked
  /// or panic mode triggers, so every manual lock path tears down streaming.
  void dispose() {
    _sessionEpoch++;
    _clearImportLeaseState(clearCeiling: true);
    _backgroundUiExpiryTimer?.cancel();
    _backgroundUiExpiryTimer = null;
    unawaited(MediaStreamServer.instance.stop());
    _timer?.cancel();
    _timer = null;
    _suspendTimer?.cancel();
    _suspendTimer = null;
    _context = null;
    _ref = null;
    _container = null;
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _backgroundedAt = null;
    _suspendCount = 0;
    _protectedOpCount = 0;
    _protectedOpAtPause = false;
  }

  static const _maxSecureWipeBytes = 64 * 1024 * 1024;

  static Future<void> secureDeleteFile(File f) async {
    try {
      if (!await f.exists()) return;
      final len = await f.length();
      if (len > 0 && len <= _maxSecureWipeBytes) {
        // Best-effort overwrite (FTL/wear-leveling may map to new physical blocks)
        final raf = await f.open(mode: FileMode.writeOnly);
        try {
          final rand = Random.secure();
          const chunkSize = 64 * 1024;
          var remaining = len;
          while (remaining > 0) {
            final writeSize = remaining < chunkSize ? remaining : chunkSize;
            final buf = Uint8List.fromList(
              List.generate(writeSize, (_) => rand.nextInt(256)),
            );
            await raf.writeFrom(buf);
            remaining -= writeSize;
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
      }
      await f.delete();
    } catch (_) {}
  }

  static Future<void> secureDeleteDir(Directory d) async {
    try {
      if (!await d.exists()) return;
      await for (final entity in d.list(recursive: true)) {
        if (entity is File) {
          await secureDeleteFile(entity);
        }
      }
      await d.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> wipeTransientPlaintext() async {
    try {
      final tempDir = await getTemporaryDirectory();
      for (final name in const [
        'vault_playback',
        'vault_docs',
        'vault_share',
      ]) {
        final dir = Directory('${tempDir.path}/$name');
        await secureDeleteDir(dir);
      }
      await for (final entity in tempDir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.contains('_migrate_plain_') ||
              name.contains('_migrate_ctr_')) {
            await secureDeleteFile(entity);
          }
        }
      }
    } catch (_) {}
  }

  void _lockVault() async {
    final container = _container;
    if (container == null) {
      _suspendCount = 0;
      _protectedOpCount = 0;
      _protectedOpAtPause = false;
      return;
    }

    final bool wasUnlocked;
    var uiAlreadyReauthenticating = false;
    try {
      final crypto = container.read(vaultCryptoProvider);
      wasUnlocked = crypto.isUnlocked;
      if (!wasUnlocked) {
        dispose();
        return;
      }
      uiAlreadyReauthenticating =
          _readUiAccess()?.requiresReauthentication ?? false;
      _sessionEpoch++;
      final cb = _importRevokeCallback;
      _clearImportLeaseState(clearCeiling: true);
      if (cb != null) {
        try {
          cb('vault_locked');
        } catch (_) {}
      }
      _notifyOnLock();
      // Clear Vault keys
      crypto.clearKey();
      _readUiAccess()?.resetForLock();
    } on StateError {
      dispose();
      return;
    }

    unawaited(MediaStreamServer.instance.stop());

    await wipeTransientPlaintext();

    if (!uiAlreadyReauthenticating) {
      AutoLock.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        router.AppRouter.vaultPinRoute,
        router.AppRouter.isNotVaultRoute,
      );
    }

    dispose();
  }
}

/// A wrapper widget that transparently listens to all user interactions
/// (tap down, scrolls, swipe/drag, mouse movement) to reset the auto-lock timer.
class AutoLockWrapper extends StatelessWidget {
  final Widget child;

  const AutoLockWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => AutoLock().resetTimer(),
      onPointerMove: (_) => AutoLock().resetTimer(),
      onPointerSignal: (_) => AutoLock().resetTimer(),
      child: child,
    );
  }
}
