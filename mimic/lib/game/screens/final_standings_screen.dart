import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/services/stats_service.dart';
import 'package:mimic/game/models/player_profile.dart';
import 'package:mimic/game/game.dart';

class FinalStandingsScreen extends ConsumerStatefulWidget {
  const FinalStandingsScreen({super.key});

  @override
  ConsumerState<FinalStandingsScreen> createState() => _FinalStandingsScreenState();
}

class _FinalStandingsScreenState extends ConsumerState<FinalStandingsScreen> {
  bool _progressionApplied = false;
  int _xpGained = 0;
  bool _rankedUp = false;
  RankTier? _newRank;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_progressionApplied) {
        _applyProgression();
      }
    });
  }

  Future<void> _applyProgression() async {
    _progressionApplied = true;
    final gameState = ref.read(gameStateProvider);
    final statsService = ref.read(statsServiceProvider);
    
    final activeProfile = statsService.activeProfile;
    if (activeProfile == null) return;

    // Find owner seat
    final ownerPlayer = gameState.players.firstWhere(
      (p) => p.profileId == activeProfile.id,
      orElse: () => Player(id: '', name: '', color: 0),
    );

    if (ownerPlayer.id.isEmpty) return; // No owner seat

    final String ownerId = ownerPlayer.id;

    // Read BEFORE state
    final int suspicionBefore = activeProfile.suspicionScore;
    final RankTier tierBefore = activeProfile.rank;

    // Compute outcomes
    final winners = GameState.winnerIds(gameState);
    final bool won = winners.contains(ownerId);
    
    bool wasMimic = false;
    bool mimicWon = false;
    bool correctlyIdentified = false;
    bool votedOutWhileInnocent = false;
    int roundsSurvived = 0;

    for (final round in gameState.roundOutcomes) {
      final isOwnerMimicInRound = round.mimicIds.contains(ownerId);
      final isAccusedMimicInRound = round.accusedPlayerId != null && round.mimicIds.contains(round.accusedPlayerId);
      
      if (isOwnerMimicInRound) {
        wasMimic = true;
        if (round.accusedPlayerId != ownerId) {
          mimicWon = true;
        }
      } else {
        if (isAccusedMimicInRound) {
          correctlyIdentified = true;
        }
        if (round.accusedPlayerId == ownerId) {
          votedOutWhileInnocent = true;
        }
        if (round.accusedPlayerId != ownerId) {
          roundsSurvived++;
        }
      }
    }

    await statsService.recordGameResult(
      won: won,
      wasMimic: wasMimic,
      mimicWon: mimicWon,
      correctlyIdentified: correctlyIdentified,
      votedOutWhileInnocent: votedOutWhileInnocent,
      firstToAccuse: false,
      roundsSurvived: roundsSurvived,
      failedToVote: false,
    );

    // Read AFTER state
    final profileAfter = statsService.activeProfile;
    if (profileAfter != null) {
      if (mounted) {
        setState(() {
          _xpGained = profileAfter.suspicionScore - suspicionBefore;
          if (profileAfter.rank != tierBefore && profileAfter.suspicionScore > suspicionBefore) {
            _rankedUp = true;
            _newRank = profileAfter.rank;
          }
        });
      }
    }
  }

  void _playAgain() {
    ref.read(gameStateProvider.notifier).resetGame();
    Navigator.of(context).pushNamedAndRemoveUntil(
      MimicGame.playerSetupRoute,
      (route) => false,
    );
  }

  void _goHome() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      MimicGame.homeRoute,
      (route) => false,
    );
  }

  String _getUnlocksText(RankTier tier) {
    switch (tier) {
      case RankTier.bystander: return '';
      case RankTier.suspect: return 'Eye & Spider masks, "Suspicious Mind" title';
      case RankTier.investigator: return 'Bat & Moon masks, "The Detective" title';
      case RankTier.phantom: return 'Coffin & Potion masks, "Shadow" title';
      case RankTier.theOriginal: return 'Dagger & Mask, "The Original" title';
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);
    final sortedScores = gameState.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final winners = GameState.winnerIds(gameState);

    // Check if owner is present to show rewards section
    final statsService = ref.read(statsServiceProvider);
    final ownerPlayer = gameState.players.firstWhere(
      (p) => p.profileId == statsService.activeProfile?.id,
      orElse: () => Player(id: '', name: '', color: 0),
    );
    final bool hasOwner = ownerPlayer.id.isNotEmpty;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'FINAL STANDINGS',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 42,
                  letterSpacing: 3.0,
                  shadows: [
                    Shadow(
                      color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                      blurRadius: 10,
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Draw banner when no winner
              if (winners.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: HorrorColors.deepSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HorrorColors.ashGray),
                  ),
                  child: Text(
                    "IT'S A DRAW — NO WINNER THIS GAME",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.creepster(
                      color: HorrorColors.ashGray,
                      fontSize: 18,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

              const SizedBox(height: 14),
              
              // Scoreboard
              Expanded(
                child: ListView.builder(
                  itemCount: sortedScores.length,
                  itemBuilder: (context, index) {
                    final entry = sortedScores[index];
                    final player = gameState.players.firstWhere(
                      (p) => p.id == entry.key,
                      orElse: () => Player(id: entry.key, name: 'Unknown', color: 0xFFFFFFFF),
                    );
                    
                    final bool isWinner = winners.contains(player.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12.0),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isWinner 
                            ? HorrorColors.crimson.withValues(alpha: 0.2) 
                            : HorrorColors.cardSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isWinner ? HorrorColors.crimson : HorrorColors.darkRedTint,
                          width: isWinner ? 2.0 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '#${index + 1}',
                            style: GoogleFonts.creepster(
                              color: HorrorColors.ashGray,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          CircleAvatar(
                            backgroundColor: Color(player.color),
                            radius: 16,
                            child: Text(
                              player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                              style: GoogleFonts.creepster(color: HorrorColors.fogWhite, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              player.name.toUpperCase(),
                              style: GoogleFonts.creepster(
                                color: player.isEliminated ? HorrorColors.ashGray : HorrorColors.fogWhite,
                                fontSize: 18,
                                decoration: player.isEliminated ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: GoogleFonts.creepster(
                              color: isWinner ? HorrorColors.crimson : HorrorColors.fogWhite,
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Rewards Section
              if (hasOwner) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HorrorColors.deepSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HorrorColors.crimson),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'YOUR REWARDS',
                        style: GoogleFonts.creepster(
                          color: HorrorColors.ashGray,
                          fontSize: 18,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '+$_xpGained XP',
                        style: GoogleFonts.inter(
                          color: HorrorColors.fogWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_rankedUp && _newRank != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'RANK UP: ${_newRank!.displayName.toUpperCase()}',
                          style: GoogleFonts.creepster(
                            color: HorrorColors.crimson,
                            fontSize: 20,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (_newRank != RankTier.bystander) ...[
                          const SizedBox(height: 4),
                          Text(
                            'New unlocks: ${_getUnlocksText(_newRank!)}',
                            style: GoogleFonts.inter(
                              color: HorrorColors.ashGray,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _playAgain,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HorrorColors.crimson,
                          foregroundColor: HorrorColors.fogWhite,
                          side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'PLAY AGAIN',
                          style: GoogleFonts.creepster(
                            fontSize: 20,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _goHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HorrorColors.ashGray,
                          side: const BorderSide(color: HorrorColors.ashGray, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'HOME',
                          style: GoogleFonts.creepster(
                            fontSize: 20,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
