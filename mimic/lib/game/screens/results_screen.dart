// lib/game/screens/results_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import '../state/game_state.dart';
import '../../vault/trigger/trigger_detector.dart';
import '../../vault/security/secret_entry_trail.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';

enum ResultsPhase { accusation, judgment, revelation, butWait, revelation2 }

class ResultsScreen extends ConsumerStatefulWidget {
  final Map<String, int>? voteCounts;

  const ResultsScreen({
    super.key,
    this.voteCounts,
  });

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> with TickerProviderStateMixin {
  ResultsPhase _phase = ResultsPhase.accusation;
  late AnimationController _particlesController;
  
  bool _mimicWasCaught = false;
  String _accusedPlayerId = '';

  /// F31: one continuation per screen instance. The NEXT ROUND / END GAME
  /// button stays tappable for a moment while the route transition plays;
  /// a double-tap used to run nextRound() twice, skipping a round and
  /// re-dealing roles mid-flow.
  bool _continueHandled = false;

  // Multiplayer variables
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _particlesController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    
    // Pulsing animation for waiting state in multiplayer
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Listen to network stream in multiplayer mode
    final networkService = ref.read(networkServiceProvider);
    if (networkService.isConnected) {
      _messageSub = networkService.messageStream.listen((message) {
        if (!mounted) return;
        final type = message['type'] as String?;
        if (type == 'nextRound') {
          Navigator.of(context).pushNamed(MimicGame.wordRevealRoute);
        }
      });
    }
    
    _runTimeline();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: SystemUiOverlay.values);
    _messageSub?.cancel();
    _pulseController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  void _initializeScores() {
    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    final gameState = ref.read(gameStateProvider);
    final mimicIds = gameState.mimicIds;

    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    final Map<String, int> args = rawArgs is Map
        ? Map<String, int>.from(rawArgs.map((k, v) => MapEntry('$k', (v as num).toInt())))
        : <String, int>{};
    final voteCounts = widget.voteCounts ?? args;

    final maxVotes = voteCounts.values.isEmpty
        ? 0 : voteCounts.values.reduce((a, b) => a > b ? a : b);
    final topPlayers = voteCounts.entries
        .where((e) => maxVotes > 0 && e.value == maxVotes)
        .map((e) => e.key).toList();
    final bool isDeadlock = topPlayers.length != 1; // tie OR no votes
    _accusedPlayerId = isDeadlock ? '' : topPlayers.first;

    // F31: this method's side effects (elimination, score award, outcome
    // record) must run exactly once per round. This screen is pushed, not
    // replaced, so re-entering it on the same votes replays the method on a
    // fresh instance. Previously that replay re-toggled the Survival
    // elimination — REVIVING the player the table had voted out, who could
    // then be dealt the Mimic next round. If this round's outcome is already
    // on record, we are that replay: rebuild the display flags from the
    // record and touch nothing.
    final recordedOutcomes = gameState.roundOutcomes
        .where((o) => o.round == gameState.currentRound)
        .toList();
    if (recordedOutcomes.isNotEmpty) {
      final outcome = recordedOutcomes.first;
      _accusedPlayerId = outcome.accusedPlayerId ?? '';
      _mimicWasCaught =
          _accusedPlayerId.isNotEmpty && mimicIds.contains(_accusedPlayerId);
      return;
    }

    if (_accusedPlayerId.isEmpty) {
      gameStateNotifier.addRoundOutcome(RoundOutcome(
        round: gameState.currentRound,
        mimicIds: mimicIds,
        accusedPlayerId: null,
      ));
      return;
    }

    final accusedIsMimic = mimicIds.contains(_accusedPlayerId);
    _mimicWasCaught = accusedIsMimic;

    // Handle Survival Mode Elimination
    if (gameState.gameMode == GameMode.survival) {
      // F31: eliminatePlayer is idempotent and one-way. toggleEliminated
      // (the old call here) revived any already-eliminated player it was
      // handed — the root cause of voted-out Watchers turning up as Mimics.
      gameStateNotifier.eliminatePlayer(_accusedPlayerId);
    }

    // Record round outcome exactly once
    gameStateNotifier.addRoundOutcome(RoundOutcome(
      round: gameState.currentRound,
      mimicIds: mimicIds,
      accusedPlayerId: _accusedPlayerId,
    ));

    // Award scores
    if (gameState.gameMode == GameMode.nightmare) {
      if (accusedIsMimic) {
        // Non-Mimics get +2, other mimic gets +3
        for (final player in gameState.players) {
          if (!mimicIds.contains(player.id)) {
            final current = gameState.scores[player.id] ?? 0;
            gameStateNotifier.updateScore(player.id, current + 2);
          } else if (player.id != _accusedPlayerId) {
            final current = gameState.scores[player.id] ?? 0;
            gameStateNotifier.updateScore(player.id, current + 3);
          }
        }
      } else {
        // Both mimics escaped
        for (final id in mimicIds) {
          final current = gameState.scores[id] ?? 0;
          gameStateNotifier.updateScore(id, current + 3);
        }
      }
    } else {
      // Classic & Survival
      if (accusedIsMimic) {
        for (final player in gameState.players) {
          if (!mimicIds.contains(player.id)) {
            final current = gameState.scores[player.id] ?? 0;
            gameStateNotifier.updateScore(player.id, current + 2);
          }
        }
      } else {
        for (final id in mimicIds) {
          final current = gameState.scores[id] ?? 0;
          gameStateNotifier.updateScore(id, current + 3);
        }
      }
    }
  }

  void _runTimeline() {
    // Accusation (2s) -> Judgment (1.5s)
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _phase = ResultsPhase.judgment;
        });

        // Judgment (1.5s) -> Revelation
        Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _initializeScores();
            _particlesController.repeat();
            setState(() {
              _phase = ResultsPhase.revelation;
            });

            final gameState = ref.read(gameStateProvider);
            if (gameState.gameMode == GameMode.nightmare) {
              // In Nightmare mode, transition to "BUT WAIT..." after 3.5s
              Timer(const Duration(milliseconds: 3500), () {
                if (mounted) {
                  setState(() {
                    _phase = ResultsPhase.butWait;
                  });

                  // "BUT WAIT..." (1.5s) -> Revelation 2
                  Timer(const Duration(milliseconds: 1500), () {
                    if (mounted) {
                      setState(() {
                        _phase = ResultsPhase.revelation2;
                      });
                    }
                  });
                }
              });
            }
          }
        });
      }
    });
  }

  void _playAgain() {
    // F31: guard against a second continuation from this instance — the
    // button is tappable during the route transition, and a double-tap used
    // to advance the round twice.
    if (_continueHandled) return;
    _continueHandled = true;
    final networkService = ref.read(networkServiceProvider);
    if (networkService.isConnected) {
      if (networkService.role == NetworkRole.host) {
        ref.read(gameStateSyncProvider.notifier).startNextRound();
        Navigator.of(context).pushReplacementNamed(MimicGame.wordRevealRoute);
      }
    } else {
      final gameState = ref.read(gameStateProvider);
      if (gameState.isGameOver) {
        Navigator.of(context).pushReplacementNamed(MimicGame.finalStandingsRoute);
      } else {
        ref.read(gameStateProvider.notifier).nextRound();
        // F31: replace, not push. Leaving results on the stack let the owner
        // walk back into a finished verdict and re-run the round flow.
        Navigator.of(context).pushReplacementNamed(MimicGame.wordRevealRoute);
      }
    }
  }

  void _newGame() {
    final networkService = ref.read(networkServiceProvider);
    if (networkService.isConnected) {
      networkService.disconnect();
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ref.read(gameStateProvider.notifier).resetGame();
      Navigator.of(context).pushNamedAndRemoveUntil(
        MimicGame.homeRoute,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Confetti painter for correct guesses
            if (_mimicWasCaught && (_phase == ResultsPhase.revelation || _phase == ResultsPhase.revelation2))
              AnimatedBuilder(
                animation: _particlesController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: ConfettiPainter(animationValue: _particlesController.value),
                  );
                },
              ),

            // Main Phase Rendering
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: _buildPhaseView(gameState),
              ),
            ),

            // Invisible TriggerDetector overlay for vault entrance
            TriggerDetector(
              tapSequence: const [0, 0, 0],
              timeout: const Duration(seconds: 2),
              onTrigger: () {
                final net = ref.read(networkServiceProvider);
                if (isMultiplayerSessionActive(net)) return;
                // Anchor the secret entry to THIS screen — the verdict the
                // mimic is looking at — so the duress panel's RETURN TO GAME
                // resumes the finished round here instead of tearing the
                // session down to the game home. Without this the trail is
                // empty and the exit can only fall back to the root.
                SecretEntryTrail.setOrigin(MimicGame.resultsRoute);
                // Push the vault PIN ROUTE, not a bare PinScreen(): the named
                // route carries RouteGuard (web and multiplayer refusal) and
                // SecureGuard (FLAG_SECURE, so the PIN screen never lands in
                // a recents thumbnail), which a raw MaterialPageRoute skips.
                Navigator.of(context).pushNamed(MimicGame.vaultPinRoute);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseView(GameState gameState) {
    final accusedPlayer = gameState.players.firstWhere(
      (p) => p.id == _accusedPlayerId,
      orElse: () => Player(id: '', name: 'No One', color: 0xFF8B0000),
    );

    switch (_phase) {
      case ResultsPhase.accusation:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'JUDGMENT PASSED',
                style: GoogleFonts.creepster(
                  color: HorrorColors.ashGray,
                  fontSize: 20,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              // Looping glitch transitions of the accused player name
              GlitchTransition(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  accusedPlayer.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.creepster(
                    fontSize: 64,
                    color: HorrorColors.crimson,
                    letterSpacing: 3.0,
                    shadows: [
                      Shadow(
                        color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                        blurRadius: 20,
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'The crowd has spoken...',
                style: GoogleFonts.inter(
                  color: HorrorColors.ashGray,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );

      case ResultsPhase.judgment:
        return const Center(
          child: HeartbeatPulse(
            child: Icon(
              Icons.favorite,
              color: HorrorColors.bloodRed,
              size: 72,
            ),
          ),
        );

      case ResultsPhase.revelation:
        return _buildRevelationContent(gameState, accusedPlayer, isFirstReveal: true);

      case ResultsPhase.butWait:
        return Center(
          child: GlitchTransition(
            duration: const Duration(milliseconds: 300),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'BUT WAIT...',
                  style: GoogleFonts.creepster(
                    fontSize: 64,
                    color: HorrorColors.crimson,
                    letterSpacing: 3.0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'THERE IS ANOTHER...',
                  style: GoogleFonts.creepster(
                    fontSize: 24,
                    color: HorrorColors.ashGray,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );

      case ResultsPhase.revelation2:
        return _buildRevelationContent(gameState, accusedPlayer, isFirstReveal: false);
    }
  }

  Widget _buildRevelationContent(GameState gameState, Player accusedPlayer, {required bool isFirstReveal}) {
    final mimicIds = gameState.mimicIds;

    // Guard: state may be cleared (e.g. resetGame) before navigation completes.
    if (mimicIds.isEmpty) return const SizedBox.shrink();

    // In Nightmare mode, we reveal Mimic 1 in Phase 3, and Mimic 2 in Phase 5.
    // In Classic/Survival, we reveal the sole mimic in Phase 3.
    final String mimicToRevealId = (gameState.gameMode == GameMode.nightmare && !isFirstReveal)
        ? (mimicIds.length > 1 ? mimicIds[1] : mimicIds[0])
        : mimicIds[0];

    final mimicPlayer = gameState.players.firstWhere(
      (p) => p.id == mimicToRevealId,
      orElse: () => Player(id: '', name: 'The Mimic', color: 0xFF8B0000),
    );

    final isCorrect = mimicIds.contains(_accusedPlayerId);

    return Column(
      children: [
        // Revelation Title
        const SizedBox(height: 20),
        if (_accusedPlayerId.isEmpty)
          Text(
            'NO ONE WAS VOTED OUT — THE VOTE WAS A DEADLOCK',
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              color: HorrorColors.fogWhite,
              fontSize: 24,
              letterSpacing: 1.0,
            ),
          )
        else if (isCorrect)
          Text(
            'THE MIMIC HAS BEEN FOUND',
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              color: HorrorColors.bloodRed,
              fontSize: 32,
              letterSpacing: 2.0,
            ),
          )
        else
          Text(
            'THE MIMIC ESCAPES',
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              color: HorrorColors.fogWhite,
              fontSize: 32,
              letterSpacing: 2.0,
            ),
          ),
        
        const SizedBox(height: 24),

        // Mimic Identity Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: HorrorColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HorrorColors.darkRedTint),
          ),
          child: Column(
            children: [
              GlitchTransition(
                animateOnStart: !isCorrect,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: Color(mimicPlayer.color),
                  child: Text(
                    mimicPlayer.name.isNotEmpty ? mimicPlayer.name[0].toUpperCase() : '?',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.fogWhite,
                      fontSize: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mimicPlayer.name.toUpperCase(),
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 24,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'THE MIMIC',
                style: GoogleFonts.creepster(
                  color: HorrorColors.ashGray,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              // Word reveal
              Text(
                'REAL WORD: ${gameState.currentWord?.toUpperCase() ?? "UNKNOWN"}',
                style: GoogleFonts.inter(
                  color: HorrorColors.fogWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Survival Mode Status
        if (gameState.gameMode == GameMode.survival) ...[
          const SizedBox(height: 16),
          _buildSurvivalStatus(gameState),
        ],

        const SizedBox(height: 24),

        // Scoreboard
        Expanded(
          child: _buildScoreboard(gameState),
        ),

        const SizedBox(height: 16),

        // Actions
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: Consumer(
                  builder: (context, ref, _) {
                    final networkService = ref.watch(networkServiceProvider);
                    if (networkService.isConnected && networkService.role != NetworkRole.host) {
                      return Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: HorrorColors.cardSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: HorrorColors.darkRedTint),
                        ),
                        child: FadeTransition(
                          opacity: _pulseAnimation,
                          child: Text(
                            'WAITING FOR HOST...',
                            style: GoogleFonts.creepster(
                              color: HorrorColors.ashGray,
                              fontSize: 14,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      );
                    }
                    return ElevatedButton(
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
                        'NEXT ROUND',
                        style: GoogleFonts.creepster(
                          fontSize: 18,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 50,
                child: Consumer(
                  builder: (context, ref, _) {
                    final isConnected = ref.watch(networkServiceProvider).isConnected;
                    return OutlinedButton(
                      onPressed: _newGame,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HorrorColors.ashGray,
                        side: const BorderSide(color: HorrorColors.ashGray, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isConnected ? 'LEAVE GAME' : 'END GAME',
                        style: GoogleFonts.creepster(
                          fontSize: 18,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSurvivalStatus(GameState gameState) {
    final survivorsCount = gameState.players.where((p) => !p.isEliminated).length;
    final deadPlayers = gameState.players.where((p) => p.isEliminated).toList();
    final accusedName = gameState.players
        .firstWhere(
          (p) => p.id == _accusedPlayerId,
          orElse: () => Player(id: '', name: '?', color: 0),
        )
        .name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: HorrorColors.deepSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HorrorColors.darkRedTint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROUND COMPLETE — $survivorsCount SURVIVORS REMAIN',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 15,
              letterSpacing: 1.0,
            ),
          ),
          // F31: name the eliminated player and say plainly whether the vote
          // landed. "ROUND COMPLETE" alone left the table guessing who was
          // gone and whether it mattered.
          if (_accusedPlayerId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '$accusedName was eliminated — '
                  '${_mimicWasCaught ? "they were the Mimic" : "they were NOT the Mimic"}.',
              style: GoogleFonts.inter(
                color: _mimicWasCaught ? HorrorColors.crimson : HorrorColors.fogWhite,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (deadPlayers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'WATCHERS (GHOSTS): ${deadPlayers.map((p) => p.name).join(", ")}',
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreboard(GameState gameState) {
    final sortedScores = gameState.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SCOREBOARD',
          style: GoogleFonts.creepster(
            color: HorrorColors.ashGray,
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
        // F31: the scoreboard's actual job in Survival was invisible — it is
        // the tiebreaker when the round cap ends the game with survivors
        // still standing. Say so, or nobody can tell what the numbers mean.
        if (gameState.gameMode == GameMode.survival)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Points are the tiebreaker: if the rounds run out, the '
                  'highest-scoring survivor wins.',
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: sortedScores.length,
            itemBuilder: (context, index) {
              final entry = sortedScores[index];
              final player = gameState.players.firstWhere(
                (p) => p.id == entry.key,
                orElse: () => Player(id: entry.key, name: 'Unknown', color: 0xFFFFFFFF),
              );
              final isMimic = gameState.mimicIds.contains(player.id);
              final isDead = player.isEliminated;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: HorrorColors.cardSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HorrorColors.darkRedTint),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(player.color),
                      radius: 16,
                      child: Text(
                        player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                        style: GoogleFonts.creepster(color: HorrorColors.fogWhite, fontSize: 16),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.name.toUpperCase(),
                            style: GoogleFonts.creepster(
                              color: isDead ? HorrorColors.ashGray : HorrorColors.fogWhite,
                              fontSize: 16,
                              decoration: isDead ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMimic) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.dangerous, color: HorrorColors.crimson, size: 16),
                        ],
                      ],
                    ),
                    trailing: GestureDetector(
                      onTap: () {
                        // Triggers the hidden vault record Tap sequence when trailing scores are clicked
                        TriggerCallbackRegistry().recordTap(0);
                      },
                      child: Text(
                        '${entry.value}',
                        style: GoogleFonts.creepster(
                          color: index == 0 ? HorrorColors.crimson : HorrorColors.fogWhite,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ConfettiPainter extends CustomPainter {
  final double animationValue;
  final math.Random _random = math.Random(42);
  
  ConfettiPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    
    // Draw 45 falling blood/crimson confetti flakes
    for (int i = 0; i < 45; i++) {
      final double speed = 0.4 + _random.nextDouble() * 0.6;
      final double startX = _random.nextDouble() * size.width;
      
      final double y = ((animationValue * size.height * speed) + (_random.nextDouble() * 300)) % size.height;
      final double x = startX + math.sin(animationValue * 2 * math.pi + i) * 20.0;
      
      final sizeFactor = 5.0 + _random.nextDouble() * 7.0;
      
      paint.color = _random.nextBool() ? HorrorColors.crimson : HorrorColors.bloodRed;
      
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: sizeFactor, height: sizeFactor),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) => true;
}