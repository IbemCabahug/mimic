// mimic/test/vault/security/phase_b_security_remediations_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/core/providers/biometric_providers.dart';
import 'package:mimic/core/services/biometric_service.dart';
import 'package:mimic/core/services/biometric_unlock_store.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/screens/set_duress_pin_screen.dart';
import 'package:mimic/vault/screens/vault_settings_screen.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/vault/security/lockout_service.dart';

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

class FakeBiometricUnlockStore implements BiometricUnlockStore {
  int clearBioSecretCount = 0;
  bool bioSecretEnabled = false;

  @override
  Future<void> clearBioSecret() async {
    clearBioSecretCount++;
    bioSecretEnabled = false;
  }

  @override
  Future<void> disable(BiometricLayer layer) async {
    bioSecretEnabled = false;
  }

  @override
  Future<void> enable(BiometricLayer layer, String secret) async {
    bioSecretEnabled = true;
  }

  @override
  Future<bool> hasBioSecret() async => bioSecretEnabled;

  @override
  Future<bool> isEnabled(BiometricLayer layer) async => bioSecretEnabled;

  @override
  Future<String?> readBioSecret() async => bioSecretEnabled ? 'secret' : null;

  @override
  Future<String?> readSecret(BiometricLayer layer) async => bioSecretEnabled ? 'secret' : null;

  @override
  Future<void> wipeAll() async {
    clearBioSecretCount++;
    bioSecretEnabled = false;
  }

  @override
  Future<void> writeBioSecret(String secret) async {
    bioSecretEnabled = true;
  }

  @override
  Future<BiometricLayer?> activeLayer() async => bioSecretEnabled ? BiometricLayer.vault : null;
}

class FakeBiometricService implements BiometricService {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<BiometricResult> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async => BiometricResult.success;
}

class FakeFastDuressService extends DuressService {
  final String fakePin;
  FakeFastDuressService(super.platform, this.fakePin);

  @override
  Future<bool> isFakePin(String pin) async => pin == fakePin;

  @override
  Future<bool> isFakePinEnabled() async => true;
}

class FakeFastVaultCrypto extends Fake with ChangeNotifier implements VaultCrypto {
  bool unlocked = true;
  String currentPin = '1234';

  @override
  bool get isUnlocked => unlocked;

  Future<bool> isVaultSetup() async => true;

  @override
  Future<void> initialize(String pin) async {
    if (pin != currentPin) {
      throw const InvalidPinException();
    }
    unlocked = true;
  }

  @override
  Future<bool> verifyPin(String pin) async => pin == currentPin;

  @override
  Future<void> changePin(String newPin) async {
    currentPin = newPin;
  }

  @override
  void lock() {
    unlocked = false;
  }

  @override
  bool get hasRecoveryPhrase => true;

  @override
  bool get needsHardwareMigration => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> secureStorageData = {};

  setUp(() {
    secureStorageData.clear();
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'write') {
          final key = methodCall.arguments['key'] as String;
          final value = methodCall.arguments['value'] as String?;
          if (value != null) {
            secureStorageData[key] = value;
          } else {
            secureStorageData.remove(key);
          }
          return null;
        }
        if (methodCall.method == 'read') {
          final key = methodCall.arguments['key'] as String;
          return secureStorageData[key];
        }
        if (methodCall.method == 'delete') {
          final key = methodCall.arguments['key'] as String;
          secureStorageData.remove(key);
          return null;
        }
        if (methodCall.method == 'readAll') {
          return secureStorageData;
        }
        return null;
      },
    );
  });

  group('AUDIT-04: Biometric Credential Invalidation on PIN Change/Reset', () {
    test('VaultCrypto.changePin explicitly clears biometric secret', () async {
      final fakePlatform = FakePlatformService();
      final fakeBioStore = FakeBiometricUnlockStore();
      fakeBioStore.bioSecretEnabled = true;

      final crypto = VaultCrypto(
        fakePlatform,
        FakeKeystoreService(),
        fakeBioStore,
      );

      await crypto.initialize('1234');
      expect(fakeBioStore.clearBioSecretCount, equals(0));

      await crypto.changePin('5678');
      expect(fakeBioStore.clearBioSecretCount, greaterThanOrEqualTo(1));
      expect(fakeBioStore.bioSecretEnabled, isFalse);
    });

    testWidgets('ResetPinScreen clears biometric secret on PIN reset', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePlatform = FakePlatformService();
      final fakeBioStore = FakeBiometricUnlockStore();
      fakeBioStore.bioSecretEnabled = true;

      final crypto = VaultCrypto(
        fakePlatform,
        FakeKeystoreService(),
        fakeBioStore,
      );

      await tester.runAsync(() async {
        await crypto.initialize('1234');
        final dummyPhrase = List.generate(12, (_) => 'abandon');
        await crypto.storeRecoveryBlob(dummyPhrase);
        await crypto.recoverWithPhrase(dummyPhrase);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => crypto),
            biometricUnlockStoreProvider.overrideWithValue(fakeBioStore),
          ],
          child: MaterialApp(
            home: const ResetPinScreen(),
            routes: {
              '/vault-home': (_) => const Scaffold(body: Text('HOME_SCREEN')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter first PIN: 5555
      for (final digit in ['5', '5', '5', '5']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.tap(find.text('Set PIN'));
      await tester.pumpAndSettle();

      // Confirm PIN: 5555
      for (final digit in ['5', '5', '5', '5']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.runAsync(() async {
        await tester.tap(find.text('Confirm PIN'));
        for (int i = 0; i < 150; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          if (fakePlatform.store['master_key_wrapped'] != null) break;
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeBioStore.clearBioSecretCount, greaterThanOrEqualTo(1));
      expect(find.text('HOME_SCREEN'), findsOneWidget);
    });
  });

  group('AUDIT-05: Duress PIN / Master PIN Collision Prevention', () {
    testWidgets('SetDuressPinScreen rejects candidate duress PIN matching vault PIN', (tester) async {
      final fakePlatform = FakePlatformService();
      final duressService = DuressService(fakePlatform);
      final crypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await crypto.initialize('1234');
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => crypto),
            duressServiceProvider.overrideWithValue(duressService),
          ],
          child: const MaterialApp(
            home: SetDuressPinScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pinField = find.byType(TextField);
      expect(pinField, findsOneWidget);

      // Attempt to set Duress PIN identical to Vault PIN ('1234')
      await tester.enterText(pinField, '1234');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Continue'));
      });
      await tester.pumpAndSettle();

      expect(find.text('This PIN is unavailable. Please choose a different PIN.'), findsOneWidget);
      final isEnabled = await duressService.isFakePinEnabled();
      expect(isEnabled, isFalse);
    });

    testWidgets('ResetPinScreen rejects candidate PIN matching active duress PIN', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePlatform = FakePlatformService();
      final duressService = FakeFastDuressService(fakePlatform, '7777');
      final crypto = FakeFastVaultCrypto()..currentPin = '1234';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => crypto),
            duressServiceProvider.overrideWithValue(duressService),
          ],
          child: const MaterialApp(
            home: ResetPinScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter PIN matching duress PIN ('7777')
      for (final digit in ['7', '7', '7', '7']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }

      await tester.runAsync(() async {
        await tester.tap(find.text('Set PIN'));
      });
      await tester.pumpAndSettle();

      expect(find.text('This PIN is unavailable. Please choose a different PIN.'), findsOneWidget);
    });

    testWidgets('VaultSettingsScreen rejects changing vault PIN to match active duress PIN', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePlatform = FakePlatformService();
      final duressService = FakeFastDuressService(fakePlatform, '8888');
      final fakeBioStore = FakeBiometricUnlockStore();
      final fakeBioService = FakeBiometricService();
      final fakeCrypto = FakeFastVaultCrypto()..currentPin = '1234';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            duressServiceProvider.overrideWithValue(duressService),
            biometricUnlockStoreProvider.overrideWithValue(fakeBioStore),
            biometricServiceProvider.overrideWithValue(fakeBioService),
          ],
          child: const MaterialApp(
            home: VaultSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Change PIN
      await tester.tap(find.text('Change PIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Enter new PIN matching duress PIN ('8888')
      await tester.enterText(find.widgetWithText(TextField, 'Current PIN'), '1234');
      await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '8888');
      await tester.enterText(find.widgetWithText(TextField, 'Confirm New PIN'), '8888');
      await tester.pump();

      await tester.tap(find.text('Change'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('This PIN is unavailable. Please choose a different PIN.'), findsOneWidget);
    });
  });

  group('AUDIT-08: Pre-increment Lockout Counter before PBKDF2', () {
    testWidgets('PinScreen increments wrong_attempts before verification and enforces lockout on failure', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePlatform = FakePlatformService();
      final fakeBioStore = FakeBiometricUnlockStore();
      final fakeBioService = FakeBiometricService();
      final fakeCrypto = FakeFastVaultCrypto()..currentPin = '1234';
      final fakeClock = FakeMonotonicClock();
      final lockoutService = LockoutService(fakePlatform, fakeClock);
      final duressService = FakeFastDuressService(fakePlatform, '7777');

      fakePlatform.store['vault_salt'] = 'dummy_salt';
      fakePlatform.store['vault_pin_hash'] = 'dummy_hash';
      fakePlatform.store['vault_setup_completed'] = 'true';
      fakePlatform.store['wrong_attempts'] = '4'; // One away from lockout

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            lockoutServiceProvider.overrideWithValue(lockoutService),
            duressServiceProvider.overrideWithValue(duressService),
            biometricUnlockStoreProvider.overrideWithValue(fakeBioStore),
            biometricServiceProvider.overrideWithValue(fakeBioService),
          ],
          child: MaterialApp(
            initialRoute: '/vault-pin',
            routes: {
              '/vault-pin': (_) => const PinScreen(),
              '/vault-enter-recovery': (_) => const Scaffold(body: Text('ENTER_RECOVERY')),
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter wrong PIN: '9999'
      final pinField = find.byType(TextField);
      await tester.enterText(pinField, '9999');
      await tester.pump();

      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // wrong_attempts was pre-incremented and saved to '5'
      expect(fakePlatform.store['wrong_attempts'], equals('5'));
      // 5 attempts activates progressive lockout (30 seconds)
      expect(fakePlatform.store.containsKey('lockout_set_wall'), isTrue);

      AutoLock().dispose();
    });

    testWidgets('PinScreen resets wrong_attempts to 0 upon successful PIN verification', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakePlatform = FakePlatformService();
      final fakeBioStore = FakeBiometricUnlockStore();
      final fakeBioService = FakeBiometricService();
      final fakeCrypto = FakeFastVaultCrypto()..currentPin = '1234';
      final fakeClock = FakeMonotonicClock();
      final lockoutService = LockoutService(fakePlatform, fakeClock);
      final duressService = FakeFastDuressService(fakePlatform, '7777');

      fakePlatform.store['vault_salt'] = 'dummy_salt';
      fakePlatform.store['vault_pin_hash'] = 'dummy_hash';
      fakePlatform.store['vault_setup_completed'] = 'true';
      fakePlatform.store['wrong_attempts'] = '2';

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            lockoutServiceProvider.overrideWithValue(lockoutService),
            duressServiceProvider.overrideWithValue(duressService),
            biometricUnlockStoreProvider.overrideWithValue(fakeBioStore),
            biometricServiceProvider.overrideWithValue(fakeBioService),
          ],
          child: MaterialApp(
            initialRoute: '/vault-pin',
            routes: {
              '/vault-pin': (_) => const PinScreen(),
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter correct PIN: '1234'
      final pinField = find.byType(TextField);
      await tester.enterText(pinField, '1234');
      await tester.pump();

      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Successful unlock clears attempt history and lockout state
      final remainingAttempts = fakePlatform.store['wrong_attempts'];
      expect(remainingAttempts == null || remainingAttempts == '0', isTrue);
      expect(fakePlatform.store['lockout_set_wall'], isNull);
      AutoLock().dispose();
    });
  });
}
