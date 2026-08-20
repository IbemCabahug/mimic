import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
import 'package:mimic/vault/security/lockout_service.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/security/auto_lock.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};
  bool intruderStorageUntouched = true;
  @override
  bool isWeb() => false;
  @override
  Future<String?> secureRead(String key) async => store[key];
  @override
  Future<void> secureWrite(String key, String value) async {
    if (key.startsWith('intruder') || key.startsWith('break_in')) {
      intruderStorageUntouched = false;
    }
    store[key] = value;
  }
  @override
  Future<void> secureDelete(String key) async {
    if (key.startsWith('intruder') || key.startsWith('break_in')) {
      intruderStorageUntouched = false;
    }
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

class ThrowingFakeKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {}
  @override
  Future<String> wrap(String base64Data) async => throw Exception('Simulated wrap failure');
  @override
  Future<String> unwrap(String base64Data) async => throw Exception('Simulated unwrap failure');
  @override
  Future<void> deleteKey() async {}
}

class ConfigurableMigrationKeystoreService implements KeystoreService {
  bool failWrap = false;

  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async {
    if (failWrap) {
      throw KeystoreWrapException('Simulated migration wrap failure');
    }
    final original = base64Decode(base64Data);
    final iv = Uint8List(12);
    final combined = Uint8List(iv.length + original.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, original);
    return base64Encode(combined);
  }

  @override
  Future<String> unwrap(String base64Data) async {
    final combined = base64Decode(base64Data);
    if (combined.length < 12) return 'KEY_INVALID';
    final original = combined.sublist(12);
    return base64Encode(original);
  }

  @override
  Future<void> deleteKey() async {}
}

void main() {
  testWidgets('PinScreen Forgot PIN Behavior Test', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    
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
    expect(find.text('Enter PIN'), findsWidgets);
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
  testWidgets('PinScreen Lockout Flow and Re-enable', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final fakeClock = FakeMonotonicClock();
    DateTime fakeNow = DateTime.now();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    
    await crypto.initialize('1234');
    crypto.lock();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
          lockoutServiceProvider.overrideWith((ref) => LockoutService(fakePlatform, fakeClock, now: () => fakeNow)),
        ],
        child: MaterialApp(
          initialRoute: '/vault-pin',
          routes: {
            '/vault-pin': (_) => const PinScreen(),
            '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
            '/admin-panel': (_) => const Scaffold(body: Text('ADMIN_PANEL')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (int i = 0; i < 5; i++) {
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
    }

    expect(fakePlatform.store['wrong_attempts'], '5');
    expect(find.textContaining('Try again in '), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Try again in '), findsOneWidget); 

    fakeClock.value += 31000;
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1)); 
    await tester.pumpAndSettle();
    
    expect(find.textContaining('Try again in '), findsNothing);
    final textFieldEnabled = tester.widget<TextField>(find.byType(TextField));
    expect(textFieldEnabled.readOnly, isFalse);

    fakePlatform.store['intruder_photo_1'] = 'blob';
    fakePlatform.intruderStorageUntouched = true;
    fakePlatform.store['recovery_blob'] = 'dummy';

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('VAULT_HOME_SCREEN'), findsOneWidget);
    expect(fakePlatform.store['wrong_attempts'], isNull);
    expect(fakePlatform.store['lockout_set_wall'], isNull);
    expect(fakePlatform.intruderStorageUntouched, isTrue);
    expect(fakePlatform.store['intruder_photo_1'], 'blob');
    
    AutoLock().dispose();
  });

  testWidgets('PinScreen Duress PIN resets lockout', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    final fakeClock = FakeMonotonicClock();
    final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
    
    await crypto.initialize('1234');
    crypto.lock();
    
    final duressService = DuressService(fakePlatform);
    // Real duress setup writes hash/salt to storage correctly
    await duressService.setFakePin('9999');
    
    fakePlatform.store['wrong_attempts'] = '3';
    fakePlatform.store['lockout_set_wall'] = '123';
    fakePlatform.store['intruder_photo_1'] = 'blob';
    fakePlatform.intruderStorageUntouched = true;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
          lockoutServiceProvider.overrideWith((ref) => LockoutService(fakePlatform, fakeClock)),
          duressServiceProvider.overrideWith((ref) => duressService),
        ],
        child: MaterialApp(
          initialRoute: '/vault-pin',
          routes: {
            '/vault-pin': (_) => const PinScreen(),
            '/admin-panel': (_) => const Scaffold(body: Text('ADMIN_PANEL')),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('ADMIN_PANEL'), findsOneWidget);
    expect(fakePlatform.store['wrong_attempts'], isNull); 
    expect(fakePlatform.store['lockout_set_wall'], isNull);
    expect(fakePlatform.intruderStorageUntouched, isTrue); 
  });

  testWidgets('PinScreen Create Mode initialize throw does not write lockout keys', (WidgetTester tester) async {
    final fakePlatform = FakePlatformService();
    // Use a throwing keystore so initialize() fails
    final crypto = VaultCrypto(fakePlatform, ThrowingFakeKeystoreService());

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
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Create Mode
    expect(find.text('Create PIN'), findsWidgets);

    // Enter PIN once
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Confirm PIN'), findsWidgets);

    // Enter PIN again (confirm)
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Verify error is creation-specific, NOT "Invalid PIN"
    expect(find.text('Couldn\'t create vault, please try again'), findsOneWidget);

    // Verify it did not write lockout keys or wrong_attempts
    expect(fakePlatform.store['wrong_attempts'], isNull);
    expect(fakePlatform.store['lockout_set_wall'], isNull);

    // Verify it reset state to Create PIN again
    expect(find.text('Create PIN'), findsWidgets);
  });

  group('Migration failure and recovery phrase preservation (F1/T1-T4)', () {
    testWidgets('T1: Migration failure navigates to vault-home and NOT RecoveryPhraseScreen', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final keystore = ConfigurableMigrationKeystoreService()..failWrap = false;
      final crypto = VaultCrypto(fakePlatform, keystore);

      await crypto.initialize('1234');
      final dummyPhrase = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await crypto.storeRecoveryBlob(dummyPhrase);
      fakePlatform.store.remove('master_key_wrapped');
      crypto.lock();

      // Now set wrap to fail during migration attempt
      keystore.failWrap = true;

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
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
              '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('VAULT_HOME_SCREEN'), findsOneWidget);
      expect(find.byType(RecoveryPhraseScreen), findsNothing);
      AutoLock().dispose();
    });

    testWidgets('T2: Migration failure displays plain-language upgrade failure message', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final keystore = ConfigurableMigrationKeystoreService()..failWrap = false;
      final crypto = VaultCrypto(fakePlatform, keystore);

      await crypto.initialize('1234');
      final dummyPhrase = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await crypto.storeRecoveryBlob(dummyPhrase);
      fakePlatform.store.remove('master_key_wrapped');
      crypto.lock();

      keystore.failWrap = true;

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
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
              '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't upgrade your vault's hardware protection right now. Your vault and your files are safe, and we'll try again next time you unlock.",
        ),
        findsOneWidget,
      );
      AutoLock().dispose();
    });

    testWidgets('T3: Migration failure leaves stored recovery_blob and recovery_salt byte-identical', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final keystore = ConfigurableMigrationKeystoreService()..failWrap = false;
      final crypto = VaultCrypto(fakePlatform, keystore);

      await crypto.initialize('1234');
      final dummyPhrase = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await crypto.storeRecoveryBlob(dummyPhrase);
      final initialBlob = fakePlatform.store['recovery_blob'];
      final initialSalt = fakePlatform.store['recovery_salt'];
      expect(initialBlob, isNotNull);
      expect(initialSalt, isNotNull);

      fakePlatform.store.remove('master_key_wrapped');
      crypto.lock();

      keystore.failWrap = true;

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
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
              '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(fakePlatform.store['recovery_blob'], equals(initialBlob));
      expect(fakePlatform.store['recovery_salt'], equals(initialSalt));
      AutoLock().dispose();
    });

    testWidgets('T4: Successful migration navigates to vault-home and migrates master key', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final keystore = ConfigurableMigrationKeystoreService()..failWrap = false;
      final crypto = VaultCrypto(fakePlatform, keystore);

      await crypto.initialize('1234');
      final dummyPhrase = [
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'abandon',
        'abandon', 'abandon', 'abandon', 'about'
      ];
      await crypto.storeRecoveryBlob(dummyPhrase);
      fakePlatform.store.remove('master_key_wrapped');
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
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME_SCREEN')),
              '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY_SCREEN')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(find.text('VAULT_HOME_SCREEN'), findsOneWidget);
      expect(find.byType(RecoveryPhraseScreen), findsNothing);
      expect(fakePlatform.store['master_key_wrapped']?.startsWith('hw1:'), isTrue);
      AutoLock().dispose();
    });
  });
}
