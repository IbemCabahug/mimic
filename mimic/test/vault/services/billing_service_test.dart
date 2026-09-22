// test/vault/services/billing_service_test.dart
//
// Phase 2P Step 2 tests. The BillingStore seam keeps Google Play, a device
// and a network out of the loop entirely: the purchase stream is a plain
// broadcast controller the tests drive by hand, and the entitlement side is
// the same in-memory FakePlatformService the Phase 1 tests use.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimic/vault/services/billing_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';

import 'pro_status_service_test.dart' show FakePlatformService;

/// Controllable stand-in for the in_app_purchase plugin.
class FakeBillingStore implements BillingStore {
  FakeBillingStore({ProductDetailsResponse? response})
      : queryResponse = response ??
            ProductDetailsResponse(productDetails: [proProductFixture], notFoundIDs: const []);

  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();

  ProductDetailsResponse queryResponse;
  bool available = true;
  bool queryShouldThrow = false;
  bool buyShouldThrow = false;
  bool buyAnswer = true;
  bool completeShouldThrow = false;
  PurchaseParam? lastBuyParam;
  bool restoreCalled = false;
  final List<PurchaseDetails> completed = [];

  void emit(List<PurchaseDetails> batch) => controller.add(batch);

  void emitError(Object error) => controller.addError(error);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    if (queryShouldThrow) throw const SocketException('query failed');
    return queryResponse;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    if (buyShouldThrow) throw const SocketException('buy failed');
    lastBuyParam = purchaseParam;
    return buyAnswer;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalled = true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (completeShouldThrow) throw const SocketException('complete failed');
    completed.add(purchase);
  }
}

final ProductDetails proProductFixture = ProductDetails(
  id: kProProductId,
  title: 'Mimic Pro',
  description: 'Lifetime unlock',
  price: '₱99.00',
  rawPrice: 99.0,
  currencyCode: 'PHP',
);

PurchaseDetails _purchase(
  PurchaseStatus status, {
  String productId = kProProductId,
  String localVerification = 'signed-payload',
  bool pending = true,
}) {
  final details = PurchaseDetails(
    purchaseID: 'tx-1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: localVerification,
      serverVerificationData: 'server-payload',
      source: 'google_play',
    ),
    transactionDate: '0',
    status: status,
  );
  details.pendingCompletePurchase = pending;
  return details;
}

BillingService _service(FakeBillingStore store, FakePlatformService platform) {
  return BillingService(
    proStatus: ProStatusService(platform, billingEnforced: true),
    store: store,
  );
}

void main() {
  test('init subscribes to the stream and caches the Pro product', () async {
    final store = FakeBillingStore();
    final service = _service(store, FakePlatformService());

    await service.init();

    expect(service.isListening, isTrue);
    expect(service.proProductDetails?.id, kProProductId);
    expect(service.proProductDetails?.price, '₱99.00');
    expect(service.lastError, isNull);
  });

  test('init records a missing product instead of crashing the paywall',
      () async {
    final store = FakeBillingStore(
      response: ProductDetailsResponse(
          productDetails: [], notFoundIDs: const [kProProductId]),
    );
    final service = _service(store, FakePlatformService());

    await service.init();

    expect(service.proProductDetails, isNull);
    expect(service.lastError, contains('not found'));
  });

  test('init treats a missing Play Store as a normal state', () async {
    final store = FakeBillingStore()..available = false;
    final service = _service(store, FakePlatformService());

    await service.init();

    expect(service.isListening, isTrue, reason: 'the stream still listens');
    expect(service.proProductDetails, isNull);
    expect(service.lastError, contains('unavailable'));
  });

  test('init swallows store exceptions and records them', () async {
    final store = FakeBillingStore()..queryShouldThrow = true;
    final service = _service(store, FakePlatformService());

    await service.init();

    expect(service.isListening, isTrue);
    expect(service.proProductDetails, isNull);
    expect(service.lastError, isNotNull);
  });

  group('purchase stream decisions', () {
    test('a purchased event grants Pro and completes the purchase', () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], proEntitlementValue);
      expect(store.completed.single.productID, kProProductId);
      expect(store.completed.single.status, PurchaseStatus.purchased);
    });

    test('a restored event grants Pro (the reinstall recovery path)',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      await service.restore();
      store.emit([_purchase(PurchaseStatus.restored)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], proEntitlementValue);
      expect(store.restoreCalled, isTrue);
      expect(store.completed.single.productID, kProProductId);
    });

    test('a pending event neither grants nor completes', () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([_purchase(PurchaseStatus.pending)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], isNull);
      expect(store.completed, isEmpty);
    });

    test('a canceled event revokes an existing grant (refund reconciliation)',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();
      await platform.secureWrite(proEntitlementKey, proEntitlementValue);

      store.emit([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], isNull);
      expect(store.completed, hasLength(1));
    });

    test('a canceled event with nothing granted is a harmless no-op',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([_purchase(PurchaseStatus.canceled)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], isNull);
      expect(store.completed, hasLength(1));
      expect(service.lastError, isNull);
    });

    test('an error event never grants but always completes', () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([_purchase(PurchaseStatus.error)]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], isNull);
      expect(store.completed, hasLength(1));
      expect(service.lastError, contains('purchase error'));
    });

    test('a foreign product is completed but never grants or revokes',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();
      await platform.secureWrite(proEntitlementKey, proEntitlementValue);

      store.emit(
          [_purchase(PurchaseStatus.purchased, productId: 'other.sku')]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], proEntitlementValue,
          reason: 'a foreign product must not revoke either');
      expect(store.completed, hasLength(1));
    });

    test('an unverifiable purchase is completed but never granted', () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([_purchase(PurchaseStatus.purchased, localVerification: '')]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], isNull);
      expect(store.completed, hasLength(1));
      expect(service.lastError, contains('verification'));
    });

    test('a grant storage failure still completes; a later restore retries',
        () async {
      final failing = _FailingWritePlatform();
      final store = FakeBillingStore();
      final service = _service(store, failing);
      await service.init();

      store.emit([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(failing.store[proEntitlementKey], isNull);
      expect(store.completed, hasLength(1),
          reason: 'the purchase must still be completed so Play does not '
              're-prompt forever');
      expect(service.lastError, contains('grant failed'));

      // Recovery: same store, healthy platform, restored re-delivery.
      final healthy = FakePlatformService();
      final recovery = _service(store, healthy);
      await recovery.init();
      store.emit([_purchase(PurchaseStatus.restored, pending: false)]);
      await pumpEventQueue();
      expect(healthy.store[proEntitlementKey], proEntitlementValue);
    });

    test('re-delivered purchases grant idempotently and complete each time',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emit([
        _purchase(PurchaseStatus.purchased),
        _purchase(PurchaseStatus.purchased),
      ]);
      await pumpEventQueue();

      expect(platform.store[proEntitlementKey], proEntitlementValue);
      expect(store.completed, hasLength(2));
    });

    test('a stream error is recorded without killing the subscription',
        () async {
      final platform = FakePlatformService();
      final store = FakeBillingStore();
      final service = _service(store, platform);
      await service.init();

      store.emitError(Exception('play hiccup'));
      await pumpEventQueue();
      store.emit([_purchase(PurchaseStatus.purchased)]);
      await pumpEventQueue();

      expect(service.lastError, contains('stream error'));
      expect(platform.store[proEntitlementKey], proEntitlementValue,
          reason: 'the subscription must survive a stream error');
    });
  });

  group('buy and restore behavior', () {
    test('buyPro passes the cached product and returns the flow answer',
        () async {
      final store = FakeBillingStore();
      final service = _service(store, FakePlatformService());
      await service.init();

      final ok = await service.buyPro();

      expect(ok, isTrue);
      expect(store.lastBuyParam?.productDetails.id, kProProductId);
      expect(store.lastBuyParam?.productDetails.price, '₱99.00');
    });

    test('buyPro before init is a false answer, not a crash', () async {
      final store = FakeBillingStore();
      final service = _service(store, FakePlatformService());

      final ok = await service.buyPro();

      expect(ok, isFalse);
      expect(service.lastError, contains('before a known product'));
      expect(store.lastBuyParam, isNull);
    });

    test('buyPro with a refused flow start answers false with the reason',
        () async {
      final store = FakeBillingStore()..buyAnswer = false;
      final service = _service(store, FakePlatformService());
      await service.init();

      expect(await service.buyPro(), isFalse);
    });

    test('buyPro with a throwing store answers false and records it',
        () async {
      final store = FakeBillingStore()..buyShouldThrow = true;
      final service = _service(store, FakePlatformService());
      await service.init();

      expect(await service.buyPro(), isFalse);
      expect(service.lastError, contains('buyPro failed'));
    });

    test('restore forwards to Play even without a cached product', () async {
      final store = FakeBillingStore()..available = false;
      final service = _service(store, FakePlatformService());
      await service.init();

      await service.restore();

      expect(store.restoreCalled, isTrue);
    });
  });

  test('dispose stops listening', () async {
    final store = FakeBillingStore();
    final service = _service(store, FakePlatformService());
    await service.init();
    expect(service.isListening, isTrue);

    service.dispose();

    expect(service.isListening, isFalse);
  });
}

class _FailingWritePlatform extends FakePlatformService {
  @override
  Future<void> secureWrite(String key, String value) async =>
      throw const SocketException('storage full');
}
