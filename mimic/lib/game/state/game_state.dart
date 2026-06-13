// lib/game/state/game_state.dart
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/game/data/word_packs.dart';

enum GameMode { classic, nightmare, survival }

class RoundOutcome {
  final int round;
  final List<String> mimicIds;
  final String? accusedPlayerId;

  RoundOutcome({
    required this.round,
    required this.mimicIds,
    this.accusedPlayerId,
  });
}

class Player {
  final String id;
  final String name;
  final int color;
  final bool isAlive;
  final bool isGhost;
  final double suspicion; // range 0.0 to 1.0 (for UI compatibility)
  final String? profileId;

  Player({
    required this.id,
    required this.name,
    required this.color,
    this.isAlive = true,
    this.isGhost = false,
    this.suspicion = 0.0,
    this.profileId,
  });

  bool get isEliminated => !isAlive;

  Player copyWith({
    String? name,
    bool? isAlive,
    bool? isGhost,
    double? suspicion,
    String? profileId,
  }) {
    return Player(
      id: id,
      name: name ?? this.name,
      color: color,
      isAlive: isAlive ?? this.isAlive,
      isGhost: isGhost ?? this.isGhost,
      suspicion: suspicion ?? this.suspicion,
      profileId: profileId ?? this.profileId,
    );
  }
}

class GameState {
  final GameMode selectedMode;
  final List<Player> players;
  final List<String> mimicIds;
  final int currentRound;
  final int maxRounds;
  final Map<String, int> suspicionScores; // Map of playerId to int 0-100
  final List<String> eliminatedPlayers;   // list of playerIds for Survival mode
  final List<String> ghostPlayers;        // list of playerIds for Survival mode
  final List<String> selectedPacks;       // list of WordPack ids
  final WordPair? currentWordPair;        // WordPair for this round
  final String? secondMimicWord;          // Store second mimic's fake word in Nightmare mode
  final Map<String, int> scores;          // Map of playerId to int
  final String currentCategory;           // WordPack category/name for this round
  final List<RoundOutcome> roundOutcomes; // History of outcomes per round

  // Legacy field support for old files
  GameMode get gameMode => selectedMode;
  String? get mimicId => mimicIds.isNotEmpty ? mimicIds.first : null;
  String? get currentWord => currentWordPair?.realWord;
  List<String> get selectedPackIds => selectedPacks;

  bool get isFinalRound => currentRound >= maxRounds - 1;

  bool get isGameOver {
    if (selectedMode == GameMode.survival) {
      final survivors = players.where((p) => p.isAlive).length;
      return survivors <= 1 || isFinalRound;
    }
    return isFinalRound;
  }

  /// Deterministic winner computation for a finished game.
  /// Returns the set of player IDs who won. Empty set = draw / no winner.
  static Set<String> winnerIds(GameState state) {
    if (state.selectedMode == GameMode.survival) {
      final alive = state.players.where((p) => p.isAlive).toList();
      if (alive.length == 1) return {alive.first.id};
      // Round-cap reached with >1 alive: highest-scoring alive player(s)
      if (alive.isEmpty) return {};
      final aliveScores = {for (final p in alive) p.id: state.scores[p.id] ?? 0};
      final max = aliveScores.values.reduce((a, b) => a > b ? a : b);
      if (max <= 0) return {};
      return aliveScores.entries.where((e) => e.value == max).map((e) => e.key).toSet();
    }
    // Classic / Nightmare: highest cumulative score
    if (state.scores.isEmpty) return {};
    final max = state.scores.values.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return {};
    return state.scores.entries.where((e) => e.value == max).map((e) => e.key).toSet();
  }

  GameState({
    this.selectedMode = GameMode.classic,
    this.players = const [],
    this.mimicIds = const [],
    this.currentRound = 0,
    this.maxRounds = 3,
    this.suspicionScores = const {},
    this.eliminatedPlayers = const [],
    this.ghostPlayers = const [],
    this.selectedPacks = const [],
    this.currentWordPair,
    this.secondMimicWord,
    this.scores = const {},
    this.currentCategory = '',
    this.roundOutcomes = const [],
  });

  GameState copyWith({
    GameMode? selectedMode,
    List<Player>? players,
    List<String>? mimicIds,
    int? currentRound,
    int? maxRounds,
    Map<String, int>? suspicionScores,
    List<String>? eliminatedPlayers,
    List<String>? ghostPlayers,
    List<String>? selectedPacks,
    WordPair? currentWordPair,
    String? secondMimicWord,
    Map<String, int>? scores,
    String? currentCategory,
    List<RoundOutcome>? roundOutcomes,
  }) {
    return GameState(
      selectedMode: selectedMode ?? this.selectedMode,
      players: players ?? this.players,
      mimicIds: mimicIds ?? this.mimicIds,
      currentRound: currentRound ?? this.currentRound,
      maxRounds: maxRounds ?? this.maxRounds,
      suspicionScores: suspicionScores ?? this.suspicionScores,
      eliminatedPlayers: eliminatedPlayers ?? this.eliminatedPlayers,
      ghostPlayers: ghostPlayers ?? this.ghostPlayers,
      selectedPacks: selectedPacks ?? this.selectedPacks,
      currentWordPair: currentWordPair ?? this.currentWordPair,
      secondMimicWord: secondMimicWord ?? this.secondMimicWord,
      scores: scores ?? this.scores,
      currentCategory: currentCategory ?? this.currentCategory,
      roundOutcomes: roundOutcomes ?? this.roundOutcomes,
    );
  }

  /// Helper to get the correct word representing this round for any player.
  /// If the player is a Mimic, they see their corresponding fake word.
  String getWordForPlayer(String playerId) {
    if (!mimicIds.contains(playerId)) {
      return currentWordPair?.realWord ?? '';
    }
    // Nightmare mode: Second mimic sees a different fake word from the same pack
    if (selectedMode == GameMode.nightmare && mimicIds.indexOf(playerId) == 1 && secondMimicWord != null) {
      return secondMimicWord!;
    }
    return currentWordPair?.mimicWord ?? '';
  }
}

class GameStateNotifier extends StateNotifier<GameState> {
  GameStateNotifier() : super(GameState());

  void selectMode(GameMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  // Backward compatibility alias
  void setGameMode(GameMode mode) => selectMode(mode);

  void setSelectedPackIds(List<String> ids) {
    state = state.copyWith(selectedPacks: ids);
  }

  void addPlayer(String name, int color, {String? profileId}) {
    if (state.players.length >= 8) return;
    
    final newPlayer = Player(
      id: DateTime.now().millisecondsSinceEpoch.toString() + state.players.length.toString(),
      name: name,
      color: color,
      profileId: profileId,
    );
    
    state = state.copyWith(
      players: [...state.players, newPlayer],
      scores: {...state.scores, newPlayer.id: 0},
      suspicionScores: {...state.suspicionScores, newPlayer.id: 0},
    );
  }

  void removePlayer(String playerId) {
    state = state.copyWith(
      players: state.players.where((p) => p.id != playerId).toList(),
      scores: Map.from(state.scores)..remove(playerId),
      suspicionScores: Map.from(state.suspicionScores)..remove(playerId),
    );
    
    if (state.mimicIds.contains(playerId)) {
      state = state.copyWith(
        mimicIds: state.mimicIds.where((id) => id != playerId).toList(),
      );
    }
  }

  void updatePlayerName(String playerId, String name) {
    final updatedPlayers = state.players.map((p) {
      if (p.id == playerId) {
        return p.copyWith(name: name);
      }
      return p;
    }).toList();
    
    state = state.copyWith(players: updatedPlayers);
  }

  void addSuspicion(String playerId, int amount) {
    final current = state.suspicionScores[playerId] ?? 0;
    final newScore = (current + amount).clamp(0, 100);
    
    final updatedSuspicionScores = {
      ...state.suspicionScores,
      playerId: newScore,
    };

    final updatedPlayers = state.players.map((p) {
      if (p.id == playerId) {
        return p.copyWith(suspicion: newScore / 100.0);
      }
      return p;
    }).toList();

    state = state.copyWith(
      suspicionScores: updatedSuspicionScores,
      players: updatedPlayers,
    );
  }

  // Backward compatibility alias for tap-to-suspect updates
  void updateSuspicion(String playerId, double value) {
    final int intVal = (value * 100).toInt();
    final clamped = intVal.clamp(0, 100);
    
    final updatedSuspicionScores = {
      ...state.suspicionScores,
      playerId: clamped,
    };

    final updatedPlayers = state.players.map((p) {
      if (p.id == playerId) {
        return p.copyWith(suspicion: clamped / 100.0);
      }
      return p;
    }).toList();

    state = state.copyWith(
      suspicionScores: updatedSuspicionScores,
      players: updatedPlayers,
    );
  }

  void eliminatePlayer(String playerId) {
    final newEliminated = [...state.eliminatedPlayers];
    if (!newEliminated.contains(playerId)) {
      newEliminated.add(playerId);
    }

    final newGhosts = [...state.ghostPlayers];
    if (!newGhosts.contains(playerId)) {
      newGhosts.add(playerId);
    }

    final updatedPlayers = state.players.map((p) {
      if (p.id == playerId) {
        return p.copyWith(isAlive: false, isGhost: true);
      }
      return p;
    }).toList();

    state = state.copyWith(
      players: updatedPlayers,
      eliminatedPlayers: newEliminated,
      ghostPlayers: newGhosts,
    );
  }

  // Backward compatibility alias
  void toggleEliminated(String playerId) {
    final isEliminated = state.eliminatedPlayers.contains(playerId);
    if (!isEliminated) {
      eliminatePlayer(playerId);
    } else {
      // Revive player
      final updatedPlayers = state.players.map((p) {
        if (p.id == playerId) {
          return p.copyWith(isAlive: true, isGhost: false);
        }
        return p;
      }).toList();

      state = state.copyWith(
        players: updatedPlayers,
        eliminatedPlayers: state.eliminatedPlayers.where((id) => id != playerId).toList(),
        ghostPlayers: state.ghostPlayers.where((id) => id != playerId).toList(),
      );
    }
  }

  void assignMimics() {
    if (state.players.isEmpty) return;
    
    // Filter active/alive players
    final activeList = state.players.where((p) => p.isAlive).toList();
    if (activeList.isEmpty) return;

    final random = math.Random();
    activeList.shuffle(random);

    // Pick a random WordPair from selected packs
    final activePacks = WordPackData.packs.where((p) => state.selectedPacks.contains(p.id)).toList();
    final packsToUse = activePacks.isNotEmpty ? activePacks : [WordPackData.packs.first];
    
    final chosenPack = packsToUse[random.nextInt(packsToUse.length)];
    final pairs = chosenPack.pairs;
    
    int pair1Index = random.nextInt(pairs.length);
    WordPair wordPair1 = pairs[pair1Index];
    
    // Prefer a different pair than the current one if possible
    if (pairs.length > 1 && state.currentWordPair != null) {
      while (wordPair1.realWord == state.currentWordPair!.realWord) {
        pair1Index = random.nextInt(pairs.length);
        wordPair1 = pairs[pair1Index];
      }
    }

    // Assign Mimics depending on mode
    if (state.selectedMode == GameMode.nightmare && activeList.length >= 4) {
      final mimic1 = activeList[0].id;
      final mimic2 = activeList[1].id;

      // Select a different pair from the same pack for the second mimic's fake word
      WordPair wordPair2 = wordPair1;
      if (pairs.length > 1) {
        int pair2Index = random.nextInt(pairs.length);
        while (pair2Index == pair1Index) {
          pair2Index = random.nextInt(pairs.length);
        }
        wordPair2 = pairs[pair2Index];
      }

      state = state.copyWith(
        mimicIds: [mimic1, mimic2],
        currentWordPair: wordPair1,
        secondMimicWord: wordPair2.mimicWord,
        currentCategory: chosenPack.name,
        suspicionScores: {
          for (var p in state.players) p.id: 0,
        },
        players: state.players.map((p) => p.copyWith(suspicion: 0.0)).toList(),
      );
    } else {
      // Classic or Survival
      final mimic1 = activeList[0].id;
      state = state.copyWith(
        mimicIds: [mimic1],
        currentWordPair: wordPair1,
        secondMimicWord: null,
        currentCategory: chosenPack.name,
        suspicionScores: {
          for (var p in state.players) p.id: 0,
        },
        players: state.players.map((p) => p.copyWith(suspicion: 0.0)).toList(),
      );
    }
  }

  // Backward compatibility alias
  void assignMimic() => assignMimics();

  void setMimicIds(List<String> ids) {
    state = state.copyWith(mimicIds: ids);
  }

  void updateScore(String playerId, int score) {
    state = state.copyWith(
      scores: {...state.scores, playerId: score},
    );
  }

  void addRoundOutcome(RoundOutcome outcome) {
    state = state.copyWith(
      roundOutcomes: [...state.roundOutcomes, outcome],
    );
  }

  void restartRound() {
    state = state.copyWith(
      currentRound: 0,
      currentWordPair: null,
      secondMimicWord: null,
      mimicIds: const [],
      currentCategory: '',
      scores: {for (var p in state.players) p.id: 0},
      suspicionScores: {for (var p in state.players) p.id: 0},
      players: state.players.map((p) => p.copyWith(isAlive: true, isGhost: false, suspicion: 0.0)).toList(),
      eliminatedPlayers: const [],
      ghostPlayers: const [],
      roundOutcomes: const [],
    );
  }

  void nextRound() {
    assignMimics();
    state = state.copyWith(currentRound: state.currentRound + 1);
  }

  void endGame() {
    state = state.copyWith(
      mimicIds: const [],
      currentRound: 0,
      suspicionScores: const {},
      eliminatedPlayers: const [],
      ghostPlayers: const [],
      currentWordPair: null,
      secondMimicWord: null,
      currentCategory: '',
      players: state.players.map((p) => p.copyWith(isAlive: true, isGhost: false, suspicion: 0.0)).toList(),
      roundOutcomes: const [],
    );
  }

  void resetGame() {
    state = GameState(
      selectedMode: state.selectedMode,
      selectedPacks: state.selectedPacks,
    );
  }

  void addPlayerWithId(String id, String name, int color) {
    if (state.players.length >= 8) return;
    if (state.players.any((p) => p.id == id)) return;
    
    final newPlayer = Player(
      id: id,
      name: name,
      color: color,
    );
    
    state = state.copyWith(
      players: [...state.players, newPlayer],
      scores: {...state.scores, newPlayer.id: 0},
      suspicionScores: {...state.suspicionScores, newPlayer.id: 0},
    );
  }

  void initializeMultiplayerPlayers(List<Player> players) {
    state = state.copyWith(
      players: players,
      scores: {
        for (var p in players) p.id: 0,
      },
      suspicionScores: {
        for (var p in players) p.id: 0,
      },
    );
  }

  void remapPlayerId(String oldId, String newId) {
    if (oldId == newId || oldId.isEmpty) return;

    final updatedPlayers = state.players.map((p) {
      if (p.id == oldId) {
        return Player(
          id: newId,
          name: p.name,
          color: p.color,
          isAlive: p.isAlive,
          isGhost: p.isGhost,
          suspicion: p.suspicion,
        );
      }
      return p;
    }).toList();

    final updatedMimicIds = state.mimicIds.map((id) => id == oldId ? newId : id).toList();
    final updatedEliminated = state.eliminatedPlayers.map((id) => id == oldId ? newId : id).toList();
    final updatedGhost = state.ghostPlayers.map((id) => id == oldId ? newId : id).toList();

    final updatedScores = Map<String, int>.from(state.scores);
    if (updatedScores.containsKey(oldId)) {
      final val = updatedScores.remove(oldId)!;
      updatedScores[newId] = val;
    }

    final updatedSuspicion = Map<String, int>.from(state.suspicionScores);
    if (updatedSuspicion.containsKey(oldId)) {
      final val = updatedSuspicion.remove(oldId)!;
      updatedSuspicion[newId] = val;
    }

    state = state.copyWith(
      players: updatedPlayers,
      mimicIds: updatedMimicIds,
      eliminatedPlayers: updatedEliminated,
      ghostPlayers: updatedGhost,
      scores: updatedScores,
      suspicionScores: updatedSuspicion,
    );
  }

  void applyRemoteState(GameState remoteState) {
    state = remoteState;
  }

  void updateGuestRoleAndWord({
    required bool isMimic,
    required String word,
    required String playerId,
  }) {
    final wordPair = isMimic
        ? WordPair(realWord: '', mimicWord: word)
        : WordPair(realWord: word, mimicWord: '');

    state = state.copyWith(
      mimicIds: isMimic ? [playerId] : const [],
      currentWordPair: wordPair,
    );
  }

  void castVote(String voterId, String targetId) {
    // Satisfy network sync requirements. Logic placeholder.
  }
}

final gameStateProvider = StateNotifierProvider<GameStateNotifier, GameState>((ref) {
  return GameStateNotifier();
});