import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/widgets/vault_scaffold.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => store[key];
  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);
  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }
  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }
  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;
  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

void main() {
  testWidgets('ResetPinScreen UI Flow and Logic Test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    
    // Setup crypto and recovery blob inside runAsync
    await tester.runAsync(() async {
      await crypto.initialize('1234');
      final dummyPhrase = List.generate(12, (_) => 'abandon');
      await crypto.storeRecoveryBlob(dummyPhrase);
      await crypto.recoverWithPhrase(dummyPhrase);
    });

    final routes = <String, WidgetBuilder>{
      '/vault-home': (_) => const Scaffold(body: Text('HOME_SCREEN')),
    };

    Widget buildTestApp() {
      return ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: MaterialApp(
          initialRoute: '/reset-pin',
          routes: {
            '/reset-pin': (_) => const ResetPinScreen(),
            ...routes,
          },
        ),
      );
    }

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Verify initial layout and copy
    expect(find.text('Set New PIN'), findsOneWidget);
    expect(find.text('Create New PIN'), findsOneWidget);
    expect(find.text('Choose a new PIN, 4 to 8 digits'), findsOneWidget);

    final submitButtonFinder = find.byType(ElevatedButton);
    expect(submitButtonFinder, findsOneWidget);

    // Initial state: button disabled
    ElevatedButton submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNull);
    expect(find.text('Set PIN'), findsOneWidget);
    
    // Find PinDotIndicator
    final dotFinder = find.byType(PinDotIndicator);
    expect(dotFinder, findsOneWidget);
    PinDotIndicator indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));
    expect(indicator.totalDots, equals(8));

    // (iii) Tap 3 digits: 1, 2, 3 -> button remains disabled
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();

    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(3));
    submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNull, reason: '(iii) Entering 3 digits leaves the button disabled');

    // (i) Tap 4th digit: 4 -> button becomes enabled
    await tester.tap(find.text('4'));
    await tester.pump();

    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(4));
    submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNotNull, reason: '(i) Entering a 4-digit PIN enables the submit button');

    // (ii) Enter 4 more digits to reach 8 digits (1, 2, 3, 4, 5, 6, 7, 8)
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('6'));
    await tester.pump();
    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.tap(find.text('8'));
    await tester.pump();

    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(8));

    // Wait and verify it does NOT auto-submit; still on entry step
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Choose a new PIN, 4 to 8 digits'), findsOneWidget,
        reason: '(ii) Entering 8 digits does NOT submit on its own — screen remains on entry step until button is tapped');
    expect(find.text('Set PIN'), findsOneWidget);

    // Tap 'Set PIN' to advance to confirmation step
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    // Verify confirmation step
    expect(find.text('Re-enter your new PIN to confirm'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsOneWidget);
    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));

    // Enter mismatching PIN: 1, 2, 3, 4, 5, 6, 7, 9
    for (final d in ['1', '2', '3', '4', '5', '6', '7', '9']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.text('Confirm PIN'));
    await tester.pumpAndSettle();

    // Verify error and reset to Step 1
    expect(find.text('PINs do not match. Please try again.'), findsOneWidget);
    expect(find.text('Choose a new PIN, 4 to 8 digits'), findsOneWidget);
    expect(find.text('Set PIN'), findsOneWidget);

    // Enter a 4-digit PIN: 9, 8, 7, 6
    for (final d in ['9', '8', '7', '6']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Re-enter your new PIN to confirm'), findsOneWidget);

    // Confirm matching 4-digit PIN: 9, 8, 7, 6
    for (final d in ['9', '8', '7', '6']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
    await tester.runAsync(() async {
      await tester.tap(find.text('Confirm PIN'));
      for (int i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (fakePlatform.store['master_key_wrapped'] != null) break;
      }
    });
    await tester.pumpAndSettle();

    // Verify navigation to home screen
    expect(find.text('HOME_SCREEN'), findsOneWidget);
  });

  testWidgets('reset-PIN · 3 digits leaves the submit button disabled', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: const MaterialApp(
          home: ResetPinScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submitButtonFinder = find.byType(ElevatedButton);
    expect(submitButtonFinder, findsOneWidget);

    // Initial state: 0 digits -> disabled
    ElevatedButton submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNull);

    // Enter 3 digits: 1, 2, 3
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();

    final dotFinder = find.byType(PinDotIndicator);
    final indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(3));

    submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNull, reason: 'Entering 3 digits must leave the submit button disabled');
  });

  testWidgets('reset-PIN · 4 digits enables the submit button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: const MaterialApp(
          home: ResetPinScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submitButtonFinder = find.byType(ElevatedButton);

    // Enter 4 digits: 1, 2, 3, 4
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }

    final dotFinder = find.byType(PinDotIndicator);
    final indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(4));

    final submitBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(submitBtn.onPressed, isNotNull, reason: 'Entering 4 digits must enable the submit button');
  });

  testWidgets('reset-PIN · 8 digits does not submit until the button is tapped', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: const MaterialApp(
          home: ResetPinScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter 8 digits: 1, 2, 3, 4, 5, 6, 7, 8
    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8']) {
      await tester.tap(find.text(d));
      await tester.pump();
    }

    final dotFinder = find.byType(PinDotIndicator);
    final indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(8));

    // Wait and settle
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Assert positively that the screen is STILL on the first entry step after eight digits
    expect(find.text('Choose a new PIN, 4 to 8 digits'), findsOneWidget,
        reason: 'Entering 8 digits does NOT auto-submit: screen remains on first entry step');
    expect(find.text('Set PIN'), findsOneWidget);
    expect(find.text('Re-enter your new PIN to confirm'), findsNothing);
    expect(find.text('Confirm PIN'), findsNothing);

    // Tapping the button explicitly advances to step 2
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Re-enter your new PIN to confirm'), findsOneWidget);
    expect(find.text('Confirm PIN'), findsOneWidget);
    expect(find.text('Choose a new PIN, 4 to 8 digits'), findsNothing);
  });
}
