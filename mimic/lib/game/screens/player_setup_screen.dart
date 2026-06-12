// lib/game/screens/player_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/services/stats_service.dart';
import 'package:mimic/game/game.dart';

class PlayerSetupScreen extends ConsumerStatefulWidget {
  const PlayerSetupScreen({super.key});

  @override
  ConsumerState<PlayerSetupScreen> createState() => _PlayerSetupScreenState();
}

class _PlayerSetupScreenState extends ConsumerState<PlayerSetupScreen> {
  final List<PlayerEntry> _players = [];
  final List<int> _playerColors = [
    0xFF8B0000, // bloodRed
    0xFFC41E3A, // crimson
    0xFF4A0E17, // deep wine
    0xFF7D1C1C, // rust red
    0xFF5C0632, // dark magenta
    0xFF360000, // near black red
    0xFFB22222, // firebrick red
    0xFF800000, // maroon
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with 2 players by default
    _addPlayer();
    _addPlayer();

    // The active profile is usually available because StatsService initializes at app boot.
    final profile = ref.read(statsServiceProvider).activeProfile;
    if (profile != null) {
      _players[0].nameController.text = profile.displayName;
      _players[0].profileId = profile.id;
    }
  }

  void _addPlayer() {
    if (_players.length >= 8) return;
    setState(() {
      _players.add(PlayerEntry(color: _playerColors[_players.length]));
    });
  }

  void _removePlayer(int index) {
    setState(() {
      _players[index].nameController.dispose();
      _players.removeAt(index);
    });
  }

  void _startGame() {
    final namedPlayers = _players.where((p) => p.nameController.text.trim().isNotEmpty).toList();
    if (namedPlayers.length < 2) return;

    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    
    // Reset notifier to clear any previous game data (scores, former round details)
    gameStateNotifier.resetGame();

    for (int i = 0; i < namedPlayers.length; i++) {
      gameStateNotifier.addPlayer(
        namedPlayers[i].nameController.text.trim(),
        namedPlayers[i].color,
        profileId: namedPlayers[i].profileId,
      );
    }

    Navigator.of(context).pushNamed(MimicGame.packSelectRoute);
  }

  bool get _canStart => _players.where((p) => p.nameController.text.trim().isNotEmpty).length >= 2;

  @override
  void dispose() {
    for (final player in _players) {
      player.nameController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);
    final mode = gameState.gameMode;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ROSTER SETUP',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 28,
            letterSpacing: 2.0,
          ),
        ),
        iconTheme: const IconThemeData(color: HorrorColors.crimson),
      ),
      body: StaticOverlay(
        child: Column(
          children: [
            // Mode-specific Warning Banner
            if (mode == GameMode.nightmare)
              _buildWarningBanner(
                message: 'TWO WILL DECEIVE. NEITHER WILL KNOW THE OTHER.',
                icon: Icons.warning_amber_rounded,
              )
            else if (mode == GameMode.survival)
              _buildWarningBanner(
                message: 'ELIMINATED PLAYERS BECOME WATCHERS.',
                icon: Icons.visibility_outlined,
              ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _players.length,
                itemBuilder: (context, index) {
                  final player = _players[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: HorrorColors.cardSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: HorrorColors.darkRedTint, width: 1),
                      ),
                      child: Row(
                        children: [
                          // Blood-colored avatar circle
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(player.color),
                                child: Text(
                                  (index + 1).toString(),
                                  style: GoogleFonts.creepster(
                                    color: HorrorColors.fogWhite,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              if (player.profileId != null)
                                Positioned(
                                  top: -6,
                                  right: -10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: HorrorColors.crimson,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'YOU',
                                      style: GoogleFonts.inter(
                                        color: HorrorColors.fogWhite,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          // Name input
                          Expanded(
                            child: TextField(
                              controller: player.nameController,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.inter(color: HorrorColors.fogWhite, fontSize: 16),
                              cursorColor: HorrorColors.crimson,
                              decoration: InputDecoration(
                                hintText: 'Enter Victim ${index + 1} Name',
                                hintStyle: GoogleFonts.inter(color: HorrorColors.ashGray),
                                filled: true,
                                fillColor: HorrorColors.deepSurface,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: HorrorColors.crimson, width: 1.0),
                                ),
                              ),
                            ),
                          ),
                          // Delete button if we have more than 2 entries
                          if (_players.length > 2)
                            IconButton(
                              icon: const Icon(Icons.close, color: HorrorColors.ashGray),
                              onPressed: () => _removePlayer(index),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Add & Start Action Panel
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_players.length < 8)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _addPlayer,
                        icon: const Icon(Icons.add, color: HorrorColors.crimson, size: 20),
                        label: Text(
                          'ADD PLAYER',
                          style: GoogleFonts.creepster(
                            color: HorrorColors.crimson,
                            fontSize: 18,
                            letterSpacing: 1.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: HorrorColors.crimson, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canStart ? _startGame : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HorrorColors.crimson,
                        foregroundColor: HorrorColors.fogWhite,
                        disabledBackgroundColor: HorrorColors.cardSurface,
                        disabledForegroundColor: HorrorColors.ashGray,
                        side: BorderSide(
                          color: _canStart ? HorrorColors.bloodRed : Colors.transparent,
                          width: 1.5,
                        ),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'START GAME',
                        style: GoogleFonts.creepster(
                          fontSize: 20,
                          letterSpacing: 2.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningBanner({required String message, required IconData icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: HorrorColors.darkRedTint.withValues(alpha: 0.7),
        border: Border.all(color: HorrorColors.crimson, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: HorrorColors.crimson, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.creepster(
                color: HorrorColors.fogWhite,
                fontSize: 14,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerEntry {
  final TextEditingController nameController;
  final int color;
  String? profileId;

  PlayerEntry({required this.color, this.profileId}) : nameController = TextEditingController();
}