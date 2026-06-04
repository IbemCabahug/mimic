// test/vault/screens/enter_recovery_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/enter_recovery_screen.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/bip39_wordlist.dart';
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
  testWidgets('EnterRecoveryScreen UI Flow Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform);

    // Set up a valid recovery phrase in the vault crypto instance
    // 1. Initialize the vault first (unlock)
    await crypto.initialize('pin1234');
    
    // 2. Store the recovery phrase blob
    final correctPhrase = List.generate(12, (i) => kBip39Wordlist[i]); // abandon, ability, able, about, etc.
    await crypto.storeRecoveryBlob(correctPhrase);
    
    // 3. Lock the vault again to simulate being locked out
    crypto.lock();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: MaterialApp(
          home: const EnterRecoveryScreen(),
          routes: {
            '/vault-home': (context) => const Scaffold(body: Text('Vault Home Screen')),
          },
        ),
      ),
    );

    // Verify Title and Subtitle
    expect(find.text('Enter Recovery Phrase'), findsOneWidget);
    expect(find.text('Enter your 12 words in order'), findsOneWidget);

    // Verify 12 word textfields exist
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(12));

    // Initially, the "Recover Vault" button should be disabled because fields are empty.
    final recoverBtnFinder = find.text('Recover Vault');
    expect(recoverBtnFinder, findsOneWidget);
    
    // Try to tap the disabled button - should not trigger recovery
    await tester.ensureVisible(recoverBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(recoverBtnFinder);
    await tester.pumpAndSettle();
    
    // Fill in incorrect words
    for (int i = 0; i < 12; i++) {
      await tester.enterText(textFields.at(i), 'invalidword');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Now all fields are filled, the button should be enabled.
    // Tap with incorrect phrase
    await tester.ensureVisible(recoverBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(recoverBtnFinder);
    await tester.pumpAndSettle();

    // Verify "Incorrect recovery phrase" snackbar appears
    expect(find.text('Incorrect recovery phrase'), findsOneWidget);

    // Fill in correct words
    for (int i = 0; i < 12; i++) {
      await tester.enterText(textFields.at(i), correctPhrase[i]);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Tap with correct phrase
    await tester.ensureVisible(recoverBtnFinder);
    await tester.pumpAndSettle();
    await tester.tap(recoverBtnFinder);
    await tester.pumpAndSettle();

    // Verify we navigated to ResetPinScreen (which is the target page route pushed replacement)
    expect(find.byType(ResetPinScreen), findsOneWidget);
    expect(find.text('Create New PIN'), findsOneWidget);
  });
}
