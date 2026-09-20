// lib/vault/services/pro_status_service.dart
//
// Phase 1 of the paid tier: the entitlement source of truth.
//
// What this file does: answers one question — "is this install Pro?" —
// from a value cached in secure storage (key `pro_entitlement`), so the
// answer survives restarts and works fully offline. Google Play remains
// the authority that GRANTS the status; this service only REMEMBERS what
// Play last said. The billing wiring that talks to Play (purchase stream,
// restorePurchases, completePurchase) lands in a later phase; until then
// every install reads Pro (see [kBillingEnforced] below), so the Pro
// features ship unlocked to everyone while the app grows.
//
// Why secure storage and not SharedPreferences: the flag gates paid
// features, so it lives beside the other vault secrets in
// FlutterSecureStorage (encryptedSharedPreferences on Android) rather
// than in the plaintext prefs file. A rooted device can still flip it —
// there is no server check — which is why NOTHING protective is ever
// gated by it (see the golden rule in future_feature.md).
//
// Why the cache defaults to free: a missing or unreadable key means
// "never granted", never "assume Pro". Lapse and reinstall both degrade
// to free, and free always keeps open + export.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/platform_service.dart';

/// Pre-billing enforcement switch.
///
/// While this is false (the current launch window), [ProStatusService.isPro]
/// answers true for EVERY install — Play billing is not wired yet, and the
/// owner wants early downloaders to have the features unlocked before
/// billing separates Pro from free. Nothing protective is gated by Pro
/// (the golden rule), so opening the gate cannot weaken security.
///
/// When Phase-2 billing lands, flip this to true and every gate falls back
/// to the stored entitlement: installs Play has not granted read free. No
/// storage migration is needed — nothing was ever written to say Pro.
const bool kBillingEnforced = false;

/// Secure-storage key holding the cached entitlement.
const String proEntitlementKey = 'pro_entitlement';

/// Values of [proEntitlementKey]. Only 'pro' means Pro; anything else —
/// including a missing key, an empty string, or a value written by an
/// older build — means free.
const String proEntitlementValue = 'pro';

/// Answers "is this install Pro?" from the secure-storage cache.
///
/// During the pre-billing window ([kBillingEnforced] is false) this answers
/// true for everyone, before storage is even consulted. Once billing is
/// enforced, the cached entitlement decides — with [billingEnforced]
/// overridable per instance so tests can pin either era's behaviour.
///
/// Constructed with a [PlatformService] so tests can pass a fake and the
/// app passes the real one via [proStatusServiceProvider] below.
class ProStatusService {
  ProStatusService(this._platform, {this.billingEnforced = kBillingEnforced});

  final PlatformService _platform;

  /// Whether the stored entitlement actually gates the answer. Tests pass
  /// true to exercise the billing-era matrix while the app still runs the
  /// launch window ([kBillingEnforced]).
  final bool billingEnforced;

  /// Reads the cached entitlement. Never throws: any storage error
  /// answers free, because a gate that crashes open is worse than a gate
  /// that fails closed.
  Future<bool> isPro() async {
    if (!billingEnforced) return true;
    try {
      return await _platform.secureRead(proEntitlementKey) ==
          proEntitlementValue;
    } catch (_) {
      return false;
    }
  }

  /// Persists a freshly granted entitlement (called only from verified
  /// Play callbacks in a later phase, or the dev override below).
  Future<void> grantPro() async {
    await _platform.secureWrite(proEntitlementKey, proEntitlementValue);
  }

  /// Clears the entitlement (lapse, refund, or user opt-out). After this
  /// [isPro] answers false — under billing enforcement — and every gate
  /// degrades to its free path.
  Future<void> revokePro() async {
    try {
      await _platform.secureDelete(proEntitlementKey);
    } catch (_) {
      // A delete failure must not leave a stale 'pro' behind: overwrite
      // with a non-Pro value so the next read answers free.
      await _platform.secureWrite(proEntitlementKey, '');
    }
  }
}

/// Riverpod access to the entitlement service.
final proStatusServiceProvider = Provider<ProStatusService>((ref) {
  return ProStatusService(ref.read(platformServiceProvider));
});

/// Reactive Pro flag for UI gates. Screens watch this; the service's
/// grant/revoke paths invalidate it so the UI updates without a restart.
final isProProvider = FutureProvider<bool>((ref) async {
  return ref.read(proStatusServiceProvider).isPro();
});
