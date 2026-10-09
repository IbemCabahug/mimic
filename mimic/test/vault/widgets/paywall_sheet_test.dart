// test/vault/widgets/paywall_sheet_test.dart
//
// Widget and concurrency tests for PaywallSheet.
// Verifies:
// 1. Value proposition rendering, Golden Rule guarantee, and Indie gratitude pledge.
// 2. Strict multi-tap debouncing on purchase and restore actions.
// 3. Offline / missing product handling with retry action.
// 4. Celebration and heartfelt gratitude view when Pro is unlocked.
// 5. Dismissal via close button.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/services/billing_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/widgets/paywall_sheet.dart';

import '../services/billing_service_test.dart' show FakeBillingStore;
import '../services/pro_status_service_test.dart' show FakePlatformService;

class AsyncFakeBillingStore extends FakeBillingStore {
  Completer<bool>? pendingBuy;
  int buyAttempts = 0;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyAttempts++;
    lastBuyParam = purchaseParam;
    if (pendingBuy != null) {
      return pendingBuy!.future;
    }
    return buyAnswer;
  }
}

Widget _wrap(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  testWidgets('renders Pro title, benefits, guarantee, gratitude pledge, and price',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    final fakeStore = AsyncFakeBillingStore();
    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(_wrap(const PaywallSheet(), container));
    await tester.pumpAndSettle();

    // Title and subtitle
    expect(find.text('MIMIC PRO'), findsOneWidget);
    expect(find.text('Lifetime Upgrade'), findsOneWidget);

    // Feature benefits
    expect(find.text('Quick-Entry Shortcut'), findsOneWidget);
    expect(find.text('Extended Auto-Lock Timeouts'), findsOneWidget);
    expect(find.text('100% Offline Independence'), findsOneWidget);

    // Golden Rule guarantee callout
    expect(
      find.textContaining('Core security, AES-256 encryption, decoy PINs'),
      findsOneWidget,
    );

    // Heartfelt indie gratitude pledge
    expect(find.text('Support Independent Development'), findsOneWidget);
    expect(
      find.textContaining('Mimic is built without investors, ads, or tracking.'),
      findsOneWidget,
    );

    // Primary button with localized price
    expect(find.text('Unlock Lifetime Pro • ₱99.00'), findsOneWidget);

    // Restore button
    expect(find.text('Already purchased? Restore Purchases'), findsOneWidget);
  });

  testWidgets('tapping buy debounces and prevents duplicate calls',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    final fakeStore = AsyncFakeBillingStore();
    final completer = Completer<bool>();
    fakeStore.pendingBuy = completer;

    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(_wrap(const PaywallSheet(), container));
    await tester.pumpAndSettle();

    final buyButton = find.text('Unlock Lifetime Pro • ₱99.00');
    expect(buyButton, findsOneWidget);

    await tester.ensureVisible(buyButton);
    await tester.tap(buyButton);
    await tester.pump();

    // Verify loading spinner is shown while in-flight
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(fakeStore.buyAttempts, 1);

    // Secondary rapid tap while loading must be ignored (debounce guard)
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.pump();
    expect(fakeStore.buyAttempts, 1, reason: 'Debounce guard prevented second buy call');

    // Settle in-flight purchase
    completer.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('shows offline retry notice when product is unavailable',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    final fakeStore = AsyncFakeBillingStore();
    fakeStore.queryResponse = ProductDetailsResponse(
      productDetails: [],
      notFoundIDs: const [kProProductId],
    );

    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(_wrap(const PaywallSheet(), container));
    await tester.pumpAndSettle();

    expect(
      find.text('Connect to internet once to load Google Play pricing.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('renders celebration and heartfelt appreciation when user is already Pro',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    // Simulate user already having Pro in secure storage
    fakePlatform.store[proEntitlementKey] = proEntitlementValue;

    final fakeStore = AsyncFakeBillingStore();
    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(_wrap(const PaywallSheet(), container));
    await tester.pumpAndSettle();

    expect(find.text('Supporter Active'), findsOneWidget);
    expect(find.text('Thank You For Your Support! 🎉'), findsOneWidget);
    expect(
      find.textContaining('You are an official Mimic Pro backer.'),
      findsOneWidget,
    );
    expect(find.text('Enjoy Mimic Pro'), findsOneWidget);

    // Purchase button should NOT be present when already Pro
    expect(find.textContaining('Unlock Lifetime Pro'), findsNothing);
  });

  testWidgets('restore purchases triggers billing restore and gives user feedback',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    final fakeStore = AsyncFakeBillingStore();
    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(_wrap(const PaywallSheet(), container));
    await tester.pumpAndSettle();

    final restoreBtn = find.text('Already purchased? Restore Purchases');
    expect(restoreBtn, findsOneWidget);

    await tester.ensureVisible(restoreBtn);
    await tester.tap(restoreBtn);
    await tester.pump();

    // Pump past the debounce and settling delay
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(fakeStore.restoreCalled, isTrue);
    expect(
      find.text('No active Pro purchase found on this Google account.'),
      findsOneWidget,
    );
  });

  testWidgets('close button pops the bottom sheet',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fakePlatform = FakePlatformService();
    final fakeStore = AsyncFakeBillingStore();
    final proService = ProStatusService(
      fakePlatform,
      billingEnforced: true,
      flavor: AppDistributionFlavor.playStore,
    );
    final billingService = BillingService(
      proStatus: proService,
      store: fakeStore,
    );
    await billingService.init();

    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        proStatusServiceProvider.overrideWithValue(proService),
        billingServiceProvider.overrideWithValue(billingService),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPaywallSheet(context),
                child: const Text('Open Paywall'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open Paywall'));
    await tester.pumpAndSettle();
    expect(find.text('MIMIC PRO'), findsOneWidget);

    // Tap close button
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('MIMIC PRO'), findsNothing);
  });
}
