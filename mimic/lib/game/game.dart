// lib/game/game.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/router/app_router.dart' as router;
import 'package:mimic/multiplayer/network/disconnect_handler.dart';
import 'package:mimic/core/providers/provider_registration.dart'
    show vaultConcealServiceProvider, disconnectHandlerProvider;
import 'package:mimic/vault/security/vault_conceal_service.dart';



class MimicGame extends StatelessWidget {
  const MimicGame({super.key});

  static GlobalKey<NavigatorState> get navigatorKey => router.navigatorKey;

  // Game routes (forwarded to AppRouter for backward compatibility)
  static const String loadingRoute = router.AppRouter.loadingRoute;
  static const String homeRoute = router.AppRouter.homeRoute;
  static const String modeSelectRoute = router.AppRouter.modeSelectRoute;
  static const String playerSetupRoute = router.AppRouter.playerSetupRoute;
  static const String packSelectRoute = router.AppRouter.packSelectRoute;
  static const String wordRevealRoute = router.AppRouter.wordRevealRoute;
  static const String discussionRoute = router.AppRouter.discussionRoute;
  static const String votingRoute = router.AppRouter.votingRoute;
  static const String resultsRoute = router.AppRouter.resultsRoute;
  static const String multiplayerRoute = router.AppRouter.multiplayerRoute;
  static const String tutorialRoute = router.AppRouter.tutorialRoute;
  static const String profileRoute = router.AppRouter.profileRoute;
  static const String leaderboardRoute = router.AppRouter.leaderboardRoute;

  // Vault routes (forwarded to AppRouter for backward compatibility)
  static const String vaultPinRoute = router.AppRouter.vaultPinRoute;
  static const String vaultHomeRoute = router.AppRouter.vaultHomeRoute;
  static const String vaultPhotosRoute = router.AppRouter.vaultPhotosRoute;
  static const String vaultNotesRoute = router.AppRouter.vaultNotesRoute;
  static const String vaultAudioRoute = router.AppRouter.vaultAudioRoute;
  static const String vaultDocumentsRoute = router.AppRouter.vaultDocumentsRoute;
  static const String vaultSettingsRoute = router.AppRouter.vaultSettingsRoute;
  static const String vaultBreakinLogsRoute = router.AppRouter.vaultBreakinLogsRoute;
  static const String vaultRecoveryPhraseRoute = router.AppRouter.vaultRecoveryPhraseRoute;
  static const String vaultEnterRecoveryRoute = router.AppRouter.vaultEnterRecoveryRoute;
  static const String vaultResetPinRoute = router.AppRouter.vaultResetPinRoute;
  static const String vaultExportRoute = router.AppRouter.vaultExportRoute;
  static const String vaultImportRoute = router.AppRouter.vaultImportRoute;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _VaultConcealWrapper(),
    );
  }
}

/// Global wrapper that initializes VaultConcealService and starts the shake
/// listener at app startup. Sits above MaterialApp so the listener is active
/// on every screen. Uses [router.navigatorKey] for overlay + navigation.
class _VaultConcealWrapper extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VaultConcealWrapper> createState() =>
      _VaultConcealWrapperState();
}

class _VaultConcealWrapperState extends ConsumerState<_VaultConcealWrapper> {
  late final VaultConcealService _concealService;

  @override
  void initState() {
    super.initState();
    // Initialize and start the global conceal shake listener.
    _concealService = ref.read(vaultConcealServiceProvider);
    _concealService.init().then((_) {
      _concealService.start();
    });
  }

  @override
  void dispose() {
    // Stop the accelerometer subscription when the app root is torn down.
    _concealService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        // Listen to disconnectHandlerProvider globally to instantiate it and route disconnect events
        ref.listen<DisconnectHandler>(disconnectHandlerProvider, (previous, next) {
          // The disconnect handler is now initialized and listening.
          // Any routing of DisconnectEvents is handled globally via this controller.
        });

        return MaterialApp(
          title: 'Mimic Game',
          navigatorKey: router.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: HorrorTheme.themeData,
          themeMode: ThemeMode.dark, // Keep theme consistently in dark horror mode
          initialRoute: MimicGame.loadingRoute,
          onGenerateRoute: router.AppRouter.onGenerateRoute,
          navigatorObservers: [
            ref.watch(router.networkNavigatorObserverProvider),
          ],
        );
      },
    );
  }
}
