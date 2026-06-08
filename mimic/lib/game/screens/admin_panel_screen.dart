// mimic/lib/game/screens/admin_panel_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/services/stats_service.dart';

class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameStateProvider);
    final gameNotifier = ref.read(gameStateProvider.notifier);
    final stats = ref.read(statsServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ADMIN PANEL',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 28,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('GAME INTEL'),
          _buildActionTile(
            context,
            icon: Icons.visibility,
            title: 'Reveal Mimic',
            subtitle: gameState.mimicIds.isNotEmpty
                ? 'Mimic: ${gameState.players.where((p) => gameState.mimicIds.contains(p.id)).map((p) => p.name).join(", ")} | Word: ${gameState.currentWord ?? "none"}'
                : 'No mimic assigned',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(gameState.mimicIds.isNotEmpty
                      ? 'Mimic: ${gameState.players.where((p) => gameState.mimicIds.contains(p.id)).map((p) => p.name).join(", ")} | Word: ${gameState.currentWord ?? "none"}'
                      : 'No mimic assigned'),
                  backgroundColor: HorrorColors.cardSurface,
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.how_to_vote,
            title: 'Live Votes',
            subtitle: '${gameState.players.length} players in lobby',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Players: ${gameState.players.map((p) => p.name).join(", ")}'),
                  backgroundColor: HorrorColors.cardSurface,
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.shuffle,
            title: 'Swap Mimic',
            subtitle: 'Reassign mimic role randomly',
            onTap: () {
              if (gameState.players.isEmpty) return;
              final activePlayers = gameState.players.where((p) => p.isAlive).toList();
              if (activePlayers.isEmpty) return;
              final randomIndex = DateTime.now().millisecondsSinceEpoch % activePlayers.length;
              final newMimicId = activePlayers[randomIndex].id;
              gameNotifier.setMimicIds([newMimicId]);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Mimic swapped to: ${activePlayers[randomIndex].name}'),
                  backgroundColor: HorrorColors.crimson,
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('ROUND CONTROL'),
          _buildActionTile(
            context,
            icon: Icons.fast_forward,
            title: 'Skip Timer',
            subtitle: 'Set discussion timer to 0',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Timer skipped'),
                  backgroundColor: HorrorColors.crimson,
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.block,
            title: 'Force End Round',
            subtitle: 'End round immediately with current tally',
            onTap: () {
              gameNotifier.endGame();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacementNamed('/results');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Round force-ended'),
                  backgroundColor: HorrorColors.crimson,
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.refresh,
            title: 'Restart Round',
            subtitle: 'Reset round state, keep players and packs',
            onTap: () {
              gameNotifier.restartRound();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacementNamed('/word-reveal');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Round restarted'),
                  backgroundColor: HorrorColors.crimson,
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('SCORE CONTROL'),
          _buildActionTile(
            context,
            icon: Icons.cleaning_services,
            title: 'Clear Round Votes',
            subtitle: 'Wipe all votes for current round',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Round votes cleared'),
                  backgroundColor: HorrorColors.crimson,
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.emoji_events,
            title: 'Reset All Scores',
            subtitle: 'Zero out all Suspicion Scores in leaderboard',
            onTap: () {
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: HorrorColors.cardSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Text(
                    'Reset All Scores?',
                    style: GoogleFonts.creepster(color: HorrorColors.crimson, fontSize: 22),
                  ),
                  content: const Text(
                    'This will permanently zero out all player Suspicion Scores.',
                    style: TextStyle(color: HorrorColors.fogWhite, fontFamily: 'Inter'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text('CANCEL', style: GoogleFonts.creepster(color: HorrorColors.ashGray)),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        await stats.resetAllScores();
                        gameNotifier.restartRound();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All scores reset'),
                            backgroundColor: HorrorColors.crimson,
                          ),
                        );
                      },
                      child: Text('RESET', style: GoogleFonts.creepster(color: HorrorColors.crimson)),
                    ),
                  ],
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.edit,
            title: 'Adjust Player Score',
            subtitle: 'Add or subtract points from a player',
            onTap: () => _showAdjustScoreDialog(context, ref, gameState),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('SYSTEM'),
          _buildActionTile(
            context,
            icon: Icons.terminal,
            title: 'Game State Dump',
            subtitle: 'View full current state',
            onTap: () {
              final dump = const JsonEncoder.withIndent('  ').convert({
                'mode': gameState.selectedMode.name,
                'round': gameState.currentRound,
                'players': gameState.players.map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'alive': p.isAlive,
                  'ghost': p.isGhost,
                  'suspicion': p.suspicion,
                }).toList(),
                'mimicIds': gameState.mimicIds,
                'scores': gameState.scores,
                'suspicionScores': gameState.suspicionScores,
                'eliminated': gameState.eliminatedPlayers,
                'ghosts': gameState.ghostPlayers,
                'packs': gameState.selectedPacks,
                'currentWord': gameState.currentWord,
                'category': gameState.currentCategory,
              });
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: HorrorColors.cardSurface,
                  title: Text(
                    'Game State Dump',
                    style: GoogleFonts.creepster(color: HorrorColors.crimson, fontSize: 22),
                  ),
                  content: SingleChildScrollView(
                    child: Text(
                      dump,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: HorrorColors.fogWhite),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text('CLOSE', style: GoogleFonts.creepster(color: HorrorColors.ashGray)),
                    ),
                  ],
                ),
              );
            },
          ),
          _buildActionTile(
            context,
            icon: Icons.exit_to_app,
            title: 'Exit',
            subtitle: 'Return to game seamlessly',
            onTap: () => Navigator.of(context).pop(),
            iconColor: HorrorColors.crimson,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: GoogleFonts.creepster(
          color: HorrorColors.crimson,
          fontSize: 18,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = HorrorColors.crimson,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: HorrorColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: HorrorColors.fogWhite,
            fontFamily: 'Inter',
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: HorrorColors.ashGray,
            fontFamily: 'Inter',
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: HorrorColors.ashGray, size: 18),
        onTap: onTap,
      ),
    );
  }

  void _showAdjustScoreDialog(BuildContext context, WidgetRef ref, GameState gameState) {
    if (gameState.players.isEmpty) return;
    final gameNotifier = ref.read(gameStateProvider.notifier);
    final stats = ref.read(statsServiceProvider);
    String? selectedPlayerId;
    int delta = 0;
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: HorrorColors.cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Adjust Player Score',
            style: GoogleFonts.creepster(color: HorrorColors.crimson, fontSize: 22),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Player',
                  labelStyle: TextStyle(color: HorrorColors.fogWhite, fontFamily: 'Inter'),
                ),
                dropdownColor: HorrorColors.cardSurface,
                style: const TextStyle(color: HorrorColors.fogWhite, fontFamily: 'Inter'),
                initialValue: selectedPlayerId,
                items: gameState.players.map((player) {
                  return DropdownMenuItem<String>(
                    value: player.id,
                    child: Text(player.name),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedPlayerId = value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Points delta (+/-)',
                        labelStyle: TextStyle(color: HorrorColors.fogWhite, fontFamily: 'Inter'),
                      ),
                      style: const TextStyle(color: HorrorColors.fogWhite, fontFamily: 'Inter'),
                      onChanged: (value) => setDialogState(() => delta = int.tryParse(value) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setDialogState(() => delta--),
                    icon: const Icon(Icons.remove_circle, color: HorrorColors.crimson),
                  ),
                  IconButton(
                    onPressed: () => setDialogState(() => delta++),
                    icon: const Icon(Icons.add_circle, color: HorrorColors.crimson),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: HorrorColors.crimson, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('CANCEL', style: GoogleFonts.creepster(color: HorrorColors.ashGray)),
            ),
            TextButton(
              onPressed: () async {
                if (selectedPlayerId == null) {
                  setDialogState(() => error = 'Select a player');
                  return;
                }
                if (delta == 0) {
                  setDialogState(() => error = 'Enter a non-zero delta');
                  return;
                }
                Navigator.of(dialogContext).pop();
                await stats.applyScoreAction(delta);
                final currentScore = gameState.scores[selectedPlayerId] ?? 0;
                gameNotifier.updateScore(selectedPlayerId!, currentScore + delta);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Score adjusted by $delta'),
                    backgroundColor: HorrorColors.crimson,
                  ),
                );
              },
              child: Text('APPLY', style: GoogleFonts.creepster(color: HorrorColors.crimson)),
            ),
          ],
        ),
      ),
    );
  }
}
