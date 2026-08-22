import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:io';
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

class SpyVaultCrypto extends VaultCrypto {
  int storeRecoveryBlobCalls = 0;
  int migrateCalls = 0;

  SpyVaultCrypto(PlatformService platformService, KeystoreService keystoreService) 
      : super(platformService, keystoreService);

  @override
  Future<void> storeRecoveryBlob([List<String>? recoveryWords]) async {
    storeRecoveryBlobCalls++;
    await Future.delayed(const Duration(milliseconds: 50));
    await super.storeRecoveryBlob(recoveryWords);
  }

  @override
  Future<void> migrateToHardwareBinding() async {
    migrateCalls++;
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('RecoveryPhraseScreen UI Flow Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    
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

    expect(find.text('Backup Your Vault'), findsOneWidget);
    expect(find.text('Generate Recovery Phrase'), findsOneWidget);

    await tester.tap(find.text('Generate Recovery Phrase'));
    await tester.pumpAndSettle();

    expect(find.text('1. '), findsOneWidget);
    expect(find.text('12. '), findsOneWidget);
    expect(find.text("I've Written Them Down"), findsOneWidget);

    final writtenDownBtn = find.text("I've Written Them Down");
    await tester.ensureVisible(writtenDownBtn);
    await tester.pumpAndSettle();
    await tester.tap(writtenDownBtn);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Recovery Phrase'), findsOneWidget);
    expect(find.text('Confirm & Save'), findsOneWidget);

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(3));

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

    await tester.enterText(textFields.at(0), 'invalidword1');
    await tester.enterText(textFields.at(1), 'invalidword2');
    await tester.enterText(textFields.at(2), 'invalidword3');
    final confirmSaveBtn = find.text('Confirm & Save');
    await tester.ensureVisible(confirmSaveBtn);
    await tester.pumpAndSettle();
    await tester.tap(confirmSaveBtn);
    await tester.pumpAndSettle();

    expect(find.text('Incorrect words. Please verify your recovery phrase.'), findsOneWidget);

    final state = tester.state<RecoveryPhraseScreenState>(find.byType(RecoveryPhraseScreen));
    final List<String> generatedWords = state.generatedWords;
    
    await tester.enterText(textFields.at(0), generatedWords[requestedIndices[0]]);
    await tester.enterText(textFields.at(1), generatedWords[requestedIndices[1]]);
    await tester.enterText(textFields.at(2), generatedWords[requestedIndices[2]]);
    
    await tester.ensureVisible(confirmSaveBtn);
    await tester.pumpAndSettle();
    await tester.tap(confirmSaveBtn);
    await tester.pumpAndSettle();

    expect(find.text('Recovery Phrase Saved!'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    expect(fakePlatform.store.containsKey('recovery_blob'), isTrue);
    expect(fakePlatform.store.containsKey('recovery_salt'), isTrue);
  });

  testWidgets('Rapid double-tap Confirm & Save calls storeRecoveryBlob exactly once', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = SpyVaultCrypto(fakePlatform, FakeKeystoreService());
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

    await tester.tap(find.text('Generate Recovery Phrase'));
    await tester.pumpAndSettle();
    
    await tester.ensureVisible(find.text("I've Written Them Down"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I've Written Them Down"));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    final List<int> requestedIndices = [];
    for (int i = 0; i < 3; i++) {
      final TextField tf = tester.widget<TextField>(textFields.at(i));
      final match = RegExp(r'#(\d+)').firstMatch(tf.decoration?.labelText ?? '');
      if (match != null) {
        requestedIndices.add(int.parse(match.group(1)!) - 1);
      }
    }
    final state = tester.state<RecoveryPhraseScreenState>(find.byType(RecoveryPhraseScreen));
    final generatedWords = state.generatedWords;
    
    await tester.enterText(textFields.at(0), generatedWords[requestedIndices[0]]);
    await tester.enterText(textFields.at(1), generatedWords[requestedIndices[1]]);
    await tester.enterText(textFields.at(2), generatedWords[requestedIndices[2]]);

    final confirmBtn = find.text('Confirm & Save');
    await tester.ensureVisible(confirmBtn);
    await tester.pumpAndSettle();

    for (int i = 0; i < 5; i++) {
      await tester.tap(confirmBtn);
    }
    
    await tester.pumpAndSettle();

    expect(crypto.storeRecoveryBlobCalls, equals(1));
    expect(find.text('Recovery Phrase Saved!'), findsOneWidget);
  });

  testWidgets('Rapid double-tap Done with forcedSetup+migrateAfter calls migrateToHardwareBinding exactly once', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = SpyVaultCrypto(fakePlatform, FakeKeystoreService());
    await crypto.initialize('pin1234');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
        ],
        child: MaterialApp(
          home: const RecoveryPhraseScreen(forcedSetup: true, migrateAfter: true),
          routes: {
            '/vault-home': (context) => const SizedBox(),
          },
        ),
      ),
    );

    final state = tester.state<RecoveryPhraseScreenState>(find.byType(RecoveryPhraseScreen));
    await tester.tap(find.text('Generate Recovery Phrase'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("I've Written Them Down"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I've Written Them Down"));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    final List<int> requestedIndices = [];
    for (int i = 0; i < 3; i++) {
      final TextField tf = tester.widget<TextField>(textFields.at(i));
      final match = RegExp(r'#(\d+)').firstMatch(tf.decoration?.labelText ?? '');
      if (match != null) {
        requestedIndices.add(int.parse(match.group(1)!) - 1);
      }
    }
    final generatedWords = state.generatedWords;
    
    await tester.enterText(textFields.at(0), generatedWords[requestedIndices[0]]);
    await tester.enterText(textFields.at(1), generatedWords[requestedIndices[1]]);
    await tester.enterText(textFields.at(2), generatedWords[requestedIndices[2]]);

    await tester.ensureVisible(find.text('Confirm & Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & Save'));
    await tester.pumpAndSettle();

    final doneBtn = find.text('Done');
    expect(doneBtn, findsOneWidget);

    for (int i = 0; i < 5; i++) {
      await tester.tap(doneBtn);
    }
    
    await tester.pumpAndSettle();

    expect(crypto.migrateCalls, equals(1));
  });
}
