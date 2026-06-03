// lib/game/screens/voting_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    final gameState = ref.read(gameStateProvider);
    for (final player in gameState.players) {
      _voteCounts[player.id] = 0;
    }
  }

  void _castVote(int targetIndex, String targetPlayerId) {
    TriggerCallbackRegistry().recordTap(targetIndex);

    setState(() {
      _voteCounts[targetPlayerId] = (_voteCounts[targetPlayerId] ?? 0) + 1;
      _currentVoterIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    if (gameState.players.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F14),
        body: Center(child: Text('No players', style: TextStyle(color: Colors.white))),
      );
    }

    final allVoted = _currentVoterIndex >= gameState.players.length;
    final currentVoter = allVoted ? null : gameState.players[_currentVoterIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          allVoted ? 'All Voted' : 'Voter: ${currentVoter!.name}',
          style: const TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (!allVoted)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Tap to vote for who you think is the Mimic',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: gameState.players.length,
                      itemBuilder: (context, index) {
                        final player = gameState.players[index];
                        final voteCount = _voteCounts[player.id] ?? 0;

                        return Stack(
                          children: [
                            ElevatedButton(
                              onPressed: () => _castVote(index, player.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(player.color),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.white,
                                    child: Text(
                                      player.name.isNotEmpty
                                          ? player.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Color(player.color),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    player.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            if (voteCount > 0)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$voteCount',
                                    style: TextStyle(
                                      color: Color(player.color),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (allVoted)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      MimicGame.resultsRoute,
                      arguments: Map.from(_voteCounts),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F77DD),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Reveal Results',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          TriggerDetector(
            tapSequence: const [2, 0, 2],
            onTrigger: () {
              Navigator.of(context).pushNamed(MimicGame.vaultPinRoute);
            },
          ),
        ],
      ),
    );
  }
}
