// lib/vault/services/quick_entry_service.dart
//
// F27 — Pro quick-entry (auth-preserving, disguised, opt-in), Phase 1.
//
// What this file does: remembers whether the owner enabled the Pro
// quick-entry path (secure-storage key `pro_quick_entry_enabled`,
// 'true'/'false', default OFF when missing). It answers ONLY the
// preference question — never Pro status itself (that is
// ProStatusService) and never vault existence (checked at tap time
// from `vault_salt`).
//
// Why secure storage: the flag gates a paid convenience, so it lives
// beside the other vault secrets in FlutterSecureStorage
// (encryptedSharedPreferences on Android), not in plaintext prefs.
//
// Why default OFF and lapse-safe at the CALLER, not here: a stale
// 'true' on a lapsed install must behave exactly like an ordinary
// game tap. Both the settings toggle and the home-screen entry check
// isPro() at use time; this service never decides that itself.
// Never throws: unreadable storage reads as disabled, failed writes
// propagate so the toggle can report them honestly.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/platform_service.dart';

/// Secure-storage key holding the quick-entry preference.
const String quickEntryEnabledKey = 'pro_quick_entry_enabled';

/// The only stored value that means enabled.
const String quickEntryEnabledValue = 'true';

/// Secure-storage key that proves a vault exists (written at vault
/// creation). The literal matches VaultCrypto's private `_storageKeySalt`;
/// pinning it here keeps this file dependency-free without inventing a
/// second name for the same key.
const String quickEntryVaultSaltKey = 'vault_salt';

/// Secure-storage key the conceal kill-switch writes. 'true' means the
/// vault is hidden — the same read VaultConcealService.isConcealed()
/// performs — and the quick entry must be dead with it.
const String quickEntryVaultConcealedKey = 'vault_concealed';
const String quickEntryVaultConcealedValue = 'true';

/// Remembers the quick-entry preference. Constructed with a
/// [PlatformService] so tests can pass a fake and the app passes the
/// real one via [quickEntryServiceProvider] below.
class QuickEntryService {
  QuickEntryService(this._platform);

  final PlatformService _platform;

  /// Reads the preference. Never throws: any storage error answers
  /// disabled, because a gate that crashes open is worse than one
  /// that fails closed.
  Future<bool> isEnabled() async {
    try {
      return await _platform.secureRead(quickEntryEnabledKey) ==
          quickEntryEnabledValue;
    } catch (_) {
      return false;
    }
  }

  /// Persists the preference. Throws on storage failure so the toggle
  /// can report the failure instead of pretending it saved.
  Future<void> setEnabled(bool enabled) async {
    await _platform.secureWrite(
      quickEntryEnabledKey,
      enabled ? quickEntryEnabledValue : 'false',
    );
  }

  /// F27 — the single entry-gate decision. Answers true only when ALL of
  /// these hold:
  ///   1. [isPro] — the entitlement, re-read at tap time by the caller, so
  ///      a lapsed install's stale 'true' degrades silently to an ordinary
  ///      game tap (the golden rule; lapse-safety lives in this check).
  ///   2. The stored preference is on ([isEnabled]).
  ///   3. A vault exists — `vault_salt` is present.
  ///   4. The vault is not concealed — `vault_concealed` is not 'true'.
  /// Never throws: any storage error answers false, because a failed gate
  /// must behave exactly like an ordinary game tap (no error, no hint, no
  /// delay). This is navigation ONLY — the PIN screen still does all the
  /// authentication it always did.
  Future<bool> shouldOpenEntry({required bool isPro}) async {
    if (!isPro) return false;
    if (!await isEnabled()) return false;
    try {
      final salt = await _platform.secureRead(quickEntryVaultSaltKey);
      if (salt == null || salt.isEmpty) return false;
      final concealed =
          await _platform.secureRead(quickEntryVaultConcealedKey);
      if (concealed == quickEntryVaultConcealedValue) return false;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Riverpod access to the quick-entry preference service.
final quickEntryServiceProvider = Provider<QuickEntryService>((ref) {
  return QuickEntryService(ref.read(platformServiceProvider));
});
