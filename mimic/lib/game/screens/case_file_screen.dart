// lib/game/screens/case_file_screen.dart
//
// Post-round dramatic summary screen — "The Case File".
// Shows a shareable dramatic recap of what happened in the round.
// Includes who was the Mimic, who voted correctly, key moments,
// and auto-generated roast cards.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/widgets/roast_card.dart';

class CaseFileScreen extends StatefulWidget {
  final GameState gameState;
  final Map<String, String> votes; // voterId → targetId
  final bool mimicCaught;
  final String eliminatedPlayerId;

  const CaseFileScreen({
    super.key,
    required this.gameState,
    required this.votes,
    required this.mimicCaught,
    required this.eliminatedPlayerId,
  });

  @override
  State<CaseFileScreen> createState() => _CaseFileScreenState();
}

class _CaseFileScreenState extends State<CaseFileScreen>
    with TickerProviderStateMixin {
  late AnimationController _revealController;
  late Animation<double> _revealAnimation;
  int _visibleSections = 0;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOut,
    );

    // Reveal sections one by one with dramatic timing
    _revealSections();
  }

  Future<void> _revealSections() async {
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _visibleSections = i + 1);
        _revealController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Title
                      _buildTitle(),
                      const SizedBox(height: 24),

                      // Section 1: The Verdict
                      if (_visibleSections >= 1) _buildVerdict(),
                      if (_visibleSections >= 1) const SizedBox(height: 20),

                      // Section 2: The Mimic Identity
                      if (_visibleSections >= 2) _buildMimicIdentity(),
                      if (_visibleSections >= 2) const SizedBox(height: 20),

                      // Section 3: The Vote Breakdown
                      if (_visibleSections >= 3) _buildVoteBreakdown(),
                      if (_visibleSections >= 3) const SizedBox(height: 20),

                      // Section 4: The Words
                      if (_visibleSections >= 4) _buildWordReveal(),
                      if (_visibleSections >= 4) const SizedBox(height: 20),

                      // Section 5: Roast Cards
                      if (_visibleSections >= 5) _buildRoastSection(),
                      if (_visibleSections >= 5) const SizedBox(height: 32),

                      // Close button
                      if (_visibleSections >= 5) _buildCloseButton(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: HorrorColors.fogWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'CASE FILE #${widget.gameState.currentRound + 1}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 12,
                letterSpacing: 3.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return HeartbeatPulse(
      child: Column(
        children: [
          Text(
            '📋',
            style: GoogleFonts.inter(fontSize: 48),
          ),
          const SizedBox(height: 12),
          Text(
            'CASE FILE',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 40,
              letterSpacing: 4.0,
              shadows: [
                Shadow(
                  blurRadius: 20,
                  color: HorrorColors.bloodRed.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerdict() {
    return _buildSection(
      icon: widget.mimicCaught ? Icons.check_circle : Icons.cancel,
      iconColor: widget.mimicCaught
          ? const Color(0xFF22C55E)
          : HorrorColors.crimson,
      title: widget.mimicCaught ? 'JUSTICE SERVED' : 'THE MIMIC ESCAPES',
      child: Text(
        widget.mimicCaught
            ? 'The group successfully identified and eliminated the Mimic. '
                'Trust was restored... for now.'
            : 'The Mimic deceived everyone and slipped away undetected. '
                'No one is safe.',
        style: GoogleFonts.inter(
          color: HorrorColors.fogWhite.withValues(alpha: 0.8),
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildMimicIdentity() {
    final mimicPlayers = widget.gameState.players
        .where((p) => widget.gameState.mimicIds.contains(p.id))
        .toList();

    return _buildSection(
      icon: Icons.theater_comedy,
      iconColor: HorrorColors.crimson,
      title: 'THE MIMIC${mimicPlayers.length > 1 ? "S" : ""}',
      child: Column(
        children: mimicPlayers.map((mimic) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(mimic.color).withValues(alpha: 0.3),
                    border: Border.all(
                      color: HorrorColors.crimson,
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Text('🎭', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  mimic.name,
                  style: GoogleFonts.creepster(
                    color: HorrorColors.crimson,
                    fontSize: 20,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoteBreakdown() {
    return _buildSection(
      icon: Icons.how_to_vote,
      iconColor: const Color(0xFF3B82F6),
      title: 'VOTE BREAKDOWN',
      child: Column(
        children: widget.votes.entries.map((entry) {
          final voter = _getPlayerName(entry.key);
          final target = _getPlayerName(entry.value);
          final isMimic = widget.gameState.mimicIds.contains(entry.value);

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    voter,
                    style: GoogleFonts.inter(
                      color: HorrorColors.fogWhite.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: HorrorColors.ashGray.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        target,
                        style: GoogleFonts.inter(
                          color: isMimic
                              ? const Color(0xFF22C55E)
                              : HorrorColors.fogWhite.withValues(alpha: 0.7),
                          fontSize: 14,
                          fontWeight:
                              isMimic ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      if (isMimic)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text('✓',
                              style: TextStyle(
                                  color: Color(0xFF22C55E), fontSize: 14)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWordReveal() {
    final realWord = widget.gameState.currentWordPair?.realWord ?? '???';
    final mimicWord = widget.gameState.currentWordPair?.mimicWord ?? '???';

    return _buildSection(
      icon: Icons.text_fields,
      iconColor: const Color(0xFFF59E0B),
      title: 'THE WORDS',
      child: Row(
        children: [
          Expanded(
            child: _buildWordCard('REAL WORD', realWord, const Color(0xFF22C55E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildWordCard('MIMIC WORD', mimicWord, HorrorColors.crimson),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(String label, String word, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
              letterSpacing: 2.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            word.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.creepster(
              color: color,
              fontSize: 22,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoastSection() {
    return _buildSection(
      icon: Icons.local_fire_department,
      iconColor: const Color(0xFFF97316),
      title: 'ROAST CARDS',
      child: Column(
        children: widget.gameState.players.take(4).map((player) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RoastCard(
              playerName: player.name,
              wasMimic: widget.gameState.mimicIds.contains(player.id),
              wasEliminated: player.id == widget.eliminatedPlayerId,
              votedCorrectly: widget.votes[player.id] != null &&
                  widget.gameState.mimicIds
                      .contains(widget.votes[player.id]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: _revealAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: HorrorColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: HorrorColors.crimson.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.creepster(
                    color: HorrorColors.crimson,
                    fontSize: 18,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: HorrorColors.crimson,
          foregroundColor: HorrorColors.fogWhite,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'CLOSE CASE FILE',
          style: GoogleFonts.creepster(
            fontSize: 20,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }

  String _getPlayerName(String playerId) {
    try {
      return widget.gameState.players
          .firstWhere((p) => p.id == playerId)
          .name;
    } catch (_) {
      return 'Unknown';
    }
  }
}
