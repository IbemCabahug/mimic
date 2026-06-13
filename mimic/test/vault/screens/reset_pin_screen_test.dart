// test/vault/screens/reset_pin_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/widgets/vault_scaffold.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => store[key];
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
}

void main() {
  testWidgets('ResetPinScreen UI Flow and Logic Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform);
    
    // Lock/Unlock doesn't matter for changePin but let's initialize to set singleton
    await crypto.initialize('1234');

    // Store a recovery blob first so we have one to recover
    final dummyPhrase = List.generate(12, (_) => 'abandon');
    await crypto.storeRecoveryBlob(dummyPhrase);

    // Setup dummy recovery words in cache by recovering
    await crypto.recoverWithPhrase(dummyPhrase);

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

    // Verify initial layout
    expect(find.text('Set New PIN'), findsOneWidget);
    expect(find.text('Create New PIN'), findsOneWidget);
    expect(find.text('Choose a new 8-digit PIN for your vault'), findsOneWidget);
    
    // Find PinDotIndicator
    final dotFinder = find.byType(PinDotIndicator);
    expect(dotFinder, findsOneWidget);
    PinDotIndicator indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));
    expect(indicator.totalDots, equals(8));

    // Tap digits: 1, 2, 3
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();

    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(3));

    // Tap Backspace
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(2));

    // Tap Clear All
    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pump();
    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));

    // Input first PIN: 1, 1, 1, 1, 1, 1, 1, 1
    for (int i = 0; i < 8; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    // Wait for validation transition delay (200ms)
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Verify confirmation instruction screen shows up
    expect(find.text('Re-enter your new PIN to confirm'), findsOneWidget);
    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));

    // Enter incorrect PIN to confirm: 1, 1, 1, 1, 1, 1, 1, 2
    for (int i = 0; i < 7; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Verify error and reset to Step 1
    expect(find.text('PINs do not match. Please try again.'), findsOneWidget);
    expect(find.text('Choose a new 8-digit PIN for your vault'), findsOneWidget);
    indicator = tester.widget<PinDotIndicator>(dotFinder);
    expect(indicator.filledCount, equals(0));

    // Enter first PIN again: 2, 2, 2, 2, 2, 2, 2, 2
    for (int i = 0; i < 8; i++) {
      await tester.tap(find.text('2'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Confirm with correct PIN: 2, 2, 2, 2, 2, 2, 2, 2
    for (int i = 0; i < 8; i++) {
      await tester.tap(find.text('2'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // Verify navigation to home screen
    expect(find.text('HOME_SCREEN'), findsOneWidget);
    
    // Verify changes in storage
    expect(fakePlatform.store['vault_pin'], equals('22222222'));
    expect(fakePlatform.store['wrong_attempts'], equals('0'));
    expect(fakePlatform.store['recovery_blob'], isNotNull);
  });
}
