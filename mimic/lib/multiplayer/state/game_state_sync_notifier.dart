// lib/multiplayer/state/game_state_sync_notifier.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/game_sync.dart';
import 'package:mimic/multiplayer/network/network_service.dart';

export 'package:mimic/core/providers/provider_registration.dart' show gameStateSyncProvider;


// ═══════════════════════════════════════════════════════════════════════════
// Model Classes
// ═══════════════════════════════════════════════════════════════════════════

class PlayerNetworkState {
  final String playerId;
  final String displayName;
  final bool hasReceivedWord;
  final bool hasVoted;
  final bool isEliminated;

  const PlayerNetworkState({
    required this.playerId,
    required this.displayName,
    this.hasReceivedWord = false,
    this.hasVoted = false,
    this.isEliminated = false,
  });

  PlayerNetworkState copyWith({
    String? displayName,
    bool? hasReceivedWord,
    bool? hasVoted,
    bool? isEliminated,
  }) {
    return PlayerNetworkState(
      playerId: playerId,
      displayName: displayName ?? this.displayName,
      hasReceivedWord: hasReceivedWord ?? this.hasReceivedWord,
      hasVoted: hasVoted ?? this.hasVoted,
      isEliminated: isEliminated ?? this.isEliminated,
    );
  }
}

class GameSyncState {
  final bool isReady;
  final String? error;
  final Map<String, PlayerNetworkState> players;

  const GameSyncState({
    this.isReady = false,
    this.error,
    this.players = const {},
  });

  GameSyncState copyWith({
    bool? isReady,
    String? error,
    Map<String, PlayerNetworkState>? players,
  }) {
    return GameSyncState(
      isReady: isReady ?? this.isReady,
      error: error ?? this.error,
      players: players ?? this.players,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GameStateSyncNotifier
// ═══════════════════════════════════════════════════════════════════════════

class GameStateSyncNotifier extends StateNotifier<GameSyncState> {
  final NetworkService networkService;
  final GameStateNotifier gameStateNotifier;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  GameStateSyncNotifier(this.networkService, this.gameStateNotifier)
      : super(const GameSyncState()) {
    _subscription = networkService.messageStream.listen((message) {
      final type = message['type'] as String?;
      switch (type) {
        case 'startGame':
          _initializeGame();
          break;
        case 'wordAck':
          final senderId = message['senderId'] as String?;
          if (senderId != null) {
            _updatePlayerReceivedWord(senderId);
          }
          break;
        case 'castVote':
          final voterId = message['voterId'] as String? ?? message['senderId'] as String?;
          final targetId = message['targetId'] as String?;
          if (voterId != null && targetId != null) {
            gameStateNotifier.castVote(voterId, targetId);
            final playerState = state.players[voterId];
            if (playerState != null) {
              final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players);
              updatedPlayers[voterId] = playerState.copyWith(hasVoted: true);
              state = state.copyWith(players: updatedPlayers);
              broadcastGameState();
            }
          }
          break;
        case 'requestRejoin':
          final senderId = message['senderId'] as String?;
          final originalPlayerId = message['playerId'] as String?;
          final name = message['name'] as String? ?? 'Guest';
          if (senderId != null) {
            _handleRejoin(senderId, originalPlayerId, name);
          }
          break;
        case 'playerLeft':
          final playerId = message['playerId'] as String?;
          if (playerId != null) {
            _handlePlayerLeft(playerId);
          }
          break;
        case 'playerJoined':
          final senderId = message['senderId'] as String?;
          final name = message['name'] as String? ?? 'Guest';
          if (senderId != null) {
            final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players);
            updatedPlayers[senderId] = PlayerNetworkState(
              playerId: senderId,
              displayName: name,
              hasReceivedWord: false,
              hasVoted: false,
              isEliminated: false,
            );
            state = state.copyWith(players: updatedPlayers);
            if (networkService.role == NetworkRole.host) {
              gameStateNotifier.addPlayerWithId(senderId, name, 0xFFC41E3A);
              broadcastGameState();
            }
          }
          break;
        case 'stateSnapshot':
          if (networkService.role == NetworkRole.guest) {
            final remoteState = GameSync.deserializeState(message);
            if (remoteState != null) {
              gameStateNotifier.applyRemoteState(remoteState);
            }
          }
          break;
        case 'roleAssigned':
          if (networkService.role == NetworkRole.guest) {
            final role = message['role'] as String?;
            final word = message['word'] as String? ?? '';
            final playerId = message['playerId'] as String?;
            final isMimic = role == 'mimic';
            gameStateNotifier.updateGuestRoleAndWord(
              isMimic: isMimic,
              word: word,
              playerId: playerId ?? '',
            );
          }
          break;
      }
    });
  }

  void _initializeGame() {
    if (networkService.role != NetworkRole.host) return;

    final connectedIds = networkService.connectedPlayerIds;
    final allPlayerIds = ['host', ...connectedIds];

    final colors = [
      0xFF8B0000, // bloodRed
      0xFFC41E3A, // crimson
      0xFF4A0E17, // deep wine
      0xFF7D1C1C, // rust red
      0xFF5C0632, // dark magenta
      0xFF360000, // near black red
      0xFFB22222, // firebrick red
      0xFF800000, // maroon
    ];

    final List<Player> newPlayers = [];
    for (int i = 0; i < allPlayerIds.length; i++) {
      final id = allPlayerIds[i];
      final displayName = state.players[id]?.displayName ?? (id == 'host' ? 'Host' : 'Guest $i');
      newPlayers.add(Player(
        id: id,
        name: displayName,
        color: colors[i % colors.length],
      ));
    }

    gameStateNotifier.initializeMultiplayerPlayers(newPlayers);
    gameStateNotifier.assignMimics();

    final updatedPlayersMap = <String, PlayerNetworkState>{};
    for (final id in allPlayerIds) {
      final isMimic = gameStateNotifier.state.mimicIds.contains(id);
      final role = isMimic ? 'mimic' : 'villager';
      final word = gameStateNotifier.state.getWordForPlayer(id);

      if (id != 'host') {
        networkService.sendTo(id, {
          'type': 'roleAssigned',
          'role': role,
          'word': word,
          'playerId': id,
        });
      }

      final displayName = state.players[id]?.displayName ?? (id == 'host' ? 'Host' : 'Guest');
      updatedPlayersMap[id] = PlayerNetworkState(
        playerId: id,
        displayName: displayName,
        hasReceivedWord: id == 'host', // Host gets word immediately
        hasVoted: false,
        isEliminated: false,
      );
    }

    state = state.copyWith(
      players: updatedPlayersMap,
      isReady: true,
    );
  }

  void broadcastGameState() {
    if (networkService.role != NetworkRole.host) return;

    final gameState = gameStateNotifier.state;
    final guestIds = networkService.connectedPlayerIds;

    for (final guestId in guestIds) {
      final isMimic = gameState.mimicIds.contains(guestId);
      final guestWord = gameState.getWordForPlayer(guestId);

      final serialized = GameSync.serializeState(gameState);

      // Sanitize secrets
      serialized['mimicIds'] = isMimic ? [guestId] : <String>[];
      serialized['secondMimicWord'] = null;
      serialized['currentWordPair'] = {
        'realWord': guestWord,
        'mimicWord': guestWord,
      };

      networkService.sendTo(guestId, {
        'type': 'stateSnapshot',
        ...serialized,
      });
    }
  }

  /// Returns the display name for a player, or null if unknown.
  String? getPlayerDisplayName(String playerId) {
    return state.players[playerId]?.displayName;
  }

  void handlePlayerLeft(String playerId) {
    _handlePlayerLeft(playerId);
  }

  void _handlePlayerLeft(String playerId) {
    if (networkService.role != NetworkRole.host) return;

    final gameStarted = gameStateNotifier.state.currentRound > 0;

    if (!gameStarted) {
      final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players)..remove(playerId);
      state = state.copyWith(players: updatedPlayers);
      gameStateNotifier.removePlayer(playerId);
      broadcastGameState();
    } else {
      gameStateNotifier.eliminatePlayer(playerId);

      final playerState = state.players[playerId];
      if (playerState != null) {
        final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players);
        updatedPlayers[playerId] = playerState.copyWith(isEliminated: true);
        state = state.copyWith(players: updatedPlayers);
      }
      broadcastGameState();
    }
  }

  void _handleRejoin(String newPlayerId, String? originalPlayerId, String name) {
    if (networkService.role != NetworkRole.host) return;

    final oldId = originalPlayerId ?? '';

    // Remap player ID in GameState
    if (oldId.isNotEmpty && oldId != newPlayerId) {
      gameStateNotifier.remapPlayerId(oldId, newPlayerId);
    }

    final isMimic = gameStateNotifier.state.mimicIds.contains(newPlayerId);
    final role = isMimic ? 'mimic' : 'villager';
    final word = gameStateNotifier.state.getWordForPlayer(newPlayerId);

    final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players);
    if (oldId.isNotEmpty && oldId != newPlayerId) {
      updatedPlayers.remove(oldId);
    }
    updatedPlayers[newPlayerId] = PlayerNetworkState(
      playerId: newPlayerId,
      displayName: name,
      hasReceivedWord: false,
      hasVoted: false,
      isEliminated: gameStateNotifier.state.eliminatedPlayers.contains(newPlayerId),
    );

    state = state.copyWith(players: updatedPlayers);

    // Determine the current phase on the host
    String phase = 'discussion';
    final currentRound = gameStateNotifier.state.currentRound;
    if (currentRound == 0) {
      phase = 'lobby';
    } else {
      bool anyWordPending = false;
      for (var entry in updatedPlayers.entries) {
        if (entry.key != 'host' && !entry.value.isEliminated && !entry.value.hasReceivedWord) {
          anyWordPending = true;
          break;
        }
      }
      if (anyWordPending) {
        phase = 'wordReveal';
      } else {
        bool anyVoted = false;
        for (var entry in updatedPlayers.entries) {
          if (!entry.value.isEliminated && entry.value.hasVoted) {
            anyVoted = true;
            break;
          }
        }
        if (anyVoted) {
          phase = 'voting';
        }
      }
    }

    // Send rejoinAccepted message directly to rejoining guest
    networkService.sendTo(newPlayerId, {
      'type': 'rejoinAccepted',
      'role': role,
      'word': word,
      'playerId': newPlayerId,
      'phase': phase,
      'gameState': GameSync.serializeState(gameStateNotifier.state),
    });

    broadcastGameState();
  }

  void _updatePlayerReceivedWord(String playerId) {
    final playerState = state.players[playerId];
    if (playerState != null) {
      final updatedPlayers = Map<String, PlayerNetworkState>.from(state.players);
      updatedPlayers[playerId] = playerState.copyWith(hasReceivedWord: true);
      state = state.copyWith(players: updatedPlayers);
      if (networkService.role == NetworkRole.host) {
        broadcastGameState();
      }
    }
  }
  void acknowledgeWord(String playerId) {
    _updatePlayerReceivedWord(playerId);
  }

  void startNextRound() {
    if (networkService.role != NetworkRole.host) return;

    // 1. Increment round and assign new mimics
    gameStateNotifier.nextRound();
    gameStateNotifier.assignMimics();

    // 2. Reset player sync states and send new roles
    final connectedIds = networkService.connectedPlayerIds;
    final allPlayerIds = ['host', ...connectedIds];
    final updatedPlayersMap = <String, PlayerNetworkState>{};

    for (final id in allPlayerIds) {
      final isMimic = gameStateNotifier.state.mimicIds.contains(id);
      final role = isMimic ? 'mimic' : 'villager';
      final word = gameStateNotifier.state.getWordForPlayer(id);

      if (id != 'host') {
        networkService.sendTo(id, {
          'type': 'roleAssigned',
          'role': role,
          'word': word,
          'playerId': id,
        });
      }

      final displayName = state.players[id]?.displayName ?? (id == 'host' ? 'Host' : 'Guest');
      updatedPlayersMap[id] = PlayerNetworkState(
        playerId: id,
        displayName: displayName,
        hasReceivedWord: id == 'host', // Host gets word immediately
        hasVoted: false,
        isEliminated: gameStateNotifier.state.eliminatedPlayers.contains(id),
      );
    }

    state = state.copyWith(
      players: updatedPlayersMap,
      isReady: true,
    );

    // 3. Broadcast new game state snapshot to guests
    broadcastGameState();

    // 4. Broadcast nextRound message to guests
    networkService.send({'type': 'nextRound'});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}


