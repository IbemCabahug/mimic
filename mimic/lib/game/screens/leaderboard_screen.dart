// lib/game/screens/leaderboard_screen.dart
//
// Local ranked leaderboard displaying all player profiles sorted by
// Suspicion Score. Uses the horror theme with animated rank tier badges.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/models/player_profile.dart';
import 'package:mimic/game/services/stats_service.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsServiceProvider);
    final leaderboard = stats.getLeaderboard();
    final activeId = stats.activeProfileId;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: SafeArea(
          child: Column(
            children: [
              // ── Top Bar ──
              _buildTopBar(context),
              const SizedBox(height: 8),

              // ── Title ──
              HeartbeatPulse(
                child: Text(
                  'THE RANKS',
                  style: GoogleFonts.creepster(
                    color: HorrorColors.crimson,
                    fontSize: 36,
                    letterSpacing: 3.0,
                    shadows: [
                      Shadow(
                        blurRadius: 15,
                        color: HorrorColors.bloodRed.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Suspicion Score Leaderboard',
                style: GoogleFonts.inter(
                  color: HorrorColors.ashGray,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),

              // ── Leaderboard List ──
              Expanded(
                child: leaderboard.isEmpty
                    ? _buildEmptyState()
                    : _buildLeaderboardList(leaderboard, activeId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.fogWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlickerWidget(
            child: Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: HorrorColors.ashGray.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No players yet',
            style: GoogleFonts.creepster(
              color: HorrorColors.ashGray,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a profile to start tracking\nyour Suspicion Score',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardList(
    List<PlayerProfile> leaderboard,
    String? activeId,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: leaderboard.length,
      itemBuilder: (context, index) {
        final profile = leaderboard[index];
        final isActive = profile.id == activeId;
        final rank = index + 1;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LeaderboardCard(
            profile: profile,
            rank: rank,
            isActive: isActive,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Leaderboard Card
// ═══════════════════════════════════════════════════════════════════════════

class _LeaderboardCard extends StatelessWidget {
  final PlayerProfile profile;
  final int rank;
  final bool isActive;

  const _LeaderboardCard({
    required this.profile,
    required this.rank,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? HorrorColors.crimson.withValues(alpha: 0.12)
            : HorrorColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? HorrorColors.crimson.withValues(alpha: 0.5)
              : isTop3
                  ? _getRankBorderColor(rank).withValues(alpha: 0.4)
                  : HorrorColors.cardSurface,
          width: isActive ? 2 : 1,
        ),
        boxShadow: isTop3
            ? [
                BoxShadow(
                  color: _getRankBorderColor(rank).withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 36,
            child: isTop3
                ? Text(
                    _getRankEmoji(rank),
                    style: const TextStyle(fontSize: 22),
                  )
                : Text(
                    '#$rank',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.ashGray,
                      fontSize: 18,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HorrorColors.deepSurface,
              border: Border.all(
                color: profile.rank.color.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                profile.avatar.emoji,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + Rank Tier
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: isActive
                              ? HorrorColors.fogWhite
                              : HorrorColors.fogWhite.withValues(alpha: 0.9),
                          fontSize: 15,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isActive)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: HorrorColors.crimson.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'YOU',
                            style: GoogleFonts.inter(
                              color: HorrorColors.crimson,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      profile.rank.emoji,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      profile.rank.displayName,
                      style: GoogleFonts.inter(
                        color: profile.rank.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${profile.suspicionScore}',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 20,
                ),
              ),
              Text(
                'pts',
                style: GoogleFonts.inter(
                  color: HorrorColors.ashGray,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRankBorderColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return HorrorColors.cardSurface;
    }
  }

  String _getRankEmoji(int rank) {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '#$rank';
    }
  }
}
