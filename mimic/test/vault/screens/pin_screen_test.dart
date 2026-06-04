// test/vault/screens/pin_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';

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
  testWidgets('PinScreen Forgot PIN Behavior Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform);
    
    // Setup correct PIN in platform and initialize crypto
    await crypto.initialize('1234');
    crypto.lock();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: MaterialApp(
          initialRoute: '/vault-pin',
          routes: {
            '/vault-pin': (_) => const PinScreen(),
            '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial layout
    expect(find.text('Enter Vault PIN'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsNothing);

    // Fail 1
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid PIN'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsNothing);

    // Fail 2
    await tester.enterText(find.byType(TextField), '8888');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot PIN?'), findsNothing);

    // Fail 3
    await tester.enterText(find.byType(TextField), '7777');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    // Now Forgot PIN? should be visible
    expect(find.text('Forgot PIN?'), findsOneWidget);

    // Tap Forgot PIN? and verify navigation
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    expect(find.text('ENTER_RECOVERY_SCREEN'), findsOneWidget);
  });
}
