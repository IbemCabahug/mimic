import 'package:mimic/vault/crypto/keystore_service.dart';
import 'dart:io';
// test/vault/screens/pin_screen_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/security/lockout_service.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
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
}

