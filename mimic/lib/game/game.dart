// lib/game/game.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/theme/app_theme.dart';
import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/player_setup_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/screens/voting_screen.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/vault/screens/pin_screen.dart';
import 'package:mimic/vault/screens/vault_home_screen.dart';
import 'package:mimic/vault/screens/photo_vault_screen.dart';
import 'package:mimic/vault/screens/notes_screen.dart';
import 'package:mimic/vault/screens/audio_vault_screen.dart';
import 'package:mimic/vault/screens/document_vault_screen.dart';
import 'package:mimic/vault/screens/vault_settings_screen.dart';
import 'package:mimic/vault/screens/breakin_log_screen.dart';

class MimicGame extends StatelessWidget {
  const MimicGame({super.key});

  // Game routes
  static const String homeRoute = '/';
  static const String playerSetupRoute = '/player-setup';
  static const String wordRevealRoute = '/word-reveal';
  static const String discussionRoute = '/discussion';
  static const String votingRoute = '/voting';
  static const String resultsRoute = '/results';

  // Vault routes
  static const String vaultPinRoute = '/vault-pin';
  static const String vaultHomeRoute = '/vault-home';
  static const String vaultPhotosRoute = '/vault-photos';
  static const String vaultNotesRoute = '/vault-notes';
  static const String vaultAudioRoute = '/vault-audio';
  static const String vaultDocumentsRoute = '/vault-documents';
  static const String vaultSettingsRoute = '/vault-settings';
  static const String vaultBreakinLogsRoute = '/vault-breakin-logs';

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Mimic Game',
        debugShowCheckedModeBanner: false,
        theme: gameTheme,
        initialRoute: homeRoute,
        routes: {
          // Game screens
          homeRoute: (context) => const HomeScreen(),
          playerSetupRoute: (context) => const PlayerSetupScreen(),
          wordRevealRoute: (context) => const WordRevealScreen(),
          discussionRoute: (context) => const DiscussionScreen(),
          votingRoute: (context) => const VotingScreen(),
          resultsRoute: (context) => const ResultsScreen(),

          // Vault screens
          vaultPinRoute: (context) => const PinScreen(),
          vaultHomeRoute: (context) => const VaultHomeScreen(),
          vaultPhotosRoute: (context) => const PhotoVaultScreen(),
          vaultNotesRoute: (context) => const NotesScreen(),
          vaultAudioRoute: (context) => const AudioVaultScreen(),
          vaultDocumentsRoute: (context) => const DocumentVaultScreen(),
          vaultSettingsRoute: (context) => const VaultSettingsScreen(),
          vaultBreakinLogsRoute: (context) => const BreakInLogScreen(),
        },
      ),
    );
  }
}
