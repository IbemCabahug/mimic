// lib/game/screens/player_profile_screen.dart
//
// Displays player stats, rank tier, avatar, and lifetime performance.
// Accessible from the home screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/models/player_profile.dart';
import 'package:mimic/game/services/stats_service.dart';

class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key});

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  bool _isCreating = false;
  final _nameController = TextEditingController();
  HorrorAvatar _selectedAvatar = HorrorAvatar.skull;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsServiceProvider);
    final profile = stats.activeProfile;

    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: SafeArea(
          child: profile == null
              ? _buildCreateProfile(stats)
              : _buildProfileView(profile, stats),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Create Profile View
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildCreateProfile(StatsService stats) {
    return GlitchTransition(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 40),
            HeartbeatPulse(
              child: Text(
                'CREATE YOUR\nIDENTITY',
                textAlign: TextAlign.center,
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 36,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Avatar picker
            Text(
              'CHOOSE YOUR MASK',
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 12,
                letterSpacing: 3.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildAvatarPicker(stats, null),
            const SizedBox(height: 32),

            // Name input
            Container(
              decoration: BoxDecoration(
                color: HorrorColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: HorrorColors.crimson.withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _nameController,
                style: GoogleFonts.inter(
                  color: HorrorColors.fogWhite,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Enter your name...',
                  hintStyle: GoogleFonts.inter(
                    color: HorrorColors.ashGray.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Create button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating ? null : () => _createProfile(stats),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HorrorColors.crimson,
                  foregroundColor: HorrorColors.fogWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _isCreating ? 'CREATING...' : 'BECOME',
                  style: GoogleFonts.creepster(
                    fontSize: 22,
                    letterSpacing: 3.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(StatsService stats, PlayerProfile? profile) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: HorrorAvatar.values.map((avatar) {
        final isSelected = profile != null ? profile.avatar == avatar : avatar == _selectedAvatar;
        final isUnlocked = profile != null ? profile.isAvatarUnlocked(avatar) : true; // all unlocked during create? Or locked?
        // Wait, during create, new profiles default to skull, so maybe they can only pick skull/ghost?
        // Actually, during create, they have 0 points, so only skull/ghost are unlocked anyway.
        final reallyUnlocked = profile != null ? isUnlocked : (avatar == HorrorAvatar.skull || avatar == HorrorAvatar.ghost);

        return GestureDetector(
          onTap: () {
            if (!reallyUnlocked) return;
            if (profile != null) {
              stats.saveProfile(profile.copyWith(avatar: avatar));
            } else {
              setState(() => _selectedAvatar = avatar);
            }
          },
          child: Opacity(
            opacity: reallyUnlocked ? 1.0 : 0.5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? HorrorColors.crimson.withValues(alpha: 0.3)
                    : HorrorColors.cardSurface,
                border: Border.all(
                  color: isSelected
                      ? HorrorColors.crimson
                      : HorrorColors.ashGray.withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: HorrorColors.crimson.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: reallyUnlocked 
                  ? Text(avatar.emoji, style: const TextStyle(fontSize: 24))
                  : Tooltip(
                      message: _getUnlockCondition(avatar),
                      child: const Icon(Icons.lock, color: HorrorColors.ashGray, size: 20),
                    ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getUnlockCondition(HorrorAvatar avatar) {
    switch (avatar) {
      case HorrorAvatar.skull:
      case HorrorAvatar.ghost:
        return 'Default';
      case HorrorAvatar.eye:
      case HorrorAvatar.spider:
        return 'Reach Suspect';
      case HorrorAvatar.bat:
      case HorrorAvatar.moon:
        return 'Reach Investigator';
      case HorrorAvatar.coffin:
      case HorrorAvatar.potion:
        return 'Reach Phantom';
      case HorrorAvatar.dagger:
      case HorrorAvatar.mask:
        return 'Reach The Original';
    }
  }

  Widget _buildTitleSelector(StatsService stats, PlayerProfile profile) {
    final activeTitle = profile.selectedTitle ?? profile.unlockedTitles.last.title;
    
    return Column(
      children: RankTier.values.map((tier) {
        final isUnlocked = profile.suspicionScore >= tier.minScore;
        final isSelected = activeTitle == tier.title;

        return GestureDetector(
          onTap: () {
            if (!isUnlocked) return;
            stats.saveProfile(profile.copyWith(selectedTitle: tier.title));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected 
                  ? HorrorColors.crimson.withValues(alpha: 0.2)
                  : HorrorColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? HorrorColors.crimson
                    : HorrorColors.crimson.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tier.title,
                    style: GoogleFonts.inter(
                      color: isUnlocked ? HorrorColors.fogWhite : HorrorColors.ashGray.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (!isUnlocked)
                  Row(
                    children: [
                      const Icon(Icons.lock, color: HorrorColors.ashGray, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Reach ${tier.displayName}',
                        style: GoogleFonts.inter(
                          color: HorrorColors.ashGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  )
                else if (isSelected)
                  const Icon(Icons.check, color: HorrorColors.crimson, size: 18),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _createProfile(StatsService stats) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    await stats.createProfile(
      displayName: name,
      avatar: _selectedAvatar,
    );
    setState(() => _isCreating = false);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Profile View
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildProfileView(PlayerProfile profile, StatsService stats) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTopBar(),
          const SizedBox(height: 16),

          // Avatar + Name + Rank
          _buildProfileHeader(profile),
          const SizedBox(height: 24),

          // Rank Progress
          _buildRankProgress(profile),
          const SizedBox(height: 24),

          // Avatar Picker (Cosmetics)
          Text(
            'COSMETICS',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 18,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildAvatarPicker(stats, profile),
          ),
          const SizedBox(height: 24),

          // Title Selector
          Text(
            'TITLE',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 18,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildTitleSelector(stats, profile),
          ),
          const SizedBox(height: 32),

          // Stats Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildStatsGrid(profile),
          ),
          const SizedBox(height: 24),

          // Performance Breakdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildPerformanceCard(profile),
          ),
          const SizedBox(height: 24),

          // Badges Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildBadgesGrid(profile),
          ),
          const SizedBox(height: 24),

          // Leaderboard rank
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildLeaderboardRank(profile, stats),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.fogWhite),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'PROFILE',
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 22,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(PlayerProfile profile) {
    return Column(
      children: [
        // Avatar with animated glow
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            return Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HorrorColors.cardSurface,
                border: Border.all(
                  color: profile.rank.color,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: profile.rank.color.withValues(alpha: _glowAnimation.value),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  profile.avatar.emoji,
                  style: const TextStyle(fontSize: 44),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        // Name
        Text(
          profile.displayName,
          style: GoogleFonts.creepster(
            color: HorrorColors.fogWhite,
            fontSize: 28,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 8),

        // Rank badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: profile.rank.color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: profile.rank.color.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(profile.rank.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                profile.rank.displayName.toUpperCase(),
                style: GoogleFonts.inter(
                  color: profile.rank.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Suspicion Score & Active Title
        Text(
          '${profile.suspicionScore} POINTS',
          style: GoogleFonts.inter(
            color: HorrorColors.ashGray,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '"${profile.selectedTitle ?? profile.unlockedTitles.last.title}"',
          style: GoogleFonts.inter(
            color: HorrorColors.fogWhite.withValues(alpha: 0.8),
            fontSize: 14,
            fontStyle: FontStyle.italic,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildRankProgress(PlayerProfile profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: profile.rankProgress,
              minHeight: 6,
              backgroundColor: HorrorColors.cardSurface,
              valueColor: AlwaysStoppedAnimation<Color>(profile.rank.color),
            ),
          ),
          const SizedBox(height: 8),

          // Progress label
          if (profile.rank != RankTier.theOriginal)
            Text(
              '${profile.pointsToNextRank} points to next rank',
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 12,
              ),
            )
          else
            Text(
              'MAX RANK ACHIEVED',
              style: GoogleFonts.inter(
                color: profile.rank.color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(PlayerProfile profile) {
    return Column(
      children: [
        Row(
          children: [
            _buildStatTile('Games\nPlayed', '${profile.gamesPlayed}'),
            const SizedBox(width: 12),
            _buildStatTile('Games\nWon', '${profile.gamesWon}'),
            const SizedBox(width: 12),
            _buildStatTile('Win\nRate', '${profile.winRate.toStringAsFixed(0)}%'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatTile('Times\nMimic', '${profile.timesMimic}'),
            const SizedBox(width: 12),
            _buildStatTile('Mimic\nWins', '${profile.timesMimicWon}'),
            const SizedBox(width: 12),
            _buildStatTile('Correct\nID', '${profile.correctIdentifications}'),
          ],
        ),
      ],
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HorrorColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: HorrorColors.crimson.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: HorrorColors.ashGray,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceCard(PlayerProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HorrorColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERFORMANCE',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 18,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildPerformanceRow(
            'Mimic Win Rate',
            '${profile.mimicWinRate.toStringAsFixed(0)}%',
          ),
          _buildPerformanceRow(
            'Rounds Survived',
            '${profile.roundsSurvivedInnocent}',
          ),
          _buildPerformanceRow(
            'First Accusations',
            '${profile.firstAccusations}',
          ),
          _buildPerformanceRow(
            'Wrongly Eliminated',
            '${profile.timesVotedOutInnocent}',
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: HorrorColors.fogWhite.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: HorrorColors.crimson,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesGrid(PlayerProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BADGES',
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 18,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: ProfileBadge.values.length,
          itemBuilder: (context, index) {
            final badge = ProfileBadge.values[index];
            final hasBadge = profile.hasBadge(badge);

            return Tooltip(
              message: hasBadge ? badge.label : '${badge.label}\n(${_getBadgeUnlockCondition(badge)})',
              textAlign: TextAlign.center,
              child: Container(
                decoration: BoxDecoration(
                  color: hasBadge 
                      ? HorrorColors.crimson.withValues(alpha: 0.15) 
                      : HorrorColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasBadge
                        ? HorrorColors.crimson.withValues(alpha: 0.5)
                        : HorrorColors.ashGray.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getBadgeIcon(badge),
                      size: 32,
                      color: hasBadge ? HorrorColors.crimson : HorrorColors.ashGray.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        badge.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: hasBadge ? HorrorColors.fogWhite : HorrorColors.ashGray.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: hasBadge ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _getBadgeIcon(ProfileBadge badge) {
    switch (badge) {
      case ProfileBadge.firstBlood: return Icons.bloodtype;
      case ProfileBadge.masterMimic: return Icons.theater_comedy;
      case ProfileBadge.sharpEye: return Icons.visibility;
      case ProfileBadge.survivor: return Icons.shield;
      case ProfileBadge.quickDraw: return Icons.flash_on;
      case ProfileBadge.veteran: return Icons.military_tech;
    }
  }

  String _getBadgeUnlockCondition(ProfileBadge badge) {
    switch (badge) {
      case ProfileBadge.firstBlood: return 'Win 1 Game';
      case ProfileBadge.masterMimic: return 'Win as Mimic 10 Times';
      case ProfileBadge.sharpEye: return 'Correct ID 25 Times';
      case ProfileBadge.survivor: return 'Survive 50 Rounds';
      case ProfileBadge.quickDraw: return '10 First Accusations';
      case ProfileBadge.veteran: return 'Play 50 Games';
    }
  }

  Widget _buildLeaderboardRank(PlayerProfile profile, StatsService stats) {
    final rank = stats.getRankPosition(profile.id);
    final total = stats.profiles.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HorrorColors.bloodRed.withValues(alpha: 0.2),
            HorrorColors.cardSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HorrorColors.bloodRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HorrorColors.bloodRed.withValues(alpha: 0.3),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEADERBOARD RANK',
                  style: GoogleFonts.inter(
                    color: HorrorColors.ashGray,
                    fontSize: 11,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rank $rank of $total players',
                  style: GoogleFonts.inter(
                    color: HorrorColors.fogWhite,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
