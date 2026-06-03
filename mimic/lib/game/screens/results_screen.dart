// lib/game/screens/results_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/game_state.dart';
import '../../vault/trigger/trigger_detector.dart';
import '../../vault/screens/pin_screen.dart';
import 'package:mimic/game/game.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  final Map<String, int>? voteCounts;

  const ResultsScreen({
    super.key,
    this.voteCounts,
  });

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _revealController;
  late Animation<double> _scaleAnimation;
  bool _mimicRevealed = false;
  bool _mimicWasCaught = false;
  int _triggerTapCount = 0;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOutBack),
    );
    
    TriggerCallbackRegistry().setOnTap(_recordScoreTap);

    // Start the reveal animation once in initState, not in build
    _startReveal();
  }

  @override
  void dispose() {
    _revealController.dispose();
    TriggerCallbackRegistry().setOnTap(null);
    super.dispose();
  }

  void _recordScoreTap(int index) {
    if (index == 0) {
      _triggerTapCount++;
      if (_triggerTapCount >= 3) {
        _triggerVault();
      }
    }
  }

  void _triggerVault() {
    _triggerTapCount = 0;
    Navigator.of(context).pushNamed(MimicGame.vaultPinRoute);
  }

  void _initializeScores() {
    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    final gameState = ref.read(gameStateProvider);
    final mimicId = gameState.mimicId;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, int>?;
    final voteCounts = widget.voteCounts ?? args ?? {};

    // Find player with most votes
    final maxVotes = voteCounts.values.isNotEmpty 
        ? voteCounts.values.reduce((a, b) => a > b ? a : b) 
        : 0;
    final topVotedId = maxVotes > 0
        ? voteCounts.entries.firstWhere((e) => e.value == maxVotes).key
        : '';

    final mimicWasCaught = topVotedId.isNotEmpty && topVotedId == mimicId;
    _mimicWasCaught = mimicWasCaught;

    if (mimicWasCaught) {
      // Non-Mimic players get +2 points
      for (final player in gameState.players) {
        if (player.id != mimicId) {
          final currentScore = gameState.scores[player.id] ?? 0;
          gameStateNotifier.updateScore(player.id, currentScore + 2);
        }
      }
    } else {
      // Mimic gets +3 points
      final currentScore = gameState.scores[mimicId] ?? 0;
      gameStateNotifier.updateScore(mimicId!, currentScore + 3);
    }
  }

  void _startReveal() {
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _mimicRevealed = true;
        });
        _revealController.forward();
        _initializeScores();
      }
    });
  }

  void _playAgain() {
    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    gameStateNotifier.nextRound();

    Navigator.of(context).pushNamed(MimicGame.wordRevealRoute);
  }

  void _newGame() {
    ref.read(gameStateProvider.notifier).resetGame();
    Navigator.of(context).pushNamedAndRemoveUntil(
      MimicGame.playerSetupRoute,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    final mimicPlayer = gameState.players.isNotEmpty
        ? gameState.players.firstWhere(
            (p) => p.id == gameState.mimicId,
            orElse: () => gameState.players.first,
          )
        : Player(id: 'unknown', name: 'Unknown', color: 0xFFFFFFFF);

    final sortedScores = gameState.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Results',
          style: TextStyle(color: Color(0xFF7F77DD)),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'The Mimic was...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                if (_mimicRevealed)
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Color(mimicPlayer.color),
                      child: Text(
                        mimicPlayer.name.isNotEmpty 
                            ? mimicPlayer.name[0].toUpperCase() 
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (_mimicRevealed)
                  const SizedBox(height: 16),
                if (_mimicRevealed)
                  Text(
                    mimicPlayer.name,
                    style: const TextStyle(
                      color: Color(0xFF7F77DD),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 40),
                if (_mimicRevealed)
                  Text(
                    _mimicWasCaught
                        ? 'The group correctly identified the Mimic!'
                        : 'The Mimic escaped undetected!',
                    style: TextStyle(
                      color: _mimicWasCaught
                          ? const Color(0xFF1D9E75)
                          : const Color(0xFFD85A30),
                      fontSize: 16,
                    ),
                  ),
                const SizedBox(height: 32),
                const Text(
                  'Scoreboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: sortedScores.length,
                    itemBuilder: (context, index) {
                      final entry = sortedScores[index];
                      final player = gameState.players.firstWhere(
                        (p) => p.id == entry.key,
                        orElse: () => Player(id: entry.key, name: 'Unknown', color: 0xFFFFFFFF),
                      );
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(player.color),
                          child: Text(
                            player.name.isNotEmpty 
                                ? player.name[0].toUpperCase() 
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          player.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: GestureDetector(
                          onTap: () {
                            TriggerCallbackRegistry().recordTap(0);
                          },
                          child: Text(
                            '${entry.value}',
                            style: TextStyle(
                              color: index == 0 ? Color(0xFF7F77DD) : Colors.white70,
                              fontSize: 20,
                              fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _playAgain,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F77DD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Play Again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _newGame,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0x337F77DD)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'New Game',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7F77DD),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TriggerDetector(
            tapSequence: const [0, 0, 0],
            timeout: const Duration(seconds: 2),
            onTrigger: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PinScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}