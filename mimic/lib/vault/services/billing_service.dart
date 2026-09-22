// lib/vault/services/billing_service.dart
//
// Phase 2P Step 2: the wiring between Google Play Billing and the Phase 1
// entitlement cache (pro_status_service.dart). Play remains the authority
// that GRANTS Pro; this service listens to what Play says and translates it
// into grantPro()/revokePro() on the cached entitlement, so the answer
// survives restarts and works fully offline afterwards.
//
// Product shape, decided 2026-09-22: ONE one-time non-consumable purchase,
// `mimic_pro_lifetime`, PHP 99. No subscription — a non-consumable has no
// lapse, no grace period and no retry state, which makes the golden rule
// ("nothing protective is ever gated, payment never locks a user out of
// their own data") nearly free to honor: the only revocation path is an
// actual refund, handled below.
//
// Verification honesty (no server): mimic has no backend, so receipt
// validation is limited to what Play itself gives the app — the product ID
// must match and Play's local verification payload must be present. A
// rooted device can still write the cache directly; that risk is already
// accepted and documented in pro_status_service.dart, and the reason
// NOTHING protective is gated by Pro.
//
// Completion contract (from the plugin): a PurchaseDetails whose
// pendingCompletePurchase is true must be completed exactly once, and a
// pending purchase must NEVER be completed (the plugin throws). Completion
// happens on every terminal status — including error and our unknown-product
// path — so Play's queue never re-delivers stale purchases forever.
//
// This service never throws to the caller: a missing Play Store (sideloaded
// APK, emulator without GMS) is a NORMAL state, not a crash. Failures are
// recorded in [lastError] for diagnostics.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'pro_status_service.dart';

/// Google Play product ID for the one-time lifetime Pro entitlement.
/// Configured in Play Console; must exist before the closed test.
const String kProProductId = 'mimic_pro_lifetime';

/// The narrow slice of the in_app_purchase plugin this service needs,
/// abstracted so tests can drive the purchase stream, fake products and
/// completion without Google Play, a device or a network.
abstract interface class BillingStore {
  Future<bool> isAvailable();
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails purchase);
  Stream<List<PurchaseDetails>> get purchaseStream;
}

/// The real store: thin delegation to the plugin singleton.
class PlayBillingStore implements BillingStore {
  final InAppPurchase _plugin = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _plugin.purchaseStream;

  @override
  Future<bool> isAvailable() => _plugin.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _plugin.queryProductDetails(ids);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) =>
      _plugin.buyNonConsumable(purchaseParam: purchaseParam);

  @override
  Future<void> restorePurchases() => _plugin.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _plugin.completePurchase(purchase);
}

/// Translates Play purchase updates into entitlement grants and revocations.
class BillingService {
  BillingService({
    required ProStatusService proStatus,
    BillingStore? store,
  })  : _pro = proStatus,
        _store = store ?? PlayBillingStore();

  final ProStatusService _pro;
  final BillingStore _store;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _proProduct;
  final StreamController<void> _entitlementChanged =
      StreamController<void>.broadcast();

  /// Last non-fatal failure, for diagnostics and the paywall's
  /// "billing is unavailable" state. Never a filesystem path.
  String? lastError;

  /// True once [init] has subscribed to the purchase stream.
  bool get isListening => _subscription != null;

  /// The cached Play product for Pro (id, title, LOCAL-currency price), or
  /// null until [init] succeeds or if Play cannot find the product.
  ProductDetails? get proProductDetails => _proProduct;

  /// Fires after a grant or revocation actually changed the cached
  /// entitlement, so a future paywall/gate UI can re-read isPro without
  /// polling.
  Stream<void> get entitlementChanged => _entitlementChanged.stream;

  /// Subscribes to the purchase stream and caches the Pro product.
  /// Idempotent; safe to call from startup on any platform.
  Future<void> init() async {
    try {
      _subscription ??= _store.purchaseStream.listen(
        _onPurchaseUpdates,
        onError: (Object error) {
          lastError = 'purchase stream error: $error';
        },
      );
      final bool available = await _store.isAvailable();
      if (!available) {
        lastError = 'store unavailable';
        return;
      }
      final ProductDetailsResponse response =
          await _store.queryProductDetails(const {kProProductId});
      if (response.notFoundIDs.isNotEmpty) {
        lastError = 'product not found: ${response.notFoundIDs.join(', ')}';
      }
      _proProduct = response.productDetails.isEmpty
          ? null
          : response.productDetails.first;
    } catch (error) {
      lastError = 'billing init failed: $error';
    }
  }

  /// Launches the Play purchase flow for the lifetime Pro product.
  /// Returns false — without throwing — when the product is unknown
  /// (init failed) or Play refused to start the flow; the actual result
  /// arrives later on the purchase stream either way.
  Future<bool> buyPro() async {
    final ProductDetails? product = _proProduct;
    if (product == null) {
      lastError ??= 'buyPro before a known product';
      return false;
    }
    try {
      return await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (error) {
      lastError = 'buyPro failed: $error';
      return false;
    }
  }

  /// Ask Play to re-deliver owned purchases. Results arrive on the purchase
  /// stream as PurchaseStatus.restored events, handled by [_processOne].
  Future<void> restore() async {
    try {
      await _store.restorePurchases();
    } catch (error) {
      lastError = 'restore failed: $error';
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> updates) async {
    for (final PurchaseDetails purchase in updates) {
      await _processOne(purchase);
    }
  }

  /// THE single decision point for every Play update. Order matters:
  /// persist the entitlement BEFORE completing the purchase, so a crash
  /// between the two leaves the purchase un-completed (Play re-delivers it
  /// and we grant again) rather than completed-but-ungranted.
  Future<void> _processOne(PurchaseDetails purchase) async {
    if (purchase.productID != kProProductId) {
      // Not ours (config drift, another product): clear Play's queue,
      // touch nothing.
      await _completeIfPending(purchase);
      return;
    }
    switch (purchase.status) {
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (!_verify(purchase)) {
          lastError = 'purchase verification failed';
          await _completeIfPending(purchase);
          return;
        }
        try {
          await _pro.grantPro();
          _entitlementChanged.add(null);
        } catch (error) {
          // A failed grant must not skip completion: the purchase stays
          // owned by Play, so a later restore() re-delivers it and the
          // grant retries. Record, complete, move on.
          lastError = 'grant failed: $error';
        }
        await _completeIfPending(purchase);

      case PurchaseStatus.canceled:
        // Two meanings arrive here: the user backed out of a fresh purchase
        // (nothing was granted — revoking is a harmless no-op) and Play's
        // refund reconciliation, which is how a REFUNDED one-time purchase
        // is reported on later queries. Revoking on cancel is therefore the
        // correct refund handling for a lifetime product.
        try {
          await _pro.revokePro();
          _entitlementChanged.add(null);
        } catch (error) {
          lastError = 'revoke failed: $error';
        }
        await _completeIfPending(purchase);

      case PurchaseStatus.error:
        lastError = 'purchase error: ${purchase.error?.message ?? 'unknown'}';
        await _completeIfPending(purchase);

      case PurchaseStatus.pending:
        // A pending purchase is neither granted nor completed — the plugin
        // throws on completing one. The next update settles it.
        break;
    }
  }

  /// Verification without a server: the product ID already matched to get
  /// here; require Play's local verification payload to be present. See the
  /// honesty note in the file header.
  bool _verify(PurchaseDetails purchase) =>
      purchase.verificationData.localVerificationData.isNotEmpty;

  /// Completes the purchase exactly once, swallowing plugin failures so one
  /// bad completion can never stall the rest of the batch.
  Future<void> _completeIfPending(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _store.completePurchase(purchase);
    } catch (error) {
      lastError = 'completePurchase failed: $error';
    }
  }

  /// Stops listening. The cached entitlement survives (Phase 1 owns it).
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _entitlementChanged.close();
  }
}

/// Riverpod access to the billing service. Disposal cancels the purchase
/// stream subscription; the entitlement cache is independent of this.
final billingServiceProvider = Provider<BillingService>((ref) {
  final service = BillingService(
    proStatus: ref.read(proStatusServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
