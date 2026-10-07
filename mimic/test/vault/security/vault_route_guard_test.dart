// test/vault/security/vault_route_guard_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mimic/core/router/app_router.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/vault/crypto/vault_crypto.dart';

class FakeNetworkService extends ChangeNotifier implements NetworkService {
  NetworkRole _role = NetworkRole.none;

  @override
  NetworkRole get role => _role;

  void setRole(NetworkRole role) {
    _role = role;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVaultCrypto extends ChangeNotifier implements VaultCrypto {
  bool _isUnlocked = false;

  @override
  bool get isUnlocked => _isUnlocked;

  void setUnlocked(bool unlocked) {
    _isUnlocked = unlocked;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SEC-07: VaultRouteGuard Tests', () {
    late FakeVaultCrypto fakeCrypto;
    late FakeNetworkService fakeNet;

    setUp(() {
      fakeCrypto = FakeVaultCrypto();
      fakeNet = FakeNetworkService();
    });

    testWidgets('Guarded route blocks access and redirects to PIN route when vault is locked',
        (tester) async {
      fakeCrypto.setUnlocked(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            networkServiceProvider.overrideWith((ref) => fakeNet),
          ],
          child: MaterialApp(
            routes: {
              AppRouter.vaultPinRoute: (context) =>
                  const Scaffold(body: Text('PIN Screen')),
            },
            home: const VaultRouteGuard(
              requireUnlocked: true,
              child: Scaffold(body: Text('Guarded Vault Content')),
            ),
          ),
        ),
      );

      // Guarded content must not be shown
      expect(find.text('Guarded Vault Content'), findsNothing);

      // Post-frame callback triggers redirect
      await tester.pumpAndSettle();

      // Navigated to PIN screen
      expect(find.text('PIN Screen'), findsOneWidget);
    });

    testWidgets('Guarded route allows access when vault is unlocked',
        (tester) async {
      fakeCrypto.setUnlocked(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            networkServiceProvider.overrideWith((ref) => fakeNet),
          ],
          child: const MaterialApp(
            home: VaultRouteGuard(
              requireUnlocked: true,
              child: Scaffold(body: Text('Guarded Vault Content')),
            ),
          ),
        ),
      );

      expect(find.text('Guarded Vault Content'), findsOneWidget);
    });

    testWidgets('Non-unlocked vault route (requireUnlocked: false) is accessible when locked',
        (tester) async {
      fakeCrypto.setUnlocked(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            networkServiceProvider.overrideWith((ref) => fakeNet),
          ],
          child: const MaterialApp(
            home: VaultRouteGuard(
              requireUnlocked: false,
              child: Scaffold(body: Text('Unlock / Recovery Screen')),
            ),
          ),
        ),
      );

      expect(find.text('Unlock / Recovery Screen'), findsOneWidget);
    });

    testWidgets('Active multiplayer session redirects all vault routes to home',
        (tester) async {
      fakeCrypto.setUnlocked(true);
      fakeNet.setRole(NetworkRole.guest);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            networkServiceProvider.overrideWith((ref) => fakeNet),
          ],
          child: MaterialApp(
            initialRoute: '/guarded',
            routes: {
              AppRouter.homeRoute: (context) =>
                  const Scaffold(body: Text('Game Home Screen')),
              '/guarded': (context) => const VaultRouteGuard(
                    requireUnlocked: true,
                    child: Scaffold(body: Text('Guarded Vault Content')),
                  ),
            },
          ),
        ),
      );

      expect(find.text('Guarded Vault Content'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Game Home Screen'), findsOneWidget);
    });

    testWidgets('Dynamic vault lock triggers redirect to PIN route while on screen',
        (tester) async {
      fakeCrypto.setUnlocked(true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultCryptoProvider.overrideWith((ref) => fakeCrypto),
            networkServiceProvider.overrideWith((ref) => fakeNet),
          ],
          child: MaterialApp(
            routes: {
              AppRouter.vaultPinRoute: (context) =>
                  const Scaffold(body: Text('PIN Screen')),
            },
            home: const VaultRouteGuard(
              requireUnlocked: true,
              child: Scaffold(body: Text('Guarded Vault Content')),
            ),
          ),
        ),
      );

      expect(find.text('Guarded Vault Content'), findsOneWidget);

      // Vault locks dynamically (e.g., auto-lock on timeout)
      fakeCrypto.setUnlocked(false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Guarded Vault Content'), findsNothing);
      expect(find.text('PIN Screen'), findsOneWidget);
    });

    testWidgets('All protected vault routes in AppRouter use VaultRouteGuard with requireUnlocked = true',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Placeholder())));
      final context = tester.element(find.byType(Placeholder));

      final protectedRoutes = [
        AppRouter.vaultHomeRoute,
        AppRouter.vaultPhotosRoute,
        AppRouter.vaultNotesRoute,
        AppRouter.vaultDocumentsRoute,
        AppRouter.vaultSettingsRoute,
        AppRouter.vaultBreakinLogsRoute,
        AppRouter.vaultRecoveryPhraseRoute,
        AppRouter.vaultSetDuressPinRoute,
        AppRouter.vaultExportRoute,
        AppRouter.vaultImportRoute,
        AppRouter.vaultVideosRoute,
        AppRouter.vaultDiagnosticsRoute,
        AppRouter.vaultManualRoute,
      ];

      for (final routeName in protectedRoutes) {
        final settings = RouteSettings(name: routeName);
        final route = AppRouter.onGenerateRoute(settings) as MaterialPageRoute?;
        expect(route, isNotNull, reason: '$routeName should have a route generator');

        final widget = route!.builder(context);
        expect(widget, isA<VaultRouteGuard>(), reason: '$routeName must be wrapped in VaultRouteGuard');
        final guard = widget as VaultRouteGuard;
        expect(guard.requireUnlocked, isTrue, reason: '$routeName must requireUnlocked == true');
      }

      final unlockRoutes = [
        AppRouter.vaultPinRoute,
        AppRouter.vaultEnterRecoveryRoute,
        AppRouter.vaultResetPinRoute,
      ];

      for (final routeName in unlockRoutes) {
        final settings = RouteSettings(name: routeName);
        final route = AppRouter.onGenerateRoute(settings) as MaterialPageRoute?;
        expect(route, isNotNull, reason: '$routeName should have a route generator');

        final widget = route!.builder(context);
        expect(widget, isA<VaultRouteGuard>(), reason: '$routeName must be wrapped in VaultRouteGuard');
        final guard = widget as VaultRouteGuard;
        expect(guard.requireUnlocked, isFalse, reason: '$routeName should not require unlocked state');
      }
    });
  });
}
