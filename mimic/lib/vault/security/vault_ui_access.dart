import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../crypto/vault_crypto.dart';

/// Separate UI browsing authorization controller for [VaultCrypto].
///
/// Even while a user-initiated, progressing background import temporarily keeps
/// [VaultCrypto] unlocked behind an authorized [ImportAuthorizationLease],
/// leaving the app or exceeding the UI inactivity timeout MUST independently
/// revoke [isUiAuthorized] and conceal visible vault UI behind authentication.
class VaultUiAccessController extends ChangeNotifier {
  final VaultCrypto _crypto;
  int _observedLockEpoch;
  bool _uiReauthRequired = false;
  bool _isBackgroundConcealed = false;
  String? _lastRevocationReason;
  bool _disposed = false;

  VaultUiAccessController(this._crypto)
    : _observedLockEpoch = _readLockEpoch(_crypto) {
    _crypto.addListener(_onCryptoChanged);
  }

  static int _readLockEpoch(VaultCrypto crypto) {
    try {
      return crypto.lockEpoch;
    } on UnsupportedError {
      return crypto.isUnlocked ? 1 : 0;
    } on NoSuchMethodError {
      return crypto.isUnlocked ? 1 : 0;
    }
  }

  /// Whether private vault browsing, previews, settings, and mutations are
  /// currently authorized in the UI.
  bool get isUiAuthorized => _crypto.isUnlocked && !_uiReauthRequired;

  /// Whether vault screens must render an opaque privacy shield immediately
  /// (e.g. during app-background transitions or pending PIN redirect).
  bool get isBackgroundConcealed => _isBackgroundConcealed;

  /// True when the vault key is temporarily held for an authorized background
  /// import, but the user must re-authenticate before viewing vault contents.
  bool get requiresReauthentication => _crypto.isUnlocked && _uiReauthRequired;

  String? get lastRevocationReason => _lastRevocationReason;

  void _onCryptoChanged() {
    if (_disposed) return;
    final currentEpoch = _readLockEpoch(_crypto);
    final epochChanged = currentEpoch != _observedLockEpoch;
    final locked = !_crypto.isUnlocked;
    if (epochChanged || locked) {
      _observedLockEpoch = currentEpoch;
      final hadState =
          _uiReauthRequired ||
          _isBackgroundConcealed ||
          _lastRevocationReason != null;
      _uiReauthRequired = false;
      _isBackgroundConcealed = false;
      if (locked) {
        _lastRevocationReason = null;
      }
      if (hadState || epochChanged || locked) {
        notifyListeners();
      }
    }
  }

  /// Covers any mounted vault UI immediately when the app leaves foreground.
  void concealForBackground() {
    if (_disposed || !_crypto.isUnlocked) return;
    if (_isBackgroundConcealed) return;
    _isBackgroundConcealed = true;
    notifyListeners();
  }

  /// Removes the background privacy shield only if UI access has not expired.
  void clearBackgroundConcealIfAuthorized() {
    if (_disposed) return;
    if (!_crypto.isUnlocked || _uiReauthRequired) return;
    if (!_isBackgroundConcealed) return;
    _isBackgroundConcealed = false;
    notifyListeners();
  }

  /// Revokes UI browsing access while preserving an active background import's
  /// remaining authorization window until that work finishes, stalls, or hits
  /// its non-resetting ceiling.
  void requireReauthentication({String reason = 'ui_access_expired'}) {
    if (_disposed || !_crypto.isUnlocked) return;
    if (_uiReauthRequired &&
        _isBackgroundConcealed &&
        _lastRevocationReason == reason) {
      return;
    }
    _uiReauthRequired = true;
    _isBackgroundConcealed = true;
    _lastRevocationReason = reason;
    notifyListeners();
  }

  /// Restores UI browsing access after fresh user authentication (PIN/biometric).
  void restoreUiAccessAfterAuth() {
    if (_disposed || !_crypto.isUnlocked) return;
    final currentEpoch = _readLockEpoch(_crypto);
    final changed =
        _observedLockEpoch != currentEpoch ||
        _uiReauthRequired ||
        _isBackgroundConcealed ||
        _lastRevocationReason != null;
    _observedLockEpoch = currentEpoch;
    _uiReauthRequired = false;
    _isBackgroundConcealed = false;
    _lastRevocationReason = null;
    if (changed) {
      notifyListeners();
    }
  }

  /// Clears transient conceal/reauth flags on full vault lock.
  void resetForLock() {
    if (_disposed) return;
    _observedLockEpoch = _readLockEpoch(_crypto);
    final changed =
        _uiReauthRequired ||
        _isBackgroundConcealed ||
        _lastRevocationReason != null;
    _uiReauthRequired = false;
    _isBackgroundConcealed = false;
    _lastRevocationReason = null;
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _crypto.removeListener(_onCryptoChanged);
    super.dispose();
  }
}

final vaultUiAccessProvider = ChangeNotifierProvider<VaultUiAccessController>((
  ref,
) {
  // Use ref.read (never ref.watch) because VaultUiAccessController already
  // subscribes directly to VaultCrypto.addListener(_onCryptoChanged). Rebuilding
  // on every VaultCrypto.notifyListeners() would dispose the instance retained
  // by ImportCoordinator.
  final crypto = ref.read(vaultCryptoProvider);
  return VaultUiAccessController(crypto);
});
