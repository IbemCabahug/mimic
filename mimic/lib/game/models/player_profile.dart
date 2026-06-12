// lib/game/models/player_profile.dart
//
// Player profile data model with persistent stats, Suspicion Score tracking,
// rank tiers, and horror avatar assignments.
//
// Used by StatsService for persistence and by the profile/leaderboard screens
// for display.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Rank Tiers
// ═══════════════════════════════════════════════════════════════════════════

/// Rank tiers based on cumulative Suspicion Score.
enum RankTier {
  bystander,
  suspect,
  investigator,
  phantom,
  theOriginal,
}

extension RankTierTitle on RankTier {
  String get title {
    switch (this) {
      case RankTier.bystander:
        return "Newcomer";
      case RankTier.suspect:
        return "Suspicious Mind";
      case RankTier.investigator:
        return "The Detective";
      case RankTier.phantom:
        return "Shadow";
      case RankTier.theOriginal:
        return "The Original";
    }
  }
}

/// Extension to provide display metadata for each rank tier.
extension RankTierDisplay on RankTier {
  String get displayName {
    switch (this) {
      case RankTier.bystander:
        return 'Bystander';
      case RankTier.suspect:
        return 'Suspect';
      case RankTier.investigator:
        return 'Investigator';
      case RankTier.phantom:
        return 'Phantom';
      case RankTier.theOriginal:
        return 'The Original';
    }
  }

  String get emoji {
    switch (this) {
      case RankTier.bystander:
        return '🩶';
      case RankTier.suspect:
        return '🟢';
      case RankTier.investigator:
        return '🔵';
      case RankTier.phantom:
        return '🟣';
      case RankTier.theOriginal:
        return '🔴';
    }
  }

  Color get color {
    switch (this) {
      case RankTier.bystander:
        return const Color(0xFF9CA3AF);
      case RankTier.suspect:
        return const Color(0xFF22C55E);
      case RankTier.investigator:
        return const Color(0xFF3B82F6);
      case RankTier.phantom:
        return const Color(0xFF8B5CF6);
      case RankTier.theOriginal:
        return const Color(0xFFDC2626);
    }
  }

  /// Minimum score required to reach this tier.
  int get minScore {
    switch (this) {
      case RankTier.bystander:
        return 0;
      case RankTier.suspect:
        return 500;
      case RankTier.investigator:
        return 1500;
      case RankTier.phantom:
        return 3000;
      case RankTier.theOriginal:
        return 6000;
    }
  }

  /// Maximum score for this tier (exclusive). Returns -1 for the highest tier.
  int get maxScore {
    switch (this) {
      case RankTier.bystander:
        return 499;
      case RankTier.suspect:
        return 1499;
      case RankTier.investigator:
        return 2999;
      case RankTier.phantom:
        return 5999;
      case RankTier.theOriginal:
        return -1; // No cap
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Horror Avatars
// ═══════════════════════════════════════════════════════════════════════════

/// Available horror-themed avatar icons for player profiles.
enum HorrorAvatar {
  skull,
  ghost,
  eye,
  spider,
  bat,
  moon,
  coffin,
  potion,
  dagger,
  mask,
}

extension HorrorAvatarDisplay on HorrorAvatar {
  String get emoji {
    switch (this) {
      case HorrorAvatar.skull:
        return '💀';
      case HorrorAvatar.ghost:
        return '👻';
      case HorrorAvatar.eye:
        return '👁️';
      case HorrorAvatar.spider:
        return '🕷️';
      case HorrorAvatar.bat:
        return '🦇';
      case HorrorAvatar.moon:
        return '🌙';
      case HorrorAvatar.coffin:
        return '⚰️';
      case HorrorAvatar.potion:
        return '🧪';
      case HorrorAvatar.dagger:
        return '🗡️';
      case HorrorAvatar.mask:
        return '🎭';
    }
  }

  String get displayName {
    switch (this) {
      case HorrorAvatar.skull:
        return 'Skull';
      case HorrorAvatar.ghost:
        return 'Ghost';
      case HorrorAvatar.eye:
        return 'All-Seeing Eye';
      case HorrorAvatar.spider:
        return 'Spider';
      case HorrorAvatar.bat:
        return 'Bat';
      case HorrorAvatar.moon:
        return 'Blood Moon';
      case HorrorAvatar.coffin:
        return 'Coffin';
      case HorrorAvatar.potion:
        return 'Potion';
      case HorrorAvatar.dagger:
        return 'Dagger';
      case HorrorAvatar.mask:
        return 'Mask';
    }
  }

  IconData get iconData {
    // Fallback Material icons for rendering in Flutter widgets
    switch (this) {
      case HorrorAvatar.skull:
        return Icons.sentiment_very_dissatisfied;
      case HorrorAvatar.ghost:
        return Icons.blur_on;
      case HorrorAvatar.eye:
        return Icons.visibility;
      case HorrorAvatar.spider:
        return Icons.pest_control;
      case HorrorAvatar.bat:
        return Icons.nights_stay;
      case HorrorAvatar.moon:
        return Icons.dark_mode;
      case HorrorAvatar.coffin:
        return Icons.inventory_2;
      case HorrorAvatar.potion:
        return Icons.science;
      case HorrorAvatar.dagger:
        return Icons.gavel;
      case HorrorAvatar.mask:
        return Icons.theater_comedy;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Badges
// ═══════════════════════════════════════════════════════════════════════════

enum ProfileBadge {
  firstBlood,
  masterMimic,
  sharpEye,
  survivor,
  quickDraw,
  veteran,
}

extension ProfileBadgeDisplay on ProfileBadge {
  String get label {
    switch (this) {
      case ProfileBadge.firstBlood:
        return "First Blood";
      case ProfileBadge.masterMimic:
        return "Master Mimic";
      case ProfileBadge.sharpEye:
        return "Sharp Eye";
      case ProfileBadge.survivor:
        return "Survivor";
      case ProfileBadge.quickDraw:
        return "Quick Draw";
      case ProfileBadge.veteran:
        return "Veteran";
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Scoring Actions
// ═══════════════════════════════════════════════════════════════════════════

/// Point values for each scoring action.
abstract class ScoringAction {
  /// Successfully fool everyone as Mimic.
  static const int mimicFoolsEveryone = 150;

  /// Correctly identify the Mimic.
  static const int correctlyIdentifyMimic = 100;

  /// Survive round as innocent.
  static const int surviveRoundInnocent = 50;

  /// First player to correctly accuse the Mimic.
  static const int firstCorrectAccusation = 75;

  /// Mimic wins in Nightmare mode.
  static const int mimicWinsNightmare = 200;

  /// Special role used correctly.
  static const int specialRoleUsed = 50;

  /// Voted out while innocent (penalty).
  static const int votedOutInnocent = -25;

  /// Failed to vote in time (penalty).
  static const int failedToVote = -10;
}

// ═══════════════════════════════════════════════════════════════════════════
// PlayerProfile
// ═══════════════════════════════════════════════════════════════════════════

/// Persistent player profile with lifetime stats and ranking.
class PlayerProfile {
  /// Unique identifier for this profile.
  final String id;

  /// Display name chosen by the player.
  final String displayName;

  /// Selected horror avatar.
  final HorrorAvatar avatar;

  /// Selected custom title (if null, displays the highest unlocked rank title).
  final String? selectedTitle;

  /// Cumulative Suspicion Score across all games.
  final int suspicionScore;

  /// Total number of games played.
  final int gamesPlayed;

  /// Total number of games won.
  final int gamesWon;

  /// Total number of times assigned as Mimic.
  final int timesMimic;

  /// Total number of times the player successfully fooled everyone as Mimic.
  final int timesMimicWon;

  /// Total number of correct Mimic identifications.
  final int correctIdentifications;

  /// Total number of times voted out while innocent.
  final int timesVotedOutInnocent;

  /// Total number of rounds survived as innocent.
  final int roundsSurvivedInnocent;

  /// Total number of first correct accusations.
  final int firstAccusations;

  /// Timestamp of when this profile was created.
  final DateTime createdAt;

  /// Timestamp of the last game played.
  final DateTime lastPlayedAt;

  PlayerProfile({
    required this.id,
    required this.displayName,
    this.avatar = HorrorAvatar.skull,
    this.suspicionScore = 0,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.timesMimic = 0,
    this.timesMimicWon = 0,
    this.correctIdentifications = 0,
    this.timesVotedOutInnocent = 0,
    this.roundsSurvivedInnocent = 0,
    this.firstAccusations = 0,
    this.selectedTitle,
    DateTime? createdAt,
    DateTime? lastPlayedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastPlayedAt = lastPlayedAt ?? DateTime.now();

  // ─────────────────────────────────────────────────────────────────────
  // Computed properties & Cosmetics
  // ─────────────────────────────────────────────────────────────────────

  /// Determines if a specific avatar is unlocked for this profile.
  bool isAvatarUnlocked(HorrorAvatar a) {
    if (a == avatar) return true; // Currently equipped is always unlocked
    switch (a) {
      case HorrorAvatar.skull:
      case HorrorAvatar.ghost:
        return true;
      case HorrorAvatar.eye:
      case HorrorAvatar.spider:
        return suspicionScore >= RankTier.suspect.minScore;
      case HorrorAvatar.bat:
      case HorrorAvatar.moon:
        return suspicionScore >= RankTier.investigator.minScore;
      case HorrorAvatar.coffin:
      case HorrorAvatar.potion:
        return suspicionScore >= RankTier.phantom.minScore;
      case HorrorAvatar.dagger:
      case HorrorAvatar.mask:
        return suspicionScore >= RankTier.theOriginal.minScore;
    }
  }

  /// List of all rank titles the user has unlocked based on their score.
  List<RankTier> get unlockedTitles {
    return RankTier.values.where((tier) => suspicionScore >= tier.minScore).toList();
  }

  /// Checks if a badge has been earned based on profile stats.
  bool hasBadge(ProfileBadge badge) {
    switch (badge) {
      case ProfileBadge.firstBlood:
        return gamesWon >= 1;
      case ProfileBadge.masterMimic:
        return timesMimicWon >= 10;
      case ProfileBadge.sharpEye:
        return correctIdentifications >= 25;
      case ProfileBadge.survivor:
        return roundsSurvivedInnocent >= 50;
      case ProfileBadge.quickDraw:
        return firstAccusations >= 10;
      case ProfileBadge.veteran:
        return gamesPlayed >= 50;
    }
  }

  /// Current rank tier based on cumulative Suspicion Score.
  RankTier get rank {
    if (suspicionScore >= RankTier.theOriginal.minScore) {
      return RankTier.theOriginal;
    }
    if (suspicionScore >= RankTier.phantom.minScore) return RankTier.phantom;
    if (suspicionScore >= RankTier.investigator.minScore) {
      return RankTier.investigator;
    }
    if (suspicionScore >= RankTier.suspect.minScore) return RankTier.suspect;
    return RankTier.bystander;
  }

  /// Win rate as a percentage (0-100).
  double get winRate =>
      gamesPlayed > 0 ? (gamesWon / gamesPlayed) * 100 : 0.0;

  /// Mimic win rate as a percentage.
  double get mimicWinRate =>
      timesMimic > 0 ? (timesMimicWon / timesMimic) * 100 : 0.0;

  /// Progress towards the next rank tier (0.0 to 1.0).
  double get rankProgress {
    final currentRank = rank;
    if (currentRank == RankTier.theOriginal) return 1.0;

    final nextRankIndex = RankTier.values.indexOf(currentRank) + 1;
    final nextRank = RankTier.values[nextRankIndex];

    final rangeStart = currentRank.minScore;
    final rangeEnd = nextRank.minScore;
    final range = rangeEnd - rangeStart;

    if (range <= 0) return 1.0;
    return ((suspicionScore - rangeStart) / range).clamp(0.0, 1.0);
  }

  /// Points needed to reach the next rank.
  int get pointsToNextRank {
    final currentRank = rank;
    if (currentRank == RankTier.theOriginal) return 0;

    final nextRankIndex = RankTier.values.indexOf(currentRank) + 1;
    final nextRank = RankTier.values[nextRankIndex];

    return (nextRank.minScore - suspicionScore).clamp(0, 999999);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Mutation (returns new instance)
  // ─────────────────────────────────────────────────────────────────────

  PlayerProfile copyWith({
    String? displayName,
    HorrorAvatar? avatar,
    String? selectedTitle,
    bool clearTitle = false,
    int? suspicionScore,
    int? gamesPlayed,
    int? gamesWon,
    int? timesMimic,
    int? timesMimicWon,
    int? correctIdentifications,
    int? timesVotedOutInnocent,
    int? roundsSurvivedInnocent,
    int? firstAccusations,
    DateTime? lastPlayedAt,
  }) {
    return PlayerProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatar: avatar ?? this.avatar,
      selectedTitle: clearTitle ? null : (selectedTitle ?? this.selectedTitle),
      suspicionScore: suspicionScore ?? this.suspicionScore,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      gamesWon: gamesWon ?? this.gamesWon,
      timesMimic: timesMimic ?? this.timesMimic,
      timesMimicWon: timesMimicWon ?? this.timesMimicWon,
      correctIdentifications:
          correctIdentifications ?? this.correctIdentifications,
      timesVotedOutInnocent:
          timesVotedOutInnocent ?? this.timesVotedOutInnocent,
      roundsSurvivedInnocent:
          roundsSurvivedInnocent ?? this.roundsSurvivedInnocent,
      firstAccusations: firstAccusations ?? this.firstAccusations,
      createdAt: createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  /// Apply a scoring action and return updated profile.
  PlayerProfile applyScore(int points) {
    return copyWith(
      suspicionScore: (suspicionScore + points).clamp(0, 999999),
      lastPlayedAt: DateTime.now(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Serialization
  // ─────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'avatar': avatar.name,
      'selectedTitle': selectedTitle,
      'suspicionScore': suspicionScore,
      'gamesPlayed': gamesPlayed,
      'gamesWon': gamesWon,
      'timesMimic': timesMimic,
      'timesMimicWon': timesMimicWon,
      'correctIdentifications': correctIdentifications,
      'timesVotedOutInnocent': timesVotedOutInnocent,
      'roundsSurvivedInnocent': roundsSurvivedInnocent,
      'firstAccusations': firstAccusations,
      'createdAt': createdAt.toIso8601String(),
      'lastPlayedAt': lastPlayedAt.toIso8601String(),
    };
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown',
      avatar: HorrorAvatar.values.firstWhere(
        (a) => a.name == (json['avatar'] as String?),
        orElse: () => HorrorAvatar.skull,
      ),
      selectedTitle: json['selectedTitle'] as String?,
      suspicionScore: (json['suspicionScore'] as num?)?.toInt() ?? 0,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
      gamesWon: (json['gamesWon'] as num?)?.toInt() ?? 0,
      timesMimic: (json['timesMimic'] as num?)?.toInt() ?? 0,
      timesMimicWon: (json['timesMimicWon'] as num?)?.toInt() ?? 0,
      correctIdentifications:
          (json['correctIdentifications'] as num?)?.toInt() ?? 0,
      timesVotedOutInnocent:
          (json['timesVotedOutInnocent'] as num?)?.toInt() ?? 0,
      roundsSurvivedInnocent:
          (json['roundsSurvivedInnocent'] as num?)?.toInt() ?? 0,
      firstAccusations: (json['firstAccusations'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.tryParse(json['lastPlayedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
