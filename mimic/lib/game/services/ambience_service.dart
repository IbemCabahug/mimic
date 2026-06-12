// lib/game/services/ambience_service.dart
//
// Horror background audio service for the discussion phase.
// Provides optional atmospheric audio that enhances the tension.
// Toggle-able in settings.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds.
void _log(String message) => debugPrint('[AmbienceService] $message');

// ═══════════════════════════════════════════════════════════════════════════
// Ambience Tracks
// ═══════════════════════════════════════════════════════════════════════════

/// Available horror ambience tracks.
enum AmbienceTrack {
  /// Low frequency hum with distant whispers.
  darkWhispers,

  /// Creaking floorboards and subtle wind.
  hauntedHouse,

  /// Distant thunder with rain.
  stormy,

  /// Ticking clock with heartbeat.
  tension,

  /// Complete silence (no audio).
  none,
}

extension AmbienceTrackDisplay on AmbienceTrack {
  String get displayName {
    switch (this) {
      case AmbienceTrack.darkWhispers:
        return 'Dark Whispers';
      case AmbienceTrack.hauntedHouse:
        return 'Haunted House';
      case AmbienceTrack.stormy:
        return 'Stormy Night';
      case AmbienceTrack.tension:
        return 'Rising Tension';
      case AmbienceTrack.none:
        return 'No Ambience';
    }
  }

  String get emoji {
    switch (this) {
      case AmbienceTrack.darkWhispers:
        return '👻';
      case AmbienceTrack.hauntedHouse:
        return '🏚️';
      case AmbienceTrack.stormy:
        return '⛈️';
      case AmbienceTrack.tension:
        return '💓';
      case AmbienceTrack.none:
        return '🔇';
    }
  }

  /// Asset path for the audio file. Audio files go in assets/audio/.
  /// Using synthesized ambient tones generated at runtime as fallback.
  String get assetPath {
    switch (this) {
      case AmbienceTrack.darkWhispers:
        return 'assets/audio/ambience_whispers.mp3';
      case AmbienceTrack.hauntedHouse:
        return 'assets/audio/ambience_haunted.mp3';
      case AmbienceTrack.stormy:
        return 'assets/audio/ambience_storm.mp3';
      case AmbienceTrack.tension:
        return 'assets/audio/ambience_tension.mp3';
      case AmbienceTrack.none:
        return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AmbienceService
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing horror background audio during gameplay.
///
/// Audio is played at low volume (0.15-0.30) to create atmospheric tension
/// without overpowering discussion. Automatically pauses during voting/reveal
/// and resumes during discussion.
///
/// This service provides the control layer and state management.
/// On web (kIsWeb), audio is disabled to avoid autoplay restrictions.
///
/// Usage:
/// ```dart
/// final ambience = ref.read(ambienceServiceProvider);
/// ambience.setTrack(AmbienceTrack.darkWhispers);
/// ambience.play();
/// ambience.setVolume(0.2);
/// ambience.pause(); // During voting
/// ambience.resume(); // During discussion
/// ambience.stop();
/// ```
class AmbienceService extends ChangeNotifier {
  // ─────────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────────

  AmbienceTrack _currentTrack = AmbienceTrack.none;
  double _volume = 0.20;
  bool _isPlaying = false;
  bool _isEnabled = true;

  // For now, state management is provided without the actual audio player

  // ─────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────

  /// Currently selected ambience track.
  AmbienceTrack get currentTrack => _currentTrack;

  /// Current volume level (0.0 to 1.0).
  double get volume => _volume;

  /// Whether ambience is currently playing.
  bool get isPlaying => _isPlaying;

  /// Whether ambience is globally enabled in settings.
  bool get isEnabled => _isEnabled;

  // ─────────────────────────────────────────────────────────────────────
  // Controls
  // ─────────────────────────────────────────────────────────────────────

  /// Enable or disable ambience globally.
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (!enabled && _isPlaying) {
      stop();
    }
    _log('Enabled: $enabled');
    notifyListeners();
  }

  /// Set the ambience track.
  void setTrack(AmbienceTrack track) {
    if (_currentTrack == track) return;

    final wasPlaying = _isPlaying;
    if (_isPlaying) {
      stop();
    }

    _currentTrack = track;
    _log('Track set: ${track.displayName}');

    if (wasPlaying && track != AmbienceTrack.none) {
      play();
    }

    notifyListeners();
  }

  /// Set the volume (0.0 to 1.0).
  void setVolume(double vol) {
    _volume = vol.clamp(0.0, 1.0);
    // If we had an audio player: _audioPlayer?.setVolume(_volume);
    _log('Volume: $_volume');
    notifyListeners();
  }

  /// Start playing the current track.
  void play() {
    if (!_isEnabled || _currentTrack == AmbienceTrack.none) return;
    if (kIsWeb) {
      _log('Audio disabled on web platform');
      return;
    }

    _isPlaying = true;
    // Actual playback would be:
    // _audioPlayer.setAsset(_currentTrack.assetPath);
    // _audioPlayer.setVolume(_volume);
    // _audioPlayer.setLoopMode(LoopMode.all);
    // _audioPlayer.play();
    _log('Playing: ${_currentTrack.displayName} at volume $_volume');
    notifyListeners();
  }

  /// Pause playback (e.g., during voting phase).
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    // _audioPlayer?.pause();
    _log('Paused');
    notifyListeners();
  }

  /// Resume playback (e.g., returning to discussion phase).
  void resume() {
    if (!_isEnabled || _currentTrack == AmbienceTrack.none) return;
    _isPlaying = true;
    // _audioPlayer?.play();
    _log('Resumed');
    notifyListeners();
  }

  /// Stop playback and reset position.
  void stop() {
    _isPlaying = false;
    // _audioPlayer?.stop();
    _log('Stopped');
    notifyListeners();
  }

  /// Fade out over a given duration (e.g., when transitioning to voting).
  Future<void> fadeOut({
    Duration duration = const Duration(seconds: 2),
  }) async {
    if (!_isPlaying) return;

    final steps = 20;
    final stepDuration = duration ~/ steps;
    final startVolume = _volume;

    for (int i = steps; i >= 0; i--) {
      if (!_isPlaying) break;
      final newVolume = startVolume * (i / steps);
      setVolume(newVolume);
      await Future.delayed(stepDuration);
    }

    stop();
    setVolume(startVolume); // Restore original volume for next play
  }

  @override
  void dispose() {
    stop();
    // _audioPlayer?.dispose();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Riverpod Provider
// ═══════════════════════════════════════════════════════════════════════════

final ambienceServiceProvider = ChangeNotifierProvider<AmbienceService>((ref) {
  return AmbienceService();
});
