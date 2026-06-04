// lib/game/game.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/mode_select_screen.dart';
import 'package:mimic/game/screens/pack_select_screen.dart';
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
import 'package:mimic/vault/screens/recovery_phrase_screen.dart';
import 'package:mimic/vault/screens/enter_recovery_screen.dart';
import 'package:mimic/vault/screens/reset_pin_screen.dart';
import 'package:mimic/vault/screens/export_vault_screen.dart';
import 'package:mimic/vault/screens/import_vault_screen.dart';

class MimicGame extends StatelessWidget {
  const MimicGame({super.key});

  // Game routes
  static const String homeRoute = '/';
  static const String modeSelectRoute = '/mode-select';
  static const String playerSetupRoute = '/player-setup';
  static const String packSelectRoute = '/pack-select';
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
  static const String vaultRecoveryPhraseRoute = '/vault-recovery-phrase';
  static const String vaultEnterRecoveryRoute = '/vault-enter-recovery';
  static const String vaultResetPinRoute = '/vault-reset-pin';
  static const String vaultExportRoute = '/vault-export';
  static const String vaultImportRoute = '/vault-import';

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Mimic Game',
        debugShowCheckedModeBanner: false,
        theme: HorrorTheme.themeData,
        themeMode: ThemeMode.dark, // Keep theme consistently in dark horror mode
        initialRoute: homeRoute,
        routes: {
          // Game screens
          homeRoute: (context) => const HomeScreen(),
          modeSelectRoute: (context) => const ModeSelectScreen(),
          playerSetupRoute: (context) => const PlayerSetupScreen(),
          packSelectRoute: (context) => const PackSelectScreen(),
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
          vaultRecoveryPhraseRoute: (context) => const RecoveryPhraseScreen(),
          vaultEnterRecoveryRoute: (context) => const EnterRecoveryScreen(),
          vaultResetPinRoute: (context) => const ResetPinScreen(),
          vaultExportRoute: (context) => const ExportVaultScreen(),
          vaultImportRoute: (context) => const ImportVaultScreen(),
        },
      ),
    );
  }
}
