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

  /// Never published anywhere. Live ONLY while no vault exists.
  static const List<int> setupPassage = [0, 2, 1];

  /// Verifies whether the given tap sequence should open the vault.
  ///
  /// 1. Reads the vault salt via [readVaultSalt].
  /// 2. If the salt is null or empty, no vault exists: returns true iff [taps]
  ///    matches [setupPassage] element by element without key derivation.
  /// 3. Otherwise a vault exists: returns the result of verifying against the
  ///    stored gesture in [GestureStore]. Never falls back to [setupPassage]
  ///    or any constant.
  Future<bool> verify(List<int> taps) async {
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

    return _store.verifyGesture(taps);
  }
}
