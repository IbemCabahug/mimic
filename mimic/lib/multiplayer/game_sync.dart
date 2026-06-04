// lib/multiplayer/game_sync.dart
//
// Serializes and deserializes GameState for multiplayer transmission.
// The host broadcasts full or partial state snapshots over the network;
// guests apply the received state to their local GameStateNotifier.
//
// All multiplayer message types flow through this class so the rest of the
// app never constructs raw JSON maps for game-level events.

import 'package:flutter/foundation.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/state/game_state.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds.
void _log(String message) => debugPrint('[GameSync] $message');

// ═══════════════════════════════════════════════════════════════════════════
// Message Types
// ═══════════════════════════════════════════════════════════════════════════

/// All multiplayer game-level message types.
///
/// Network-layer messages (welcome, playerJoined, playerLeft, playerReady,
/// disconnected, etc.) are handled directly by [NetworkService].
/// [GameSync] only deals with game-logic messages listed here.
abstract class GameMessageType {
  static const String gameStart = 'gameStart';
  static const String roundStart = 'roundStart';
  static const String wordReveal = 'wordReveal';
  static const String discussionStart = 'discussionStart';
  static const String voteCast = 'voteCast';
  static const String voteResults = 'voteResults';
  static const String suspicionUpdate = 'suspicionUpdate';
  static const String playerEliminated = 'playerEliminated';
  static const String roundEnd = 'roundEnd';
  static const String gameEnd = 'gameEnd';
  static const String stateSnapshot = 'stateSnapshot';
  static const String chatMessage = 'chatMessage';
  static const String accusation = 'accusation';
}

// ═══════════════════════════════════════════════════════════════════════════
// GameSync
// ═══════════════════════════════════════════════════════════════════════════

/// Handles serialization of [GameState] and construction of typed game
/// messages for multiplayer transmission.
///
/// Usage:
/// ```dart
/// // Host broadcasts game start:
/// final msg = GameSync.buildGameStart(gameState);
/// networkService.send(msg);
///
/// // Guest receives and applies:
/// final state = GameSync.parseStateSnapshot(message);
/// gameStateNotifier.applyRemoteState(state);
/// ```
class GameSync {
  GameSync._(); // Prevent instantiation

  // ─────────────────────────────────────────────────────────────────────
  // Serialization — GameState → JSON
  // ─────────────────────────────────────────────────────────────────────

  /// Serialize a full [GameState] into a JSON-compatible map.
  static Map<String, dynamic> serializeState(GameState state) {
    return {
      'selectedMode': state.selectedMode.name,
      'players': state.players.map((p) => _serializePlayer(p)).toList(),
      'mimicIds': state.mimicIds,
      'currentRound': state.currentRound,
      'maxRounds': state.maxRounds,
      'suspicionScores': state.suspicionScores.map(
        (k, v) => MapEntry(k, v),
      ),
      'eliminatedPlayers': state.eliminatedPlayers,
      'ghostPlayers': state.ghostPlayers,
      'selectedPacks': state.selectedPacks,
      'currentWordPair': state.currentWordPair != null
          ? {
              'realWord': state.currentWordPair!.realWord,
              'mimicWord': state.currentWordPair!.mimicWord,
            }
          : null,
      'secondMimicWord': state.secondMimicWord,
      'scores': state.scores.map((k, v) => MapEntry(k, v)),
      'currentCategory': state.currentCategory,
    };
  }

  /// Serialize a [Player] to a JSON-compatible map.
  static Map<String, dynamic> _serializePlayer(Player player) {
    return {
      'id': player.id,
      'name': player.name,
      'color': player.color,
      'isAlive': player.isAlive,
      'isGhost': player.isGhost,
      'suspicion': player.suspicion,
    };
  }

  // ─────────────────────────────────────────────────────────────────────
  // Deserialization — JSON → GameState
  // ─────────────────────────────────────────────────────────────────────

  /// Deserialize a full [GameState] from a JSON map.
  /// Returns `null` if the map is malformed.
  static GameState? deserializeState(Map<String, dynamic> json) {
    try {
      final modeName = json['selectedMode'] as String? ?? 'classic';
      final mode = GameMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => GameMode.classic,
      );

      final playersList = (json['players'] as List<dynamic>?)
              ?.map((p) => _deserializePlayer(p as Map<String, dynamic>))
              .toList() ??
          [];

      final mimicIds =
          (json['mimicIds'] as List<dynamic>?)?.cast<String>() ?? [];

      WordPair? wordPair;
      if (json['currentWordPair'] != null) {
        final wpMap = json['currentWordPair'] as Map<String, dynamic>;
        wordPair = WordPair(
          realWord: wpMap['realWord'] as String? ?? '',
          mimicWord: wpMap['mimicWord'] as String? ?? '',
        );
      }

      final suspicionScores = <String, int>{};
      if (json['suspicionScores'] != null) {
        (json['suspicionScores'] as Map<String, dynamic>).forEach((k, v) {
          suspicionScores[k] = (v as num).toInt();
        });
      }

      final scores = <String, int>{};
      if (json['scores'] != null) {
        (json['scores'] as Map<String, dynamic>).forEach((k, v) {
          scores[k] = (v as num).toInt();
        });
      }

      return GameState(
        selectedMode: mode,
        players: playersList,
        mimicIds: mimicIds,
        currentRound: (json['currentRound'] as num?)?.toInt() ?? 0,
        maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 3,
        suspicionScores: suspicionScores,
        eliminatedPlayers:
            (json['eliminatedPlayers'] as List<dynamic>?)?.cast<String>() ??
                [],
        ghostPlayers:
            (json['ghostPlayers'] as List<dynamic>?)?.cast<String>() ?? [],
        selectedPacks:
            (json['selectedPacks'] as List<dynamic>?)?.cast<String>() ?? [],
        currentWordPair: wordPair,
        secondMimicWord: json['secondMimicWord'] as String?,
        scores: scores,
        currentCategory: json['currentCategory'] as String? ?? '',
      );
    } catch (e) {
      _log('Failed to deserialize GameState: $e');
      return null;
    }
  }

  /// Deserialize a [Player] from a JSON map.
  static Player _deserializePlayer(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      color: (json['color'] as num?)?.toInt() ?? 0xFF6B7280,
      isAlive: json['isAlive'] as bool? ?? true,
      isGhost: json['isGhost'] as bool? ?? false,
      suspicion: (json['suspicion'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Message Builders — Host → Guests
  // ─────────────────────────────────────────────────────────────────────

  /// Full state snapshot — sent when a guest joins mid-game or at the
  /// start of each round for full sync.
  static Map<String, dynamic> buildStateSnapshot(GameState state) {
    return {
      'type': GameMessageType.stateSnapshot,
      ...serializeState(state),
    };
  }

  /// Signals all guests that the game is starting.
  /// Includes full state so guests initialize their local state.
  static Map<String, dynamic> buildGameStart(GameState state) {
    return {
      'type': GameMessageType.gameStart,
      ...serializeState(state),
    };
  }

  /// Signals the start of a new round.
  /// Includes the round number and refreshed state.
  static Map<String, dynamic> buildRoundStart(GameState state) {
    return {
      'type': GameMessageType.roundStart,
      'round': state.currentRound,
      ...serializeState(state),
    };
  }

  /// Sends the word reveal data for a specific player.
  /// The host sends each player their word individually (via sendTo)
  /// so mimics don't receive the real word in the broadcast.
  static Map<String, dynamic> buildWordReveal({
    required String playerId,
    required String word,
    required bool isMimic,
    required String category,
  }) {
    return {
      'type': GameMessageType.wordReveal,
      'playerId': playerId,
      'word': word,
      'isMimic': isMimic,
      'category': category,
    };
  }

  /// Signals that the discussion phase has started.
  static Map<String, dynamic> buildDiscussionStart({
    required int durationSeconds,
  }) {
    return {
      'type': GameMessageType.discussionStart,
      'durationSeconds': durationSeconds,
    };
  }

  /// A player has submitted an accusation before voting.
  static Map<String, dynamic> buildAccusation({
    required String accuserId,
    required String accusedId,
    required String reason,
  }) {
    return {
      'type': GameMessageType.accusation,
      'accuserId': accuserId,
      'accusedId': accusedId,
      'reason': reason,
    };
  }

  /// A single player's vote — sent from guest to host.
  static Map<String, dynamic> buildVoteCast({
    required String voterId,
    required String targetId,
  }) {
    return {
      'type': GameMessageType.voteCast,
      'voterId': voterId,
      'targetId': targetId,
    };
  }

  /// Host broadcasts aggregated vote results to all guests.
  static Map<String, dynamic> buildVoteResults({
    required Map<String, String> votes, // voterId → targetId
    required String eliminatedId, // who got voted out
    required bool mimicCaught,
    required List<String> mimicIds,
  }) {
    return {
      'type': GameMessageType.voteResults,
      'votes': votes,
      'eliminatedId': eliminatedId,
      'mimicCaught': mimicCaught,
      'mimicIds': mimicIds,
    };
  }

  /// Suspicion level update for a specific player.
  static Map<String, dynamic> buildSuspicionUpdate({
    required String playerId,
    required int suspicionValue,
  }) {
    return {
      'type': GameMessageType.suspicionUpdate,
      'playerId': playerId,
      'suspicionValue': suspicionValue,
    };
  }

  /// Notification that a player has been eliminated (Survival mode).
  static Map<String, dynamic> buildPlayerEliminated({
    required String playerId,
  }) {
    return {
      'type': GameMessageType.playerEliminated,
      'playerId': playerId,
    };
  }

  /// Signals the end of the current round with updated scores.
  static Map<String, dynamic> buildRoundEnd({
    required int round,
    required Map<String, int> scores,
    required bool gameOver,
  }) {
    return {
      'type': GameMessageType.roundEnd,
      'round': round,
      'scores': scores,
      'gameOver': gameOver,
    };
  }

  /// Signals the end of the entire game session.
  static Map<String, dynamic> buildGameEnd({
    required Map<String, int> finalScores,
    required String winnerId,
    required String winnerName,
  }) {
    return {
      'type': GameMessageType.gameEnd,
      'finalScores': finalScores,
      'winnerId': winnerId,
      'winnerName': winnerName,
    };
  }

  /// Build a chat message for relay.
  static Map<String, dynamic> buildChatMessage({
    required String senderId,
    required String senderName,
    required String text,
  }) {
    return {
      'type': GameMessageType.chatMessage,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  // ─────────────────────────────────────────────────────────────────────
  // Message Parsers
  // ─────────────────────────────────────────────────────────────────────

  /// Extract the message type from any incoming message.
  static String? getMessageType(Map<String, dynamic> message) {
    return message['type'] as String?;
  }

  /// Parse a full state snapshot or gameStart/roundStart message into
  /// a [GameState]. Works for any message that embeds serialized state.
  static GameState? parseStateSnapshot(Map<String, dynamic> message) {
    return deserializeState(message);
  }

  /// Parse vote results from a voteResults message.
  static VoteResultData? parseVoteResults(Map<String, dynamic> message) {
    try {
      final votes = <String, String>{};
      if (message['votes'] != null) {
        (message['votes'] as Map<String, dynamic>).forEach((k, v) {
          votes[k] = v as String;
        });
      }

      return VoteResultData(
        votes: votes,
        eliminatedId: message['eliminatedId'] as String? ?? '',
        mimicCaught: message['mimicCaught'] as bool? ?? false,
        mimicIds:
            (message['mimicIds'] as List<dynamic>?)?.cast<String>() ?? [],
      );
    } catch (e) {
      _log('Failed to parse vote results: $e');
      return null;
    }
  }

  /// Parse a word reveal message.
  static WordRevealData? parseWordReveal(Map<String, dynamic> message) {
    try {
      return WordRevealData(
        playerId: message['playerId'] as String? ?? '',
        word: message['word'] as String? ?? '',
        isMimic: message['isMimic'] as bool? ?? false,
        category: message['category'] as String? ?? '',
      );
    } catch (e) {
      _log('Failed to parse word reveal: $e');
      return null;
    }
  }

  /// Parse a chat message.
  static ChatMessageData? parseChatMessage(Map<String, dynamic> message) {
    try {
      return ChatMessageData(
        senderId: message['senderId'] as String? ?? '',
        senderName: message['senderName'] as String? ?? 'Unknown',
        text: message['text'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (message['timestamp'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      _log('Failed to parse chat message: $e');
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Data Classes for parsed results
// ═══════════════════════════════════════════════════════════════════════════

/// Parsed vote result data.
class VoteResultData {
  final Map<String, String> votes; // voterId → targetId
  final String eliminatedId;
  final bool mimicCaught;
  final List<String> mimicIds;

  const VoteResultData({
    required this.votes,
    required this.eliminatedId,
    required this.mimicCaught,
    required this.mimicIds,
  });
}

/// Parsed word reveal data for a specific player.
class WordRevealData {
  final String playerId;
  final String word;
  final bool isMimic;
  final String category;

  const WordRevealData({
    required this.playerId,
    required this.word,
    required this.isMimic,
    required this.category,
  });
}

/// Parsed chat message data.
class ChatMessageData {
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;

  const ChatMessageData({
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
  });
}
