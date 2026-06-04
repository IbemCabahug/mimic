// test/vault/screens/recovery_phrase_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
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
  testWidgets('RecoveryPhraseScreen UI Flow Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform);
    
    // Unlock the vault first since storeRecoveryBlob requires unlocked state
    await crypto.initialize('pin1234');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: const MaterialApp(
          home: RecoveryPhraseScreen(),
        ),
      ),
    );

    // --- STEP 1: Generate phrase ---
    expect(find.text('Backup Your Vault'), findsOneWidget);
    expect(find.text('Generate Recovery Phrase'), findsOneWidget);

    // Tap generate
    await tester.tap(find.text('Generate Recovery Phrase'));
    await tester.pumpAndSettle();

    // Verify 12 words are shown (their numbered indicators 1. to 12. should exist)
    expect(find.text('1. '), findsOneWidget);
    expect(find.text('12. '), findsOneWidget);
    expect(find.text("I've Written Them Down"), findsOneWidget);

    // Tap written down button to proceed to Step 2 (Confirm)
    final writtenDownBtn = find.text("I've Written Them Down");
    await tester.ensureVisible(writtenDownBtn);
    await tester.pumpAndSettle();
    await tester.tap(writtenDownBtn);
    await tester.pumpAndSettle();

    // --- STEP 2: Confirm phrase ---
    expect(find.text('Confirm Recovery Phrase'), findsOneWidget);
    expect(find.text('Confirm & Save'), findsOneWidget);

    // Find the 3 textfields
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(3));

    // Get the word numbers from the textfield labels
    // E.g. "Enter word #4"
    final List<int> requestedIndices = [];
    for (int i = 0; i < 3; i++) {
      final TextField textFieldWidget = tester.widget<TextField>(textFields.at(i));
      final labelText = textFieldWidget.decoration?.labelText ?? '';
      final match = RegExp(r'#(\d+)').firstMatch(labelText);
      if (match != null) {
        requestedIndices.add(int.parse(match.group(1)!) - 1);
      }
    }

    expect(requestedIndices.length, equals(3));

    // Try entering incorrect words first
    await tester.enterText(textFields.at(0), 'invalidword1');
    await tester.enterText(textFields.at(1), 'invalidword2');
    await tester.enterText(textFields.at(2), 'invalidword3');
    final confirmSaveBtn = find.text('Confirm & Save');
    await tester.ensureVisible(confirmSaveBtn);
    await tester.pumpAndSettle();
    await tester.tap(confirmSaveBtn);
    await tester.pumpAndSettle();

    // Verify error message is shown
    expect(find.text('Incorrect words. Please verify your recovery phrase.'), findsOneWidget);

    // Get the correct words
    final state = tester.state<RecoveryPhraseScreenState>(find.byType(RecoveryPhraseScreen));
    // Since we need to access _generatedWords, let's retrieve them
    final List<String> generatedWords = state.generatedWords;
    
    // Enter the correct words
    await tester.enterText(textFields.at(0), generatedWords[requestedIndices[0]]);
    await tester.enterText(textFields.at(1), generatedWords[requestedIndices[1]]);
    await tester.enterText(textFields.at(2), generatedWords[requestedIndices[2]]);
    
    await tester.ensureVisible(confirmSaveBtn);
    await tester.pumpAndSettle();
    await tester.tap(confirmSaveBtn);
    await tester.pumpAndSettle();

    // --- STEP 3: Saved successfully ---
    expect(find.text('Recovery Phrase Saved!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // Verify blob is stored in fake secure storage
    expect(fakePlatform.store.containsKey('recovery_blob'), isTrue);
    expect(fakePlatform.store.containsKey('recovery_salt'), isTrue);
  });
}
