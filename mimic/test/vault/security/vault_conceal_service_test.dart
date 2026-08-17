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
}
