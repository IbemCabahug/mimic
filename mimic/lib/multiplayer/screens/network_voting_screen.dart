// lib/multiplayer/screens/network_voting_screen.dart
//
// Multiplayer voting screen: synchronized voting across all devices.
// The host collects all votes and broadcasts results simultaneously.
// Replaces the pass-and-play VotingScreen for multiplayer mode.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Model
// ═══════════════════════════════════════════════════════════════════════════

/// Lightweight model exposed by this screen for UI rendering.
class NetworkPlayerInfo {
  final String playerId;
  final String displayName;
  final bool isEliminated;

  const NetworkPlayerInfo({
    required this.playerId,
    required this.displayName,
    this.isEliminated = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// NetworkVotingScreen
// ═══════════════════════════════════════════════════════════════════════════

class NetworkVotingScreen extends ConsumerStatefulWidget {
  const NetworkVotingScreen({super.key});

  @override
  ConsumerState<NetworkVotingScreen> createState() =>
      _NetworkVotingScreenState();
}

class _NetworkVotingScreenState extends ConsumerState<NetworkVotingScreen>
    with TickerProviderStateMixin {
  // ─── State ──────────────────────────────────────────────────────────
  String? _myVote;
  bool _votingClosed = false;
  Map<String, int> _voteCounts = {};
  String? _eliminatedPlayerId;
  List<NetworkPlayerInfo> _players = [];

  // Host-only: collects votes from all guests
  final Map<String, String> _hostVoteCollector = {}; // voterId → targetId

  // ─── Results animation state ──────────────────────────────────────
  bool _showRoleReveal = false; // sub-reveal after 2s
  bool _showContinueButton = false; // CONTINUE after 3s

  // ─── Animation controllers ────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _revealScaleController;
  late Animation<double> _revealScaleAnimation;
  late AnimationController _revealFadeController;
  late Animation<double> _revealFadeAnimation;
  late AnimationController _barAnimationController;

  StreamSubscription<Map<String, dynamic>>? _messageSub;

  // ─── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Pulsing animation for waiting states
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Scale animation for dramatic reveal (1.5s)
    _revealScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _revealScaleAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
          parent: _revealScaleController, curve: Curves.easeOutBack),
    );

    // Fade animation for dramatic reveal (1.5s)
    _revealFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _revealFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _revealFadeController, curve: Curves.easeIn),
    );

    // Bar animation controller for vote count bars
    _barAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Build initial player list from sync state
    _refreshPlayerList();

    // Listen for network messages
    final networkService = ref.read(networkServiceProvider);
    _messageSub = networkService.messageStream.listen(_handleMessage);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _pulseController.dispose();
    _revealScaleController.dispose();
    _revealFadeController.dispose();
    _barAnimationController.dispose();
    super.dispose();
  }

  // ─── Player list from sync state ──────────────────────────────────

  void _refreshPlayerList() {
    final syncState = ref.read(gameStateSyncProvider);
    final gameState = ref.read(gameStateProvider);

    _players = gameState.players.map((p) {
      final syncPlayer = syncState.players[p.id];
      return NetworkPlayerInfo(
        playerId: p.id,
        displayName: syncPlayer?.displayName ?? p.name,
        isEliminated: p.isEliminated,
      );
    }).toList();
  }

  // ─── My own player ID ─────────────────────────────────────────────

  String get _myPlayerId {
    final networkService = ref.read(networkServiceProvider);
    if (networkService.role == NetworkRole.host) return 'host';
    return networkService.assignedPlayerId ?? '';
  }

  bool get _isHost =>
      ref.read(networkServiceProvider).role == NetworkRole.host;

  // ─── Network message handler ──────────────────────────────────────

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;

    final type = message['type'] as String?;
    switch (type) {
      case 'voteResults':
        _onVoteResults(message);
        break;
      case 'gameOver':
        _onGameOver(message);
        break;
      case 'nextRound':
        _onNextRound();
        break;
      case 'castVote':
        // Host-only: collect incoming votes from guests
        if (_isHost) {
          _onHostReceiveVote(message);
        }
        break;
    }
  }

  void _onVoteResults(Map<String, dynamic> message) {
    final rawCounts = message['counts'] as Map<String, dynamic>? ?? {};
    final eliminated = message['eliminated'] as String?;

    setState(() {
      _voteCounts = rawCounts.map((k, v) => MapEntry(k, (v as num).toInt()));
      _eliminatedPlayerId = eliminated;
      _votingClosed = true;
    });

    // Trigger dramatic reveal animations
    _revealScaleController.forward();
    _revealFadeController.forward();
    _barAnimationController.forward();

    // Sub-reveal after 2s: show if eliminated was Mimic or not
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showRoleReveal = true;
        });
      }
    });

    // CONTINUE button after 3s
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showContinueButton = true;
        });
      }
    });
  }

  void _onGameOver(Map<String, dynamic> message) {
    if (!mounted) return;
    // Navigate to the results screen with vote counts
    Navigator.of(context).pushReplacementNamed(
      MimicGame.resultsRoute,
      arguments: _voteCounts,
    );
  }

  void _onNextRound() {
    if (!mounted) return;
    // Navigate back to the word reveal screen for the next round
    Navigator.of(context).pushReplacementNamed(MimicGame.wordRevealRoute);
  }

  // ─── Host-only: vote collection ───────────────────────────────────

  void _onHostReceiveVote(Map<String, dynamic> message) {
    final voterId =
        message['voterId'] as String? ?? message['senderId'] as String? ?? '';
    final targetId = message['targetId'] as String? ?? '';
    if (voterId.isEmpty || targetId.isEmpty) return;

    _hostVoteCollector[voterId] = targetId;

    // Check if all non-eliminated players have voted
    final alivePlayers = _players.where((p) => !p.isEliminated).toList();
    if (_hostVoteCollector.length >= alivePlayers.length) {
      _hostTallyAndBroadcast();
    }
  }

  void _hostTallyAndBroadcast() {
    // Tally votes
    final counts = <String, int>{};
    for (final targetId in _hostVoteCollector.values) {
      counts[targetId] = (counts[targetId] ?? 0) + 1;
    }

    // Find the player with the most votes
    String eliminatedId = '';
    int maxVotes = 0;
    for (final entry in counts.entries) {
      if (entry.value > maxVotes) {
        maxVotes = entry.value;
        eliminatedId = entry.key;
      }
    }

    // Eliminate the player in game state
    if (eliminatedId.isNotEmpty) {
      ref.read(gameStateProvider.notifier).eliminatePlayer(eliminatedId);
    }

    // Broadcast results to all players (including self via local handler)
    final networkService = ref.read(networkServiceProvider);
    final resultsMessage = {
      'type': 'voteResults',
      'counts': counts,
      'eliminated': eliminatedId,
    };
    networkService.send(resultsMessage);

    // Also process locally for the host
    _onVoteResults(resultsMessage);
  }

  // ─── User actions ─────────────────────────────────────────────────

  void _castVote(String targetId) {
    if (_myVote != null) return;

    setState(() {
      _myVote = targetId;
    });

    final networkService = ref.read(networkServiceProvider);
    final voteMessage = {
      'type': 'castVote',
      'voterId': _myPlayerId,
      'targetId': targetId,
    };

    if (_isHost) {
      // Host processes its own vote locally
      _onHostReceiveVote(voteMessage);
    } else {
      // Guest sends vote to host
      networkService.send(voteMessage);
    }
  }

  void _onContinue() {
    if (!_isHost) return; // Only host decides what's next

    final gameState = ref.read(gameStateProvider);
    final networkService = ref.read(networkServiceProvider);

    // Check win condition: is the game over?
    final mimicEliminated = _eliminatedPlayerId != null &&
        gameState.mimicIds.contains(_eliminatedPlayerId);
    final alivePlayers =
        gameState.players.where((p) => !p.isEliminated).toList();
    final aliveNonMimics = alivePlayers
        .where((p) => !gameState.mimicIds.contains(p.id))
        .toList();

    // Game ends if:
    // 1. The mimic was eliminated (villagers win), OR
    // 2. Only mimics remain among alive players (mimic wins), OR
    // 3. Max rounds reached in survival mode
    final mimicWins = aliveNonMimics.isEmpty;
    final villagersWin = mimicEliminated;
    final maxRoundsReached = gameState.gameMode == GameMode.survival &&
        gameState.currentRound >= gameState.maxRounds - 1;

    if (villagersWin || mimicWins || maxRoundsReached) {
      final winner = villagersWin ? 'villagers' : 'mimic';
      final gameOverMsg = {
        'type': 'gameOver',
        'winner': winner,
      };
      networkService.send(gameOverMsg);
      _onGameOver(gameOverMsg);
    } else {
      // Next round
      ref.read(gameStateSyncProvider.notifier).startNextRound();
      _onNextRound();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch sync state for live player updates
    ref.watch(gameStateSyncProvider);

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: SafeArea(
          child: _votingClosed ? _buildResultsStage() : _buildVotingStage(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 1 — Voting open
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildVotingStage() {
    if (_myVote != null) {
      return _buildWaitingForOthers();
    }
    return _buildVoteSelection();
  }

  Widget _buildVoteSelection() {
    final alivePlayers = _players
        .where((p) => !p.isEliminated && p.playerId != _myPlayerId)
        .toList();

    return Column(
      children: [
        const SizedBox(height: 24),
        // Header: blood-drip styled title
        FlickerWidget(
          child: Text(
            'WHO IS THE MIMIC?',
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              fontSize: 36,
              color: HorrorColors.crimson,
              letterSpacing: 2.0,
              shadows: [
                Shadow(
                  color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Vote carefully. One wrong move and the Mimic wins.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: HorrorColors.ashGray,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Player vote grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.95,
            ),
            itemCount: alivePlayers.length,
            itemBuilder: (context, index) {
              final player = alivePlayers[index];
              return _VoteCard(
                player: player,
                onTap: () => _castVote(player.playerId),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingForOthers() {
    // Find the name of who the player voted for
    final votedFor = _players
        .where((p) => p.playerId == _myVote)
        .map((p) => p.displayName)
        .firstOrNull;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.how_to_vote,
              color: HorrorColors.crimson,
              size: 56,
            ),
            const SizedBox(height: 24),
            Text(
              'VOTE CAST',
              style: GoogleFonts.creepster(
                fontSize: 32,
                color: HorrorColors.crimson,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            if (votedFor != null)
              Text(
                'You voted for ${votedFor.toUpperCase()}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: HorrorColors.ashGray,
                  fontWeight: FontWeight.w400,
                ),
              ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: _pulseAnimation,
              child: Text(
                'Waiting for others…',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  color: HorrorColors.fogWhite,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            HeartbeatPulse(
              child: Icon(
                Icons.favorite,
                color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 2 — Results received (dramatic reveal)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildResultsStage() {
    final gameState = ref.read(gameStateProvider);
    final eliminatedPlayer = _players
        .where((p) => p.playerId == _eliminatedPlayerId)
        .firstOrNull;
    final eliminatedName =
        eliminatedPlayer?.displayName.toUpperCase() ?? 'UNKNOWN';
    final wasMimic = _eliminatedPlayerId != null &&
        gameState.mimicIds.contains(_eliminatedPlayerId);

    return ScaleTransition(
      scale: _revealScaleAnimation,
      child: FadeTransition(
        opacity: _revealFadeAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Title
              Text(
                'JUDGMENT',
                style: GoogleFonts.creepster(
                  fontSize: 20,
                  color: HorrorColors.ashGray,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 16),

              // Eliminated player name
              GlitchTransition(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  eliminatedName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.creepster(
                    fontSize: 44,
                    color: HorrorColors.crimson,
                    letterSpacing: 3.0,
                    shadows: [
                      Shadow(
                        color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'has been eliminated!',
                style: GoogleFonts.creepster(
                  fontSize: 18,
                  color: HorrorColors.ashGray,
                  letterSpacing: 1.0,
                ),
              ),

              const SizedBox(height: 24),

              // Animated vote count bars
              Expanded(
                child: _buildVoteCountBars(),
              ),

              // Sub-reveal: was the eliminated player the Mimic?
              if (_showRoleReveal) ...[
                const SizedBox(height: 16),
                _buildRoleReveal(wasMimic),
              ],

              // CONTINUE button (host only, after 3s)
              if (_showContinueButton) ...[
                const SizedBox(height: 20),
                _buildContinueButton(),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoteCountBars() {
    // Sort by vote count descending
    final sortedEntries = _voteCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sortedEntries.isNotEmpty
        ? sortedEntries.first.value.toDouble()
        : 1.0;

    return AnimatedBuilder(
      animation: _barAnimationController,
      builder: (context, _) {
        return ListView.separated(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: sortedEntries.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = sortedEntries[index];
            final player = _players
                .where((p) => p.playerId == entry.key)
                .firstOrNull;
            final name = player?.displayName.toUpperCase() ?? 'UNKNOWN';
            final isEliminated = entry.key == _eliminatedPlayerId;
            final fraction = maxCount > 0
                ? (entry.value / maxCount) * _barAnimationController.value
                : 0.0;

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: HorrorColors.cardSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEliminated
                      ? HorrorColors.crimson
                      : HorrorColors.darkRedTint,
                  width: isEliminated ? 2.0 : 1.0,
                ),
                boxShadow: isEliminated
                    ? [
                        BoxShadow(
                          color: HorrorColors.crimson.withValues(alpha: 0.25),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.creepster(
                            fontSize: 16,
                            color: isEliminated
                                ? HorrorColors.crimson
                                : HorrorColors.fogWhite,
                            letterSpacing: 1.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${entry.value} ${entry.value == 1 ? "vote" : "votes"}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: HorrorColors.ashGray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Animated bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor:
                            HorrorColors.deepSurface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isEliminated
                              ? HorrorColors.crimson
                              : HorrorColors.bloodRed,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoleReveal(bool wasMimic) {
    return GlitchTransition(
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: HorrorColors.deepSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: wasMimic
                ? const Color(0xFF2E7D32) // green tint
                : HorrorColors.crimson,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: wasMimic
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.2)
                  : HorrorColors.crimson.withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            if (wasMimic) ...[
              HeartbeatPulse(
                enabled: false, // static, green glow is the effect
                child: Text(
                  'THE MIMIC IS DEFEATED.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.creepster(
                    fontSize: 24,
                    color: const Color(0xFF4CAF50),
                    letterSpacing: 2.0,
                    shadows: [
                      Shadow(
                        color:
                            const Color(0xFF4CAF50).withValues(alpha: 0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The villagers are safe… for now.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: HorrorColors.ashGray,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              HeartbeatPulse(
                child: Text(
                  'THE MIMIC ESCAPES.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.creepster(
                    fontSize: 24,
                    color: HorrorColors.crimson,
                    letterSpacing: 2.0,
                    shadows: [
                      Shadow(
                        color: HorrorColors.crimson.withValues(alpha: 0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'An innocent has fallen. The hunt continues…',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: HorrorColors.ashGray,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 3 — CONTINUE button
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildContinueButton() {
    if (_isHost) {
      return SizedBox(
        width: 220,
        height: 56,
        child: ElevatedButton(
          onPressed: _onContinue,
          style: ElevatedButton.styleFrom(
            backgroundColor: HorrorColors.crimson,
            foregroundColor: HorrorColors.fogWhite,
            side: const BorderSide(
                color: HorrorColors.bloodRed, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 6,
            shadowColor: HorrorColors.crimson.withValues(alpha: 0.4),
          ),
          child: Text(
            'CONTINUE',
            style: GoogleFonts.creepster(
              fontSize: 22,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // Guests see a waiting message
    return FadeTransition(
      opacity: _pulseAnimation,
      child: Text(
        'Waiting for host…',
        style: GoogleFonts.inter(
          fontSize: 16,
          color: HorrorColors.ashGray,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VoteCard Widget
// ═══════════════════════════════════════════════════════════════════════════

class _VoteCard extends StatefulWidget {
  final NetworkPlayerInfo player;
  final VoidCallback onTap;

  const _VoteCard({
    required this.player,
    required this.onTap,
  });

  @override
  State<_VoteCard> createState() => _VoteCardState();
}

class _VoteCardState extends State<_VoteCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _pressController.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // Deterministic color from player ID hash
    final colorSeed = widget.player.playerId.hashCode;
    final playerColor = _playerColors[colorSeed.abs() % _playerColors.length];

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: HorrorColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: HorrorColors.darkRedTint,
              width: 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 28,
                  backgroundColor: playerColor,
                  child: Text(
                    widget.player.displayName.isNotEmpty
                        ? widget.player.displayName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.fogWhite,
                      fontSize: 24,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Player name
                Text(
                  widget.player.displayName.toUpperCase(),
                  style: GoogleFonts.creepster(
                    fontSize: 16,
                    color: HorrorColors.fogWhite,
                    letterSpacing: 1.0,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // Suspicion icon + "TAP TO VOTE"
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_search,
                      color: HorrorColors.ashGray.withValues(alpha: 0.7),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TAP TO VOTE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: HorrorColors.ashGray,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Player avatar color palette ────────────────────────────────────
const List<Color> _playerColors = [
  Color(0xFF8B0000), // bloodRed
  Color(0xFFC41E3A), // crimson
  Color(0xFF4A0E17), // deep wine
  Color(0xFF7D1C1C), // rust red
  Color(0xFF5C0632), // dark magenta
  Color(0xFF360000), // near black red
  Color(0xFFB22222), // firebrick red
  Color(0xFF800000), // maroon
];
