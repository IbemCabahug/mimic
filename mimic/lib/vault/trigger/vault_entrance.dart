// lib/vault/trigger/vault_entrance.dart

import 'gesture_store.dart';

/// Decides whether a tap sequence entered during voting should open the vault.
///
/// DESIGN & SECURITY CONSTRAINTS:
/// - The setup passage exists only so a fresh install can reach vault creation
///   before any gesture is stored.
/// - Once vault_salt exists, the passage is permanently dead and the stored
///   gesture is the only way in.
/// - There is deliberately no legacy fallback: the previously published
///   sequence [2, 0, 2] must never be accepted again.
class VaultEntrance {
  VaultEntrance({
    required Future<String?> Function() readVaultSalt,
    GestureStore? store,
  })  : _readVaultSalt = readVaultSalt,
        _store = store ?? GestureStore();

  final Future<String?> Function() _readVaultSalt;
  final GestureStore _store;

  /// Only the positive result ("vault exists") is cached.
  ///
  /// A vault can be created during the lifetime of this object, and caching
  /// "no vault" would keep the setup passage alive after it should be dead.
  /// Once a vault exists it can never stop existing while this object lives.
  bool _vaultExistsCached = false;

  /// Warms [_vaultExistsCached] during idle time (e.g. when the voting screen
  /// mounts) by checking whether a gesture record is stored.
  ///
  /// This moves one platform-channel read off the unlock path so the first
  /// gesture attempt only needs a single read (for verification) instead of
  /// two. Never throws to the caller and never caches a negative result.
  Future<void> prewarm() async {
    try {
      if (_vaultExistsCached) return;
      if (await _store.hasGesture()) {
        _vaultExistsCached = true;
      }
    } catch (_) {
      // Swallowed: idle prewarming must never disrupt startup or surface errors.
    }
  }

  /// Never published anywhere. Live ONLY while no vault exists.
  static const List<int> setupPassage = [0, 2, 1];

  /// Verifies whether the given tap sequence should open the vault.
  ///
  /// 1. If [_vaultExistsCached] is true, delegates directly to
  ///    [_store.verifyGesture].
  /// 2. Otherwise asks [_store.hasGesture] whether a gesture record exists.
  ///    If it does, a vault necessarily exists (a gesture can only be set
  ///    during or after vault creation), so caches [_vaultExistsCached] = true
  ///    and delegates to [_store.verifyGesture].
  /// 3. Only if there is no gesture record, reads vault salt via
  ///    [_readVaultSalt]:
  ///    - If the salt is null or empty, no vault exists: returns true iff [taps]
  ///      matches [setupPassage] element by element without key derivation,
  ///      caching nothing.
  ///    - Otherwise a vault exists but no gesture is stored: returns false
  ///      without caching. The passage remains dead.
  Future<bool> verify(List<int> taps) async {
    if (_vaultExistsCached) {
      return _store.verifyGesture(taps);
    }

    if (await _store.hasGesture()) {
      _vaultExistsCached = true;
      return _store.verifyGesture(taps);
    }

    final salt = await _readVaultSalt();
    if (salt == null || salt.isEmpty) {
      if (taps.length != setupPassage.length) {
        return false;
      }
      for (int i = 0; i < setupPassage.length; i++) {
        if (taps[i] != setupPassage[i]) {
          return false;
        }
      }
      return true;
    }

    return false;
  }
}
