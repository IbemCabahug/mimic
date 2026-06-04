// lib/game/screens/voting_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/widgets/suspicion_meter.dart';
import '../state/game_state.dart';
import '../../vault/trigger/trigger_detector.dart';
import 'package:mimic/game/game.dart';

class VotingScreen extends ConsumerStatefulWidget {
  const VotingScreen({super.key});

  @override
  ConsumerState<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends ConsumerState<VotingScreen> {
  final Map<String, int> _voteCounts = {};
  int _currentVoterIndex = 0;
  String? _selectedCandidateId;

  @override
  void initState() {
    super.initState();
    final gameState = ref.read(gameStateProvider);
    for (final player in gameState.players) {
      _voteCounts[player.id] = 0;
    }
  }

  void _submitVote(int targetIndex, String targetPlayerId) {
    // Record the tap on the index of the candidate for the stealth trigger detector
    TriggerCallbackRegistry().recordTap(targetIndex);

    setState(() {
      _voteCounts[targetPlayerId] = (_voteCounts[targetPlayerId] ?? 0) + 1;
      _currentVoterIndex++;
      _selectedCandidateId = null; // Reset selection for the next voter
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState.players.isEmpty) {
      return const Scaffold(
        backgroundColor: HorrorColors.voidBlack,
        body: Center(
          child: Text('No players present.', style: TextStyle(color: HorrorColors.fogWhite)),
        ),
      );
    }

    // Filter alive players who are eligible to vote and be voted for
    final alivePlayers = gameState.players.where((p) => !p.isEliminated).toList();
    final allVoted = _currentVoterIndex >= alivePlayers.length;
    final currentVoter = allVoted ? null : alivePlayers[_currentVoterIndex];

    // Determine the highest suspicion value among alive players
    double maxSuspicion = -1.0;
    for (final p in alivePlayers) {
      if (p.suspicion > maxSuspicion) {
        maxSuspicion = p.suspicion;
      }
    }

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          allVoted ? 'VOTING CONCLUDED' : 'VOTER: ${currentVoter!.name.toUpperCase()}',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 24,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StaticOverlay(
        child: Stack(
          children: [
            Column(
              children: [
                if (!allVoted)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    child: Text(
                      'SELECT WHO YOU SUSPECT IS THE MIMIC',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.creepster(
                        color: HorrorColors.ashGray,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                Expanded(
                  child: allVoted
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'ALL VOTES LOCKED IN',
                                style: GoogleFonts.creepster(
                                  fontSize: 32,
                                  color: HorrorColors.crimson,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Pass the device to the host to reveal who will face judgment.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: HorrorColors.ashGray,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 48),
                              // Heartbeat Pulsing Reveal Button
                              HeartbeatPulse(
                                child: SizedBox(
                                  width: 220,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).pushNamed(
                                        MimicGame.resultsRoute,
                                        arguments: Map.from(_voteCounts),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: HorrorColors.crimson,
                                      foregroundColor: HorrorColors.fogWhite,
                                      side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'REVEAL RESULTS',
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
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: alivePlayers.length,
                          itemBuilder: (context, index) {
                            final player = alivePlayers[index];
                            final isSelected = player.id == _selectedCandidateId;
                            final isHighestSuspicion = player.suspicion == maxSuspicion && maxSuspicion > 0.0;

                            // Custom player card
                            Widget card = GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCandidateId = player.id;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: HorrorColors.cardSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? HorrorColors.crimson
                                        : isHighestSuspicion
                                            ? HorrorColors.bloodRed.withValues(alpha: 0.6)
                                            : HorrorColors.darkRedTint,
                                    width: isSelected ? 2.5 : 1.0,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: HorrorColors.crimson.withValues(alpha: 0.25),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : null,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: Color(player.color),
                                            child: Text(
                                              player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                                              style: GoogleFonts.creepster(
                                                color: HorrorColors.fogWhite,
                                                fontSize: 20,
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: HorrorColors.crimson,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.check,
                                                  color: HorrorColors.fogWhite,
                                                  size: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        player.name.toUpperCase(),
                                        style: GoogleFonts.creepster(
                                          fontSize: 18,
                                          color: isSelected ? HorrorColors.crimson : HorrorColors.fogWhite,
                                          letterSpacing: 1.0,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 10),
                                      SuspicionMeter(value: player.suspicion, height: 10),
                                    ],
                                  ),
                                ),
                              ),
                            );

                            // Apply tension pulse to the most suspected victim
                            if (isHighestSuspicion) {
                              return HeartbeatPulse(child: card);
                            }
                            return card;
                          },
                        ),
                ),

                // Submit Vote Panel for Voter Flow
                if (!allVoted)
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _selectedCandidateId != null
                            ? () {
                                final targetId = _selectedCandidateId!;
                                final targetIndex = gameState.players.indexWhere((p) => p.id == targetId);
                                _submitVote(targetIndex, targetId);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HorrorColors.crimson,
                          foregroundColor: HorrorColors.fogWhite,
                          disabledBackgroundColor: HorrorColors.cardSurface,
                          disabledForegroundColor: HorrorColors.ashGray,
                          side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'SUBMIT VOTE',
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

            // Invisible TriggerDetector overlay for vault entrance
            TriggerDetector(
              tapSequence: const [2, 0, 2],
              onTrigger: () {
                Navigator.of(context).pushNamed(MimicGame.vaultPinRoute);
              },
            ),
          ],
        ),
      ),
    );
  }
}
