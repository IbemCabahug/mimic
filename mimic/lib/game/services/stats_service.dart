// lib/game/services/stats_service.dart
//
// Reads and writes player profile stats to local SQLite storage.
// Provides a Riverpod provider for easy access throughout the app.
//
// This is local-only — no cloud sync. Online leaderboard deferred to v2.0.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/game/models/player_profile.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds.
void _log(String message) => debugPrint('[StatsService] $message');

// ═══════════════════════════════════════════════════════════════════════════
// StatsService
// ═══════════════════════════════════════════════════════════════════════════

/// Service for persisting and retrieving player profiles and stats.
///
/// Uses SharedPreferences for cross-platform compatibility (Android, iOS, web).
/// All profiles are stored as a single JSON array under the key `_kProfilesKey`.
///
/// Usage:
/// ```dart
/// final stats = ref.read(statsServiceProvider);
/// await stats.init();
///
/// // Create or update a profile
/// await stats.saveProfile(profile);
///
/// // Get leaderboard
/// final leaderboard = stats.getLeaderboard();
/// ```
class StatsService extends ChangeNotifier {
  static const String _kProfilesKey = 'mimic_player_profiles';
  static const String _kActiveProfileKey = 'mimic_active_profile_id';

  SharedPreferences? _prefs;
  List<PlayerProfile> _profiles = [];
  String? _activeProfileId;
  bool _initialized = false;

  // ─────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// All stored player profiles.
  List<PlayerProfile> get profiles => List.unmodifiable(_profiles);

  /// The currently active player profile (the device owner).
  PlayerProfile? get activeProfile {
    if (_activeProfileId == null) return null;
    try {
      return _profiles.firstWhere((p) => p.id == _activeProfileId);
    } catch (_) {
      return null;
    }
  }

  /// The active profile's ID.
  String? get activeProfileId => _activeProfileId;

  // ─────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────

  /// Initialize the service by loading all profiles from storage.
  /// Must be called before any other operations.
  Future<void> init() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadProfiles();
      _activeProfileId = _prefs?.getString(_kActiveProfileKey);
      _initialized = true;
      _log('Initialized with ${_profiles.length} profiles');
      notifyListeners();
    } catch (e) {
      _log('Failed to initialize: $e');
      _initialized = true; // Mark as initialized even on error
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Profile CRUD
  // ─────────────────────────────────────────────────────────────────────

  /// Create a new player profile and set it as active.
  Future<PlayerProfile> createProfile({
    required String displayName,
    HorrorAvatar avatar = HorrorAvatar.skull,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final profile = PlayerProfile(
      id: id,
      displayName: displayName,
      avatar: avatar,
    );

    _profiles.add(profile);
    _activeProfileId = id;
    await _saveProfiles();
    await _prefs?.setString(_kActiveProfileKey, id);

    _log('Created profile: $displayName (id: $id)');
    notifyListeners();
    return profile;
  }

  /// Save/update an existing profile.
  Future<void> saveProfile(PlayerProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }

    await _saveProfiles();
    _log('Saved profile: ${profile.displayName}');
    notifyListeners();
  }

  /// Delete a profile by ID.
  Future<void> deleteProfile(String profileId) async {
    _profiles.removeWhere((p) => p.id == profileId);

    if (_activeProfileId == profileId) {
      _activeProfileId = _profiles.isNotEmpty ? _profiles.first.id : null;
      if (_activeProfileId != null) {
        await _prefs?.setString(_kActiveProfileKey, _activeProfileId!);
      } else {
        await _prefs?.remove(_kActiveProfileKey);
      }
    }

    await _saveProfiles();
    _log('Deleted profile: $profileId');
    notifyListeners();
  }

  /// Set the active profile by ID.
  Future<void> setActiveProfile(String profileId) async {
    if (_profiles.any((p) => p.id == profileId)) {
      _activeProfileId = profileId;
      await _prefs?.setString(_kActiveProfileKey, profileId);
      _log('Active profile set to: $profileId');
      notifyListeners();
    }
  }

  /// Get a profile by ID.
  PlayerProfile? getProfile(String profileId) {
    try {
      return _profiles.firstWhere((p) => p.id == profileId);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Stats Recording
  // ─────────────────────────────────────────────────────────────────────

  /// Record a completed game's results for the active profile.
  Future<void> recordGameResult({
    required bool won,
    required bool wasMimic,
    required bool mimicWon,
    required bool correctlyIdentified,
    required bool votedOutWhileInnocent,
    required bool firstToAccuse,
    required int roundsSurvived,
    required bool failedToVote,
  }) async {
    final profile = activeProfile;
    if (profile == null) {
      _log('No active profile — cannot record game result');
      return;
    }

    int scoreChange = 0;

    // Calculate score based on game outcome
    if (wasMimic && mimicWon) {
      scoreChange += ScoringAction.mimicFoolsEveryone;
    }
    if (correctlyIdentified) {
      scoreChange += ScoringAction.correctlyIdentifyMimic;
    }
    if (!wasMimic && !votedOutWhileInnocent) {
      scoreChange += ScoringAction.surviveRoundInnocent * roundsSurvived;
    }
    if (firstToAccuse) {
      scoreChange += ScoringAction.firstCorrectAccusation;
    }
    if (votedOutWhileInnocent) {
      scoreChange += ScoringAction.votedOutInnocent;
    }
    if (failedToVote) {
      scoreChange += ScoringAction.failedToVote;
    }

    final updatedProfile = profile.copyWith(
      suspicionScore: (profile.suspicionScore + scoreChange).clamp(0, 999999),
      gamesPlayed: profile.gamesPlayed + 1,
      gamesWon: profile.gamesWon + (won ? 1 : 0),
      timesMimic: profile.timesMimic + (wasMimic ? 1 : 0),
      timesMimicWon: profile.timesMimicWon + (wasMimic && mimicWon ? 1 : 0),
      correctIdentifications:
          profile.correctIdentifications + (correctlyIdentified ? 1 : 0),
      timesVotedOutInnocent:
          profile.timesVotedOutInnocent + (votedOutWhileInnocent ? 1 : 0),
      roundsSurvivedInnocent:
          profile.roundsSurvivedInnocent + roundsSurvived,
      firstAccusations: profile.firstAccusations + (firstToAccuse ? 1 : 0),
      lastPlayedAt: DateTime.now(),
    );

    await saveProfile(updatedProfile);
    _log('Recorded game result for ${profile.displayName}: '
        'score change=$scoreChange, new total=${updatedProfile.suspicionScore}');
  }

  /// Apply a specific scoring action to the active profile.
  Future<void> applyScoreAction(int points) async {
    final profile = activeProfile;
    if (profile == null) return;

    final updated = profile.applyScore(points);
    await saveProfile(updated);
  }

  // ─────────────────────────────────────────────────────────────────────
  // Leaderboard
  // ─────────────────────────────────────────────────────────────────────

  /// Get all profiles sorted by Suspicion Score (descending) for the leaderboard.
  List<PlayerProfile> getLeaderboard() {
    final sorted = List<PlayerProfile>.from(_profiles);
    sorted.sort((a, b) => b.suspicionScore.compareTo(a.suspicionScore));
    return sorted;
  }

  /// Get the top N profiles for the leaderboard.
  List<PlayerProfile> getTopPlayers({int limit = 10}) {
    final leaderboard = getLeaderboard();
    return leaderboard.take(limit).toList();
  }

  /// Get the rank position (1-indexed) of a specific profile.
  int getRankPosition(String profileId) {
    final leaderboard = getLeaderboard();
    final index = leaderboard.indexWhere((p) => p.id == profileId);
    return index >= 0 ? index + 1 : -1;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Persistence Helpers
  // ─────────────────────────────────────────────────────────────────────

  /// Load all profiles from SharedPreferences.
  Future<void> _loadProfiles() async {
    final jsonString = _prefs?.getString(_kProfilesKey);
    if (jsonString == null || jsonString.isEmpty) {
      _profiles = [];
      return;
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      _profiles = jsonList
          .map((j) => PlayerProfile.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('Failed to load profiles: $e');
      _profiles = [];
    }
  }

  /// Save all profiles to SharedPreferences.
  Future<void> _saveProfiles() async {
    try {
      final jsonList = _profiles.map((p) => p.toJson()).toList();
      final jsonString = json.encode(jsonList);
      await _prefs?.setString(_kProfilesKey, jsonString);
    } catch (e) {
      _log('Failed to save profiles: $e');
    }
  }

  /// Clear all stored profiles. Use with caution.
  Future<void> clearAllProfiles() async {
    _profiles.clear();
    _activeProfileId = null;
    await _prefs?.remove(_kProfilesKey);
    await _prefs?.remove(_kActiveProfileKey);
    _log('All profiles cleared');
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Riverpod Provider
// ═══════════════════════════════════════════════════════════════════════════

final statsServiceProvider = ChangeNotifierProvider<StatsService>((ref) {
  final service = StatsService();
  // Initialize asynchronously — consumers should check isInitialized
  service.init();
  return service;
});
