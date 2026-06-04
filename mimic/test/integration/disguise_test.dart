// test/integration/disguise_test.dart
//
// Integration tests for Mimic's disguise, stealth, and security mechanisms.
// Covers:
// 1. Recent apps thumbnail protection on backgrounding.
// 2. FLAG_SECURE screenshot protection enabled when vault is active.
// 3. FLAG_SECURE screenshot protection disabled during normal gameplay.
// 4. Panic mode (volume-down press trigger) routing and key purge.
// 5. Auto-lock when application is paused (sent to background).
// 6. Auto-lock on user inactivity timeout.
// 7. Android back button protection (no vault routes left in stack).
// 8. Launcher metadata validation (app name is "Mimic").

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/game/game.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/security/auto_lock.dart';
import 'package:mimic/vault/security/panic_mode.dart';

// Screens
import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/vault_home_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fakes
// ═══════════════════════════════════════════════════════════════════════════

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
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Entry Point
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  late FakePlatformService fakePlatform;
  late VaultCrypto fakeCrypto;
  final secureFlagsList = <int>[];

  setUp(() async {
    fakePlatform = FakePlatformService();
    fakeCrypto = VaultCrypto(fakePlatform);
    secureFlagsList.clear();
  });

  /// Build the integration test app environment with Riverpod overrides.
  Widget buildIntegrationApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MimicGame(),
    );
  }

  // Intercept the native platform window manager method calls to track FLAG_SECURE
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel('flutter_windowmanager').setMockMethodCallHandler((MethodCall methodCall) async {
      final flag = methodCall.arguments['flags'] as int?;
      if (flag != null) {
        if (methodCall.method == 'addFlags') {
          secureFlagsList.add(flag);
        } else if (methodCall.method == 'clearFlags') {
          secureFlagsList.remove(flag);
        }
      }
      return true;
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1 · Recent Apps Thumbnail Disguise
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('1. Recent apps thumbnail - backgrounding from vault shows game home', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    // 1. Navigate into the Vault (Unlock)
    await fakeCrypto.initialize('1234');
    expect(fakeCrypto.isUnlocked, isTrue);

    // Push the VaultHomeScreen route
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.pushNamed('/vault-home');
    await tester.pumpAndSettle();

    expect(find.byType(VaultHomeScreen), findsOneWidget);

    // 2. Background the app (simulate AppLifecycleState.paused)
    // The disguise system must immediately switch the UI stack or cover it
    // so that the OS recents screenshot captures a safe state (game HomeScreen).
    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    // Verify the vault screen is gone and the safe game HomeScreen is visible instead
    expect(find.byType(VaultHomeScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget,
        reason: 'Backgrounding the app from the vault must render the game HomeScreen for safety');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2 · FLAG_SECURE inside Vault
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('2. FLAG_SECURE - enabled when vault is active', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    // Unlock the vault
    await fakeCrypto.initialize('1234');
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.pushNamed('/vault-home');
    await tester.pumpAndSettle();

    // Android FLAG_SECURE constant is 0x00002000 (8192)
    const flagSecure = 8192;
    
    // Simulate screenshot block validation. The WindowManager must have FLAG_SECURE registered.
    expect(secureFlagsList.contains(flagSecure), isTrue,
        reason: 'FLAG_SECURE must be set when navigating inside the vault');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3 · No FLAG_SECURE during Game
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('3. FLAG_SECURE - disabled during normal gameplay', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    // Normal game screen is open, vault is locked
    expect(fakeCrypto.isUnlocked, isFalse);
    expect(find.byType(HomeScreen), findsOneWidget);

    const flagSecure = 8192;
    
    // Verify FLAG_SECURE is not set so players can screenshot gameplay normally
    expect(secureFlagsList.contains(flagSecure), isFalse,
        reason: 'FLAG_SECURE must NOT be set during regular game screens');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4 · Panic Mode (Volume-Down presses)
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('4. Panic mode - triple volume-down press clears key and exits', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    // Unlock and navigate to vault
    await fakeCrypto.initialize('1234');
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.pushNamed('/vault-home');
    await tester.pumpAndSettle();

    expect(fakeCrypto.isUnlocked, isTrue);

    // Simulate triple volume-down hardware key press
    for (int i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Verify panic trigger wiped keys and reset to safe screen
    expect(fakeCrypto.isUnlocked, isFalse,
        reason: 'Panic mode must immediately clear/wipe vault keys');
    expect(find.byType(HomeScreen), findsOneWidget,
        reason: 'Panic mode must navigate instantly back to game HomeScreen');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5 · Auto-lock on Background
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('5. Auto-lock on background - paused lifecycle clears key', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    await fakeCrypto.initialize('1234');
    expect(fakeCrypto.isUnlocked, isTrue);

    // Send the app to the background
    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    // Verify the key has been cleared immediately upon backgrounding
    expect(fakeCrypto.isUnlocked, isFalse,
        reason: 'Wiping vault keys must happen immediately when app goes to background');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6 · Auto-lock on Inactivity
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('6. Auto-lock on inactivity - clears key after timeout', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    await fakeCrypto.initialize('1234');
    
    // Initialize AutoLock timer manager
    final context = tester.element(find.byType(HomeScreen));
    AutoLock().init(context, container.read as WidgetRef); // mock initialization
    expect(fakeCrypto.isUnlocked, isTrue);

    // Advance clock past the 60-second inactivity threshold
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();

    // Verify inactivity timer fired and locked the vault
    expect(fakeCrypto.isUnlocked, isFalse,
        reason: 'Vault key must be cleared after inactivity timeout');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 7 · Android Back Button Route Cleansing
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('7. Navigation stack - back button cannot enter vault after locking', (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        platformServiceProvider.overrideWithValue(fakePlatform),
        vaultCryptoProvider.overrideWithValue(fakeCrypto),
      ],
    );

    await tester.pumpWidget(buildIntegrationApp(container));
    await tester.pumpAndSettle();

    // 1. Open Vault
    await fakeCrypto.initialize('1234');
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.pushNamed('/vault-home');
    await tester.pumpAndSettle();

    expect(find.byType(VaultHomeScreen), findsOneWidget);

    // 2. Lock Vault (wipes key and pushes /vault-pin removing vault history)
    navigator.pushNamedAndRemoveUntil('/vault-pin', (route) => route.settings.name == '/');
    await tester.pumpAndSettle();

    expect(find.byType(PinScreen), findsOneWidget);

    // 3. Simulate Android Back Button pop
    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    // Verify back button lands on safe game HomeScreen, NOT the VaultHomeScreen
    expect(find.byType(VaultHomeScreen), findsNothing,
        reason: 'Android back button must not navigate back into vault screens after lock');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 8 · App Metadata Disguise Validation
  // ═══════════════════════════════════════════════════════════════════════
  test('8. Launcher disguise - manifest label matches game name exactly', () async {
    // Read the AndroidManifest.xml from local file system
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    expect(await manifestFile.exists(), isTrue,
        reason: 'AndroidManifest.xml must exist to verify android metadata');

    final content = await manifestFile.readAsString();

    // Capture application node and verify its label attribute
    final labelRegex = RegExp(r'android:label="([^"]+)"');
    final match = labelRegex.firstMatch(content);

    expect(match, isNotNull,
        reason: 'AndroidManifest.xml application node must specify android:label');

    final appLabelValue = match!.group(1);
    expect(appLabelValue, equals('mimic'),
        reason: 'App name launcher label must remain "mimic" to keep vault disguised');
  });
}
