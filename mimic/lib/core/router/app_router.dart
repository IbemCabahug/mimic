// lib/core/router/app_router.dart
//
// Centralized routing configuration for Mimic, supporting horror/party game screens,
// vault screens (for the disguise), and new multiplayer/networked routes with route guards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/providers/provider_registration.dart';


// Game screens
import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/mode_select_screen.dart';
import 'package:mimic/game/screens/pack_select_screen.dart';
import 'package:mimic/game/screens/player_setup_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/screens/voting_screen.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/screens/tutorial_screen.dart';
import 'package:mimic/game/screens/player_profile_screen.dart';
import 'package:mimic/game/screens/leaderboard_screen.dart';
import 'package:mimic/game/screens/admin_panel_screen.dart';
import 'package:mimic/core/screens/loading_screen.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/vault_home_screen.dart';
import 'package:mimic/vault/screens/photo_vault_screen.dart';
import 'package:mimic/vault/screens/notes_screen.dart';
import 'package:mimic/vault/screens/audio_vault_screen.dart';
import 'package:mimic/vault/screens/document_vault_screen.dart';
import 'package:mimic/vault/screens/vault_settings_screen.dart';
import 'package:mimic/vault/screens/breakin_log_screen.dart';
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
import 'package:mimic/vault/screens/enter_recovery_screen.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/screens/export_vault_screen.dart';
import 'package:mimic/vault/screens/import_vault_screen.dart';
import 'package:mimic/vault/screens/set_duress_pin_screen.dart';
import 'package:mimic/vault/screens/video_vault_screen.dart';

// Multiplayer screens
import 'package:mimic/multiplayer/screens/multiplayer_menu_screen.dart';
import 'package:mimic/multiplayer/screens/host_screen.dart';
import 'package:mimic/multiplayer/screens/join_screen.dart' hide LobbyScreen;
import 'package:mimic/multiplayer/screens/lobby_screen.dart';
import 'package:mimic/multiplayer/screens/network_word_reveal_screen.dart';
import 'package:mimic/multiplayer/screens/network_voting_screen.dart';
import 'package:mimic/multiplayer/screens/rejoin_screen.dart';
import 'package:mimic/game/screens/onboarding_screen.dart';

// Network dependencies
import 'package:mimic/multiplayer/network/network_service.dart';

/// Global navigator key used for context-less navigation, like displaying
/// connection dialogs from DisconnectHandler.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Application routing map and dynamic route generator.
class AppRouter {
  // Game route names
  static const String loadingRoute = 'loading';
  static const String homeRoute = '/';
  static const String modeSelectRoute = '/mode-select';
  static const String playerSetupRoute = '/player-setup';
  static const String packSelectRoute = '/pack-select';
  static const String wordRevealRoute = '/word-reveal';
  static const String discussionRoute = '/discussion';
  static const String votingRoute = '/voting';
  static const String resultsRoute = '/results';
  static const String multiplayerRoute = '/multiplayer';
  static const String tutorialRoute = '/tutorial';
  static const String profileRoute = '/profile';
  static const String leaderboardRoute = '/leaderboard';

  // Vault route names
  static const String vaultPinRoute = '/vault-pin';
  static const String vaultHomeRoute = '/vault-home';
  static const String vaultPhotosRoute = '/vault-photos';
  static const String vaultNotesRoute = '/vault-notes';
  static const String vaultAudioRoute = '/vault-audio';
  static const String vaultDocumentsRoute = '/vault-documents';
  static const String vaultSettingsRoute = '/vault-settings';
  static const String vaultBreakinLogsRoute = '/vault-breakin-logs';
  static const String vaultRecoveryPhraseRoute = '/vault-recovery-phrase';
  static const String vaultEnterRecoveryRoute = '/vault-enter-recovery';
  static const String vaultResetPinRoute = '/vault-reset-pin';
  static const String vaultSetDuressPinRoute = '/vault-set-duress-pin';
  static const String vaultExportRoute = '/vault-export';
  static const String vaultImportRoute = '/vault-import';
  static const String vaultVideosRoute = '/vault-videos';

  // Multiplayer route names
  static const String multiplayerHostRoute = '/multiplayer/host';
  static const String multiplayerJoinRoute = '/multiplayer/join';
  static const String multiplayerLobbyRoute = '/multiplayer/lobby';
  static const String multiplayerWordRevealRoute = '/multiplayer/word-reveal';
  static const String multiplayerVotingRoute = '/multiplayer/voting';
  static const String multiplayerRejoinRoute = '/multiplayer/rejoin';

  /// Generates the routes dynamically to handle guards and parameter passing.
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments;

    switch (settings.name) {
      // ─── Game Screens ──────────────────────────────────────────────────────
      case loadingRoute:
        return MaterialPageRoute(
          builder: (_) => const LoadingScreen(),
          settings: settings,
        );
      case homeRoute:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case '/onboarding':
        return MaterialPageRoute(
          builder: (_) => const OnboardingScreen(),
          settings: settings,
        );
      case '/admin-panel':
        return MaterialPageRoute(
          builder: (_) => const AdminPanelScreen(),
          settings: settings,
        );
      case modeSelectRoute:
        return MaterialPageRoute(
          builder: (_) => const ModeSelectScreen(),
          settings: settings,
        );
      case playerSetupRoute:
        return MaterialPageRoute(
          builder: (_) => const PlayerSetupScreen(),
          settings: settings,
        );
      case packSelectRoute:
        return MaterialPageRoute(
          builder: (_) => const PackSelectScreen(),
          settings: settings,
        );
      case wordRevealRoute:
        return MaterialPageRoute(
          builder: (_) => Consumer(
            builder: (context, ref, _) {
              final netService = ref.watch(networkServiceProvider);
              if (netService.isConnected) {
                return const NetworkWordRevealScreen();
              }
              return const WordRevealScreen();
            },
          ),
          settings: settings,
        );
      case discussionRoute:
        return MaterialPageRoute(
          builder: (_) => const DiscussionScreen(),
          settings: settings,
        );
      case votingRoute:
        return MaterialPageRoute(
          builder: (_) => Consumer(
            builder: (context, ref, _) {
              final netService = ref.watch(networkServiceProvider);
              if (netService.isConnected) {
                return const NetworkVotingScreen();
              }
              return const VotingScreen();
            },
          ),
          settings: settings,
        );
      case resultsRoute:
        return MaterialPageRoute(
          builder: (_) => const ResultsScreen(),
          settings: settings,
        );
      case multiplayerRoute:
        return MaterialPageRoute(
          builder: (_) => const MultiplayerProviderScope(
            child: MultiplayerMenuScreen(),
          ),
          settings: settings,
        );
      case tutorialRoute:
        return MaterialPageRoute(
          builder: (_) => const TutorialScreen(),
          settings: settings,
        );
      case profileRoute:
        return MaterialPageRoute(
          builder: (_) => const PlayerProfileScreen(),
          settings: settings,
        );
      case leaderboardRoute:
        return MaterialPageRoute(
          builder: (_) => const LeaderboardScreen(),
          settings: settings,
        );

      // ─── Vault Screens ─────────────────────────────────────────────────────
      case vaultPinRoute:
        return MaterialPageRoute(
          builder: (_) => const PinScreen(),
          settings: settings,
        );
      case vaultHomeRoute:
        return MaterialPageRoute(
          builder: (_) => const VaultHomeScreen(),
          settings: settings,
        );
      case vaultPhotosRoute:
        return MaterialPageRoute(
          builder: (_) => const PhotoVaultScreen(),
          settings: settings,
        );
      case vaultNotesRoute:
        return MaterialPageRoute(
          builder: (_) => const NotesScreen(),
          settings: settings,
        );
      case vaultAudioRoute:
        return MaterialPageRoute(
          builder: (_) => const AudioVaultScreen(),
          settings: settings,
        );
      case vaultDocumentsRoute:
        return MaterialPageRoute(
          builder: (_) => const DocumentVaultScreen(),
          settings: settings,
        );
      case vaultSettingsRoute:
        return MaterialPageRoute(
          builder: (_) => const VaultSettingsScreen(),
          settings: settings,
        );
      case vaultBreakinLogsRoute:
        return MaterialPageRoute(
          builder: (_) => const BreakInLogScreen(),
          settings: settings,
        );
      case vaultRecoveryPhraseRoute:
        return MaterialPageRoute(
          builder: (_) => const RecoveryPhraseScreen(),
          settings: settings,
        );
      case vaultEnterRecoveryRoute:
        return MaterialPageRoute(
          builder: (_) => const EnterRecoveryScreen(),
          settings: settings,
        );
      case vaultResetPinRoute:
        return MaterialPageRoute(
          builder: (_) => const ResetPinScreen(),
          settings: settings,
        );
      case vaultSetDuressPinRoute:
        return MaterialPageRoute(
          builder: (_) => const SetDuressPinScreen(),
          settings: settings,
        );
      case vaultExportRoute:
        return MaterialPageRoute(
          builder: (_) => const ExportVaultScreen(),
          settings: settings,
        );
      case vaultImportRoute:
        return MaterialPageRoute(
          builder: (_) => const ImportVaultScreen(),
          settings: settings,
        );
      case vaultVideosRoute:
        return MaterialPageRoute(
          builder: (_) => const VideoVaultScreen(),
          settings: settings,
        );

      // ─── Multiplayer Screens (With Route Guards & Parameters) ──────────────
      case multiplayerHostRoute:
        final hostName = args is String ? args : 'Host';
        return MaterialPageRoute(
          builder: (_) => RouteGuard(
            guard: (netService) => netService.role == NetworkRole.host,
            child: HostScreen(hostName: hostName),
          ),
          settings: settings,
        );

      case multiplayerJoinRoute:
        return MaterialPageRoute(
          builder: (_) => RouteGuard(
            guard: (netService) => netService.role == NetworkRole.none,
            child: const JoinScreen(),
          ),
          settings: settings,
        );

      case multiplayerLobbyRoute:
        final isHost = args is bool ? args : (args is Map ? (args['isHost'] ?? false) : false);
        return MaterialPageRoute(
          builder: (_) => RouteGuard(
            guard: (netService) => netService.isConnected,
            child: LobbyScreen(isHost: isHost),
          ),
          settings: settings,
        );

      case multiplayerWordRevealRoute:
        return MaterialPageRoute(
          builder: (_) => RouteGuard(
            guard: (netService) => netService.isConnected,
            child: const NetworkWordRevealScreen(),
          ),
          settings: settings,
        );

      case multiplayerVotingRoute:
        return MaterialPageRoute(
          builder: (_) => RouteGuard(
            guard: (netService) => netService.isConnected,
            child: const NetworkVotingScreen(),
          ),
          settings: settings,
        );

      case multiplayerRejoinRoute:
        String lastRoomCode = '';
        String lastPlayerName = '';
        String lastPlayerId = '';

        if (args is Map<String, dynamic>) {
          lastRoomCode = args['lastRoomCode'] ?? '';
          lastPlayerName = args['lastPlayerName'] ?? '';
          lastPlayerId = args['lastPlayerId'] ?? '';
        } else if (args is Map) {
          lastRoomCode = args['lastRoomCode']?.toString() ?? '';
          lastPlayerName = args['lastPlayerName']?.toString() ?? '';
          lastPlayerId = args['lastPlayerId']?.toString() ?? '';
        }

        return MaterialPageRoute(
          builder: (_) => RejoinScreen(
            lastRoomCode: lastRoomCode,
            lastPlayerName: lastPlayerName,
            lastPlayerId: lastPlayerId,
          ),
          settings: settings,
        );

      default:
        // Let the default router or next handler catch undefined routes.
        return null;
    }
  }
}

/// A reactive route wrapper that validates connectivity or network role state
/// before rendering the screen. If the guard condition fails, the user is
/// redirected to the multiplayer menu screen.
class RouteGuard extends ConsumerWidget {
  final Widget child;
  final bool Function(NetworkService) guard;

  const RouteGuard({
    super.key,
    required this.child,
    required this.guard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netService = ref.watch(networkServiceProvider);

    if (!guard(netService)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Pop or remove routes until we reach the main route, and push multiplayer menu.
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRouter.multiplayerRoute,
          (route) => route.isFirst,
        );
      });

      // Show a solid background during the redirect frame to prevent visual flash
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    return child;
  }
}

/// NavigatorObserver that listens for popped back routes to the home or mode select
/// screen, shutting down any active network hosts/clients to prevent dangling socket connections.
class NetworkNavigatorObserver extends NavigatorObserver {
  final Ref ref;

  NetworkNavigatorObserver(this.ref);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _checkAndDisconnect(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _checkAndDisconnect(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _checkAndDisconnect(newRoute);
  }

  void _checkAndDisconnect(Route<dynamic>? activeRoute) {
    if (activeRoute == null) return;
    final name = activeRoute.settings.name;
    if (name == AppRouter.homeRoute || name == '/home') {
      try {
        final netService = ref.read(networkServiceProvider);
        if (netService.isConnected) {
          netService.disconnect();
        }
      } catch (e) {
        debugPrint('[NetworkNavigatorObserver] Failed to automatically disconnect: $e');
      }
    }
  }
}

/// Provider for the [NetworkNavigatorObserver].
final networkNavigatorObserverProvider = Provider<NetworkNavigatorObserver>((ref) {
  return NetworkNavigatorObserver(ref);
});
