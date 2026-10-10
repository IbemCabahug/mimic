import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';
import 'package:mimic/vault/crypto/keystore_service.dart';
import 'package:mimic/vault/security/duress_service.dart';
import 'package:mimic/vault/security/decoy_vault_service.dart';
import 'package:mimic/vault/security/lockout_service.dart';
import 'package:mimic/vault/security/vault_conceal_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/screens/set_decoy_pin_screen.dart';
import 'package:mimic/vault/screens/decoy_vault_home_screen.dart';
import 'package:mimic/vault/screens/decoy_photos_screen.dart';
import 'package:mimic/vault/screens/decoy_notes_screen.dart';
import 'package:mimic/vault/screens/decoy_documents_screen.dart';
import 'package:mimic/vault/screens/decoy_settings_screen.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/core/providers/provider_registration.dart'
    show vaultConcealServiceProvider;

class FakePlatformService implements PlatformService {
  final Map<String, String> store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);

  @override
  Future<void> secureWrite(String key, String value) async => store[key] = value;

  @override
  Future<void> secureDelete(String key) async => store.remove(key);

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<Uint8List?> readEncryptedFile(String path) async => null;

  @override
  Future<File> resolveVaultFile(String path) async => throw UnimplementedError();

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async {}
}

class FakeKeystoreService implements KeystoreService {
  @override
  Future<void> ensureKey() async {}

  @override
  Future<String> wrap(String base64Data) async => base64Data;

  @override
  Future<String> unwrap(String base64Data) async => base64Data;

  @override
  Future<void> deleteKey() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Decoy Vault Screens Test', () {
    late FakePlatformService fakePlatform;
    late VaultCrypto crypto;
    late DuressService duressService;
    late DecoyVaultService decoyService;
    late ProStatusService proService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakePlatform = FakePlatformService();

      // Pre-populate pro entitlement so ProStatusService.isPro() returns true
      // when billing is enforced (kBillingEnforced = true).
      fakePlatform.store['pro_entitlement'] = 'pro';

      crypto = VaultCrypto(fakePlatform, FakeKeystoreService());
      await crypto.initialize('1234');
      crypto.lock();

      duressService = DuressService(fakePlatform);
      await duressService.setFakePin('9999');

      // Create ProStatusService with billingEnforced so it reads from storage.
      proService = ProStatusService(fakePlatform, billingEnforced: true);

      decoyService = DecoyVaultService(fakePlatform);
    });

    /// Helper to build common provider overrides for SetDecoyPinScreen tests.
    List<Override> _setDecoyPinOverrides() => [
          platformServiceProvider.overrideWithValue(fakePlatform),
          vaultCryptoProvider.overrideWith((ref) => crypto),
          duressServiceProvider.overrideWith((ref) => duressService),
          decoyVaultServiceProvider.overrideWith((ref) => decoyService),
          proStatusServiceProvider.overrideWithValue(proService),
          isProProvider.overrideWith((ref) => true),
        ];

    testWidgets('SetDecoyPinScreen rejects PIN matching vault PIN', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _setDecoyPinOverrides(),
          child: const MaterialApp(home: SetDecoyPinScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Enter Master PIN '1234'
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pumpAndSettle();

      // Scroll to make sure the button is visible, then tap
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('This PIN is unavailable. Please choose a different PIN.'), findsOneWidget);
    });

    testWidgets('SetDecoyPinScreen rejects PIN matching duress PIN', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _setDecoyPinOverrides(),
          child: const MaterialApp(home: SetDecoyPinScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Enter Duress PIN '9999'
      await tester.enterText(find.byType(TextField), '9999');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('This PIN is unavailable. Please choose a different PIN.'), findsOneWidget);
    });

    testWidgets('SetDecoyPinScreen saves valid candidate PIN', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _setDecoyPinOverrides(),
          child: const MaterialApp(home: SetDecoyPinScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Enter valid candidate '5555'
      await tester.enterText(find.byType(TextField), '5555');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Decoy PIN'), findsOneWidget);

      // Confirm '5555'
      await tester.enterText(find.byType(TextField), '5555');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Decoy PIN'));
      await tester.tap(find.text('Save Decoy PIN'));
      await tester.pumpAndSettle();

      expect(await decoyService.isDecoyPin('5555'), isTrue);
    });

    testWidgets('DecoyVaultHomeScreen displays category cards and counts', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            decoyVaultServiceProvider.overrideWith((ref) => decoyService),
            proStatusServiceProvider.overrideWithValue(proService),
          ],
          child: const MaterialApp(home: DecoyVaultHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SECURE VAULT'), findsOneWidget);
      expect(find.text('Private Photos'), findsOneWidget);
      expect(find.text('Encrypted Notes'), findsOneWidget);
      expect(find.text('Secure Documents'), findsOneWidget);
    });

    testWidgets('DecoyPhotosScreen renders photos and responds to search', (tester) async {
      await decoyService.addPhoto(DecoyPhoto(
        id: 'test_p1',
        title: 'Mountain Sunrise',
        createdAt: DateTime.now(),
      ));
      await decoyService.addPhoto(DecoyPhoto(
        id: 'test_p2',
        title: 'Beach Sunset',
        createdAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            decoyVaultServiceProvider.overrideWith((ref) => decoyService),
          ],
          child: const MaterialApp(home: DecoyPhotosScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Mountain Sunrise'), findsOneWidget);

      // Search for specific photo
      await tester.enterText(find.byType(TextField), 'Sunset');
      await tester.pumpAndSettle();

      expect(find.text('Beach Sunset'), findsOneWidget);
      expect(find.text('Mountain Sunrise'), findsNothing);
    });

    testWidgets('DecoyNotesScreen renders notes and allows reading note', (tester) async {
      await decoyService.saveNote(DecoyNote(
        id: 'test_n1',
        title: 'Weekly Grocery List',
        content: 'Apples, milk, bread',
        updatedAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            decoyVaultServiceProvider.overrideWith((ref) => decoyService),
          ],
          child: const MaterialApp(home: DecoyNotesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Weekly Grocery List'), findsOneWidget);

      await tester.tap(find.text('Weekly Grocery List'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Note'), findsOneWidget);
    });

    testWidgets('DecoyDocumentsScreen renders documents', (tester) async {
      await decoyService.addDocument(DecoyDocument(
        id: 'test_d1',
        name: 'Microwave_User_Manual.pdf',
        fileSize: 1024,
        updatedAt: DateTime.now(),
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            decoyVaultServiceProvider.overrideWith((ref) => decoyService),
          ],
          child: const MaterialApp(home: DecoyDocumentsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Microwave_User_Manual.pdf'), findsOneWidget);
    });

    testWidgets('DecoySettingsScreen allows changing decoy PIN', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(fakePlatform),
            decoyVaultServiceProvider.overrideWith((ref) => decoyService),
          ],
          child: const MaterialApp(home: DecoySettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault Settings'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget);

      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();

      expect(find.text('Change Vault PIN'), findsOneWidget);
    });

    testWidgets('PinScreen does not unlock Decoy Vault when user is not Pro / revoked', (tester) async {
      // Create a separate platform service for the non-Pro scenario.
      // Do NOT set pro_entitlement so isPro() returns false.
      final nonProPlatform = FakePlatformService();
      final nonProCrypto = VaultCrypto(nonProPlatform, FakeKeystoreService());
      await nonProCrypto.initialize('1234');
      nonProCrypto.lock();

      final nonProDuressService = DuressService(nonProPlatform);
      await nonProDuressService.setFakePin('9999');

      final revokedProService = ProStatusService(nonProPlatform, billingEnforced: true);
      // isPro() will return false because no pro_entitlement key is set.

      final nonProDecoyService = DecoyVaultService(nonProPlatform, revokedProService);
      // Set the decoy pin directly in storage (bypasses pro check)
      await nonProPlatform.secureWrite('decoy_pin_hash', '5555');

      final fakeClock = FakeMonotonicClock();
      final lockoutService = LockoutService(nonProPlatform, fakeClock);

      final concealService = VaultConcealService(null, nonProPlatform);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            platformServiceProvider.overrideWithValue(nonProPlatform),
            vaultCryptoProvider.overrideWith((ref) => nonProCrypto),
            duressServiceProvider.overrideWith((ref) => nonProDuressService),
            decoyVaultServiceProvider.overrideWith((ref) => nonProDecoyService),
            proStatusServiceProvider.overrideWithValue(revokedProService),
            isProProvider.overrideWith((ref) => false),
            lockoutServiceProvider.overrideWithValue(lockoutService),
            vaultConcealServiceProvider.overrideWithValue(concealService),
          ],
          child: MaterialApp(
            home: const PinScreen(),
            routes: {
              '/decoy-vault-home': (context) => const Scaffold(body: Text('DECOY_LANDED')),
              '/admin-panel': (context) => const Scaffold(body: Text('ADMIN_LANDED')),
              '/vault-home': (context) => const Scaffold(body: Text('VAULT_LANDED')),
              '/vault-enter-recovery': (context) => const Scaffold(body: Text('RECOVERY')),
              '/vault-import': (context) => const Scaffold(body: Text('IMPORT')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter the Decoy PIN '5555' via the TextField and submit
      await tester.enterText(find.byType(TextField), '5555');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      // Must NOT navigate to /decoy-vault-home!
      expect(find.text('DECOY_LANDED'), findsNothing);
      // The PinScreen shows 'Invalid PIN' for wrong attempts (not 'Incorrect PIN. Try again.')
      expect(find.text('Invalid PIN'), findsOneWidget);
    });
  });
}
