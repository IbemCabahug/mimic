// test/vault/security/vault_conceal_service_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
import 'package:mimic/vault/security/vault_conceal_service.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/core/providers/provider_registration.dart' show vaultConcealServiceProvider;
import 'package:mimic/core/router/app_router.dart' as router;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePlatformService implements PlatformService {
  final Map<String, String> secureStore = {};
  final Map<String, Uint8List> fileStore = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => secureStore[key];

  @override
  Future<void> secureWrite(String key, String value) async {
    secureStore[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    secureStore.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {
    fileStore[path] = data;
  }

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => fileStore[path];

  @override
  Future<void> deleteFile(String path) async {
    fileStore.remove(path);
  }

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();
}

void main() {
  group('ShakeSensitivity Enum', () {
    test('1 · correctly maps to thresholds', () {
      expect(ShakeSensitivity.low.threshold, equals(24.0));
      expect(ShakeSensitivity.medium.threshold, equals(18.0));
      expect(ShakeSensitivity.high.threshold, equals(13.0));
    });

    test('2 · fromName resolves names or defaults to medium', () {
      expect(ShakeSensitivity.fromCode('low'), equals(ShakeSensitivity.low));
      expect(ShakeSensitivity.fromCode('high'), equals(ShakeSensitivity.high));
      expect(ShakeSensitivity.fromCode('medium'), equals(ShakeSensitivity.medium));
      expect(ShakeSensitivity.fromCode(null), equals(ShakeSensitivity.medium));
      expect(ShakeSensitivity.fromCode('invalid'), equals(ShakeSensitivity.medium));
    });
  });

  group('VaultConcealService Persistence & Configuration', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PathProviderPlatform.instance = MockPathProviderPlatform(Directory.systemTemp.path);
    });

    test('3 · init() loads default medium threshold if unset', () async {
      final service = VaultConcealService(null, const PlatformServicePlaceholder());
      await service.init();
      expect(service.sensitivity, equals(ShakeSensitivity.medium));
    });

    test('4 · setSensitivity persists the choice and updates live', () async {
      final service = VaultConcealService(null, const PlatformServicePlaceholder());
      await service.init();

      await service.setSensitivity(ShakeSensitivity.high);
      expect(service.sensitivity, equals(ShakeSensitivity.high));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('shake_sensitivity'), equals('high'));

      // Validate reload
      final newService = VaultConcealService(null, const PlatformServicePlaceholder());
      await newService.init();
      expect(newService.sensitivity, equals(ShakeSensitivity.high));
    });

    test('a · toggle-off works when _isConcealed is stale/false but storage holds true', () async {
      final fakePlatform = FakePlatformService();
      fakePlatform.secureStore['vault_concealed'] = 'true';

      // Fresh instance without init: _isConcealed is initially false in memory (stale)
      final service = VaultConcealService(null, fakePlatform);
      expect(service.isConcealedCached, isFalse);

      await service.toggleConceal();

      expect(await fakePlatform.secureRead('vault_concealed'), equals('false'));
      expect(service.isConcealedCached, isFalse);
    });

    test('b · setConcealed(true) followed by init() leaves _isConcealed true', () async {
      final fakePlatform = FakePlatformService();
      final service1 = VaultConcealService(null, fakePlatform);
      await service1.setConcealed(true);
      expect(fakePlatform.secureStore['vault_concealed'], equals('true'));

      final service2 = VaultConcealService(null, fakePlatform);
      expect(service2.isConcealedCached, isFalse);
      await service2.init();
      expect(service2.isConcealedCached, isTrue);
      expect(await service2.isConcealed(), isTrue);
    });

    testWidgets('c · a correct PIN while concealed clears the flag and unlocks', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      // Create vault with PIN 1234
      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      fakeCrypto.lock();

      // Mark concealed
      await fakePlatform.secureWrite('vault_concealed', 'true');
      expect(fakePlatform.secureStore['vault_concealed'], equals('true'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            initialRoute: '/vault-pin',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
              '/vault-pin': (_) => const PinScreen(),
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Unlock'));
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (find.byType(RecoveryPhraseScreen).evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(fakePlatform.secureStore['vault_concealed'], equals('false'),
          reason: 'Correct PIN must clear the vault_concealed flag');
      expect(fakeCrypto.isUnlocked, isTrue,
          reason: 'Correct PIN must successfully unlock the vault');
      expect(find.byType(RecoveryPhraseScreen), findsOneWidget,
          reason: 'Vault with no recovery phrase setup must navigate to forced RecoveryPhraseScreen on unlock');
    });

    testWidgets('d · a wrong PIN while concealed leaves the flag set and does NOT unlock', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      // Create vault with PIN 1234
      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      fakeCrypto.lock();

      // Mark concealed
      await fakePlatform.secureWrite('vault_concealed', 'true');
      expect(fakePlatform.secureStore['vault_concealed'], equals('true'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            initialRoute: '/vault-pin',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
              '/vault-pin': (_) => const PinScreen(),
            },
          ),
        ),
      );
      await tester.runAsync(() async {
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      await tester.enterText(find.byType(TextField), '9999');
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Unlock'));
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (find.text('Invalid PIN').evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(fakePlatform.secureStore['vault_concealed'], equals('true'),
          reason: 'Wrong PIN must NOT clear the vault_concealed flag');
      expect(fakeCrypto.isUnlocked, isFalse,
          reason: 'Wrong PIN must not unlock crypto');
      expect(find.text('Invalid PIN'), findsOneWidget);
    });
  });

  group('AutoLock & Conceal Lifecycle', () {
    late Directory testTempDir;

    setUp(() {
      AutoLock().dispose();
      testTempDir = Directory.systemTemp.createTempSync('vault_conceal_test_');
      // throwOnTemp bypasses native dart:io stream hanging during fakeAsync auto-lock testing
      PathProviderPlatform.instance = MockPathProviderPlatform(testTempDir.path, throwOnTemp: true);
    });

    tearDown(() {
      AutoLock().dispose();
      try {
        testTempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('e-control · positive control: auto-lock timer fires and navigates to /vault-pin when unlocked and not concealed', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      expect(fakeCrypto.isUnlocked, isTrue);

      late BuildContext savedContext;
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/vault-home',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const Scaffold(body: Text('VAULT_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      // Initialize AutoLock with vault unlocked
      AutoLock().init(savedContext, savedRef);

      // Advance time past auto-lock timeout (60 seconds) without concealing
      await tester.pump(const Duration(seconds: 70));
      await tester.runAsync(() async {
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (!fakeCrypto.isUnlocked) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            break;
          }
        }
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // Positive control: auto-lock must navigate to PIN_SCREEN
      expect(find.text('PIN_SCREEN'), findsOneWidget);
      expect(fakeCrypto.isUnlocked, isFalse);
    });

    testWidgets('e · after a conceal, the auto-lock timer no longer fires navigation to /vault-pin', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      expect(fakeCrypto.isUnlocked, isTrue);

      late BuildContext savedContext;
      late WidgetRef savedRef;
      late VaultConcealService concealService;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/vault-home',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  concealService = ref.read(vaultConcealServiceProvider);
                  return const Scaffold(body: Text('VAULT_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      // Initialize AutoLock as happens on vault unlock
      AutoLock().init(savedContext, savedRef);

      // Trigger concealment
      await tester.runAsync(() async {
        await concealService.toggleConceal();
      });
      await tester.pumpAndSettle();

      // Navigation should be at game home
      expect(find.text('GAME_HOME'), findsOneWidget);
      expect(fakeCrypto.isUnlocked, isFalse);

      // Advance time past auto-lock timeout (60 seconds)
      await tester.pump(const Duration(seconds: 70));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Should still be at GAME_HOME, NOT PIN_SCREEN
      expect(find.text('GAME_HOME'), findsOneWidget);
      expect(find.text('PIN_SCREEN'), findsNothing);
    });

    // NOTE: The background-resume vector is not reachable in fake time because _backgroundedAt uses the real wall clock.
    testWidgets('f · _lockVault foreground timer with the vault already locked performs no navigation', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());
      expect(fakeCrypto.isUnlocked, isFalse);

      late BuildContext savedContext;
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/',
            routes: {
              '/': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const Scaffold(body: Text('GAME_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      // Initialize AutoLock while vault is locked (arms foreground 60s timer)
      AutoLock().init(savedContext, savedRef);

      // Advance past 60s timer so _lockVault fires in fake time
      await tester.pump(const Duration(seconds: 70));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Defense-in-depth guard: since wasUnlocked was false, no navigation occurred
      expect(find.text('GAME_HOME'), findsOneWidget);
      expect(find.text('PIN_SCREEN'), findsNothing);
    });

    testWidgets('backgrounding past the idle timeout still locks when not suspended', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      expect(fakeCrypto.isUnlocked, isTrue);

      late BuildContext savedContext;
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/vault-home',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const Scaffold(body: Text('VAULT_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      AutoLock().init(savedContext, savedRef);
      expect(AutoLock().isSuspended, isFalse);

      // Simulate backgrounding
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      // Fast-forward background time past 60-second idle timeout
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(seconds: 70)));
      // Resume
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Drain _lockVault
      await tester.runAsync(() async {
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (!fakeCrypto.isUnlocked) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            break;
          }
        }
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(fakeCrypto.isUnlocked, isFalse,
          reason: 'Vault must lock when un-suspended background time exceeds _timeout');
      expect(find.text('PIN_SCREEN'), findsOneWidget);
    });

    testWidgets('a suspended import survives a long trip to the file picker', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      expect(fakeCrypto.isUnlocked, isTrue);

      late BuildContext savedContext;
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/vault-home',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const Scaffold(body: Text('VAULT_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      AutoLock().init(savedContext, savedRef);
      // Suspend auto-lock (e.g. during file picker import)
      AutoLock().suspend();
      expect(AutoLock().isSuspended, isTrue);

      // Simulate backgrounding while picking files (e.g. 5 minutes)
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(minutes: 5)));
      // Resume from background
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(fakeCrypto.isUnlocked, isTrue,
          reason: 'Suspended import must NOT lock when background time is less than suspendCeiling');
      expect(AutoLock().isSuspended, isTrue,
          reason: 'isSuspended must remain true across background resume');
      expect(find.text('VAULT_HOME'), findsOneWidget);
      expect(find.text('PIN_SCREEN'), findsNothing);

      // Clean up the active 30-minute suspend timer before test finishes
      AutoLock().dispose();
    });

    testWidgets('a suspended session locks once the ceiling is exceeded', (WidgetTester tester) async {
      final fakePlatform = FakePlatformService();
      final fakeCrypto = VaultCrypto(fakePlatform, FakeKeystoreService());

      await tester.runAsync(() async {
        await fakeCrypto.initialize('1234');
      });
      expect(fakeCrypto.isUnlocked, isTrue);

      late BuildContext savedContext;
      late WidgetRef savedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
          ],
          child: MaterialApp(
            navigatorKey: router.navigatorKey,
            initialRoute: '/vault-home',
            routes: {
              '/': (_) => const Scaffold(body: Text('GAME_HOME')),
              '/vault-home': (_) => Consumer(
                builder: (context, ref, _) {
                  savedContext = context;
                  savedRef = ref;
                  return const Scaffold(body: Text('VAULT_HOME'));
                },
              ),
              '/vault-pin': (_) => const Scaffold(body: Text('PIN_SCREEN')),
            },
          ),
        ),
      );
      await tester.pump();

      AutoLock().init(savedContext, savedRef);
      AutoLock().suspend();
      expect(AutoLock().isSuspended, isTrue);

      // Simulate backgrounding past 30-minute suspend ceiling (e.g. 31 minutes)
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.paused);
      AutoLock().setBackgroundedAtForTesting(DateTime.now().subtract(const Duration(minutes: 31)));
      // Resume from background
      AutoLock().didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Drain _lockVault
      await tester.runAsync(() async {
        for (int i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (!fakeCrypto.isUnlocked) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            break;
          }
        }
      });
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(fakeCrypto.isUnlocked, isFalse,
          reason: 'Suspended session must lock when background duration exceeds suspendCeiling');
      expect(find.text('PIN_SCREEN'), findsOneWidget);
    });
  });
}

class MockPathProviderPlatform extends PathProviderPlatform {
  final String path;
  final bool throwOnTemp;
  MockPathProviderPlatform(this.path, {this.throwOnTemp = false});

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async {
    if (throwOnTemp) throw UnsupportedError('Test environment temp dir');
    return path;
  }
}
