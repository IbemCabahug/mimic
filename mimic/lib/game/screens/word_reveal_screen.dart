// lib/game/screens/word_reveal_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/widgets/suspicion_meter.dart';
import 'package:mimic/game/game.dart';

enum RevealState { cover, revealed, pass }

class WordRevealScreen extends ConsumerStatefulWidget {
  const WordRevealScreen({super.key});

  @override
  ConsumerState<WordRevealScreen> createState() => _WordRevealScreenState();
}

class _WordRevealScreenState extends ConsumerState<WordRevealScreen> {
  int _currentIndex = 0;
  RevealState _revealState = RevealState.cover;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: SystemUiOverlay.values);
    _timer?.cancel();
    super.dispose();
  }

  void _revealWord() {
    setState(() {
      _revealState = RevealState.revealed;
    });

    _timer?.cancel();
    // 3-second auto-hide timer before showing the pass device screen
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _revealState = RevealState.pass;
        });
      }
    });
  }

  void _nextPlayer() {
    _timer?.cancel();
    final gameState = ref.read(gameStateProvider);
    if (_currentIndex < gameState.players.length - 1) {
      setState(() {
        _currentIndex++;
        _revealState = RevealState.cover;
      });
    } else {
      Navigator.of(context).pushNamed(MimicGame.discussionRoute);
    }
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

    final currentPlayer = gameState.players[_currentIndex];
    // In Nightmare mode, there are 2 mimics. Check if player is one of them.
    final isMimic = gameState.mimicIds.contains(currentPlayer.id);
    
    // Retrieve player's specific word dynamically from Riverpod state
    final wordToShow = gameState.getWordForPlayer(currentPlayer.id);
    final category = gameState.currentCategory;
    final isLastPlayer = _currentIndex >= gameState.players.length - 1;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'VICTIM ${_currentIndex + 1} OF ${gameState.players.length}',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 20,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StaticOverlay(
        child: Column(
          children: [
            // Survival Mode Round Indicator
            if (gameState.gameMode == GameMode.survival)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'ROUND ${gameState.currentRound + 1}',
                  style: GoogleFonts.creepster(
                    color: HorrorColors.crimson,
                    fontSize: 22,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            
            Expanded(
              child: _buildStateContent(
                currentPlayer: currentPlayer,
                wordToShow: wordToShow,
                category: category,
                isMimic: isMimic,
                isLastPlayer: isLastPlayer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateContent({
    required Player currentPlayer,
    required String wordToShow,
    required String category,
    required bool isMimic,
    required bool isLastPlayer,
  }) {
    switch (_revealState) {
      case RevealState.cover:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _revealWord,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Color(currentPlayer.color),
                  child: Text(
                    currentPlayer.name.isNotEmpty ? currentPlayer.name[0].toUpperCase() : '?',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.fogWhite,
                      fontSize: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  currentPlayer.name.toUpperCase(),
                  style: GoogleFonts.creepster(
                    fontSize: 40,
                    color: HorrorColors.fogWhite,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 40),
                HeartbeatPulse(
                  child: Text(
                    'TAP TO SEE YOUR FATE',
                    style: GoogleFonts.creepster(
                      fontSize: 22,
                      color: HorrorColors.ashGray,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case RevealState.revealed:
        return GlitchTransition(
          duration: const Duration(milliseconds: 200),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: HorrorColors.crimson.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: HorrorColors.crimson, width: 0.8),
                  ),
                  child: Text(
                    category.toUpperCase(),
                    style: GoogleFonts.creepster(
                      fontSize: 14,
                      color: HorrorColors.crimson,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                FlickerWidget(
                  child: Text(
                    wordToShow.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.creepster(
                      fontSize: 56,
                      color: isMimic ? HorrorColors.bloodRed : HorrorColors.crimson,
                      letterSpacing: 3.0,
                      shadows: [
                        Shadow(
                          color: HorrorColors.crimson.withValues(alpha: 0.5),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isMimic)
                  Text(
                    'YOU ARE THE MIMIC',
                    style: GoogleFonts.creepster(
                      fontSize: 20,
                      color: HorrorColors.ashGray,
                      letterSpacing: 1.5,
                    ),
                  )
                else
                  Text(
                    'REMEMBER YOUR WORD',
                    style: GoogleFonts.creepster(
                      fontSize: 16,
                      color: HorrorColors.ashGray,
                      letterSpacing: 1.0,
                    ),
                  ),
              ],
            ),
          ),
        );

      case RevealState.pass:
        final nextPlayerName = _currentIndex < ref.read(gameStateProvider).players.length - 1
            ? ref.read(gameStateProvider).players[_currentIndex + 1].name
            : '';

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'PASS THE DEVICE',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.creepster(
                    fontSize: 48,
                    color: HorrorColors.ashGray,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isLastPlayer
                      ? 'Hand the device back to the group to begin discussion.'
                      : 'Hand the device to $nextPlayerName and make sure they do not see the screen.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: HorrorColors.ashGray,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 220,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _nextPlayer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HorrorColors.crimson,
                      foregroundColor: HorrorColors.fogWhite,
                      side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isLastPlayer ? 'START DISCUSSION' : 'PROCEED',
                      style: GoogleFonts.creepster(
                        fontSize: 20,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class DiscussionScreen extends ConsumerStatefulWidget {
  const DiscussionScreen({super.key});

  @override
  ConsumerState<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends ConsumerState<DiscussionScreen> {
  late Timer _timer;
  int _secondsRemaining = 90;
  bool _screenFlash = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
        
        // At 10 seconds: trigger a brief visual screen flash
        if (_secondsRemaining == 10) {
          setState(() {
            _screenFlash = true;
          });
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) {
              setState(() {
                _screenFlash = false;
              });
            }
          });
        }
      } else {
        timer.cancel();
        Navigator.of(context).pushNamed(MimicGame.votingRoute);
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge, overlays: SystemUiOverlay.values);
    _timer.cancel();
    super.dispose();
  }

  String get _timeString {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameStateProvider);
    final isLowTime = _secondsRemaining <= 30;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'DISCUSSION',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 26,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StaticOverlay(
        child: FlickerWidget(
          enabled: isLowTime, // Screen flickers when time is low
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Roster & Timer Layout
              Column(
                children: [
                  if (gameState.gameMode == GameMode.survival)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'ROUND ${gameState.currentRound + 1}',
                        style: GoogleFonts.creepster(
                          color: HorrorColors.crimson,
                          fontSize: 20,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                  
                  // Circular Progress Indicator Timer
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: _secondsRemaining / 90.0,
                            strokeWidth: 6,
                            backgroundColor: HorrorColors.cardSurface,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isLowTime ? HorrorColors.bloodRed : HorrorColors.crimson,
                            ),
                          ),
                        ),
                        // Low time heartbeat tension pulse
                        HeartbeatPulse(
                          enabled: isLowTime,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _timeString,
                                style: GoogleFonts.creepster(
                                  fontSize: 38,
                                  color: isLowTime ? HorrorColors.bloodRed : HorrorColors.fogWhite,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'REMAINING',
                                style: GoogleFonts.creepster(
                                  fontSize: 10,
                                  letterSpacing: 1.5,
                                  color: HorrorColors.ashGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Interactive Suspicion Roster
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TAP TO CAST SUSPICION (+10%)',
                            style: GoogleFonts.creepster(
                              color: HorrorColors.ashGray,
                              fontSize: 14,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: gameState.players.length,
                              itemBuilder: (context, index) {
                                final player = gameState.players[index];
                                final isDead = player.isEliminated;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: GestureDetector(
                                    onTap: isDead
                                        ? null
                                        : () {
                                            // Add +10% (0.10) suspicion on tap
                                            ref.read(gameStateProvider.notifier).updateSuspicion(
                                                  player.id,
                                                  player.suspicion + 0.10,
                                                );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: HorrorColors.cardSurface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDead ? HorrorColors.darkRedTint : HorrorColors.darkRedTint,
                                          width: 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                player.name.toUpperCase(),
                                                style: GoogleFonts.creepster(
                                                  color: isDead ? HorrorColors.ashGray : HorrorColors.fogWhite,
                                                  fontSize: 16,
                                                  letterSpacing: 1.0,
                                                  decoration: isDead ? TextDecoration.lineThrough : null,
                                                ),
                                              ),
                                              if (isDead)
                                                Text(
                                                  'DEAD',
                                                  style: GoogleFonts.creepster(
                                                    color: HorrorColors.crimson,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          SuspicionMeter(value: player.suspicion, height: 12),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Start Voting Now Button
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            _timer.cancel();
                            Navigator.of(context).pushNamed(MimicGame.votingRoute);
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
                            'START VOTING',
                            style: GoogleFonts.creepster(
                              fontSize: 20,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                ],
              ),

              // Screen flash effect container overlay
              if (_screenFlash)
                Positioned.fill(
                  child: Container(
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
