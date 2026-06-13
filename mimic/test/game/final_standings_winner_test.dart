// test/game/final_standings_winner_test.dart
//
// Unit tests for GameState.winnerIds — the deterministic winner helper.

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/data/word_packs.dart';

GameState _makeState({
  required GameMode mode,
  required List<Player> players,
  required Map<String, int> scores,
  int currentRound = 2,
  int maxRounds = 3,
}) {
  return GameState(
    selectedMode: mode,
    players: players,
    scores: scores,
    currentRound: currentRound,
    maxRounds: maxRounds,
    currentWordPair: const WordPair(realWord: 'Test', mimicWord: 'Fake'),
  );
}

void main() {
  group('GameState.winnerIds', () {
    // ── Survival ──────────────────────────────────────────────────────

    test('Survival, round-cap with 3 alive → highest-scoring alive player wins', () {
      final players = [
        Player(id: 'p1', name: 'A', color: 0xFF000001),
        Player(id: 'p2', name: 'B', color: 0xFF000002),
        Player(id: 'p3', name: 'C', color: 0xFF000003),
        Player(id: 'p4', name: 'D', color: 0xFF000004, isAlive: false),
        Player(id: 'p5', name: 'E', color: 0xFF000005, isAlive: false),
        Player(id: 'p6', name: 'F', color: 0xFF000006, isAlive: false),
      ];
      final scores = {'p1': 6, 'p2': 4, 'p3': 2, 'p4': 8, 'p5': 0, 'p6': 0};
      final state = _makeState(mode: GameMode.survival, players: players, scores: scores);

      expect(state.isGameOver, isTrue, reason: 'round-cap reached');
      final winners = GameState.winnerIds(state);
      expect(winners, equals({'p1'}), reason: 'p1 is alive with highest score');
      expect(winners, isNotEmpty, reason: 'BUG 1 fix: must not be empty at round cap');
    });

    test('Survival, sole survivor → that survivor wins regardless of score', () {
      final players = [
        Player(id: 'p1', name: 'A', color: 0xFF000001),
        Player(id: 'p2', name: 'B', color: 0xFF000002, isAlive: false),
        Player(id: 'p3', name: 'C', color: 0xFF000003, isAlive: false),
      ];
      final scores = {'p1': 0, 'p2': 10, 'p3': 5};
      final state = _makeState(
        mode: GameMode.survival,
        players: players,
        scores: scores,
        currentRound: 1,
        maxRounds: 3,
      );

      final winners = GameState.winnerIds(state);
      expect(winners, equals({'p1'}), reason: 'sole survivor always wins');
    });

    // ── Classic ───────────────────────────────────────────────────────

    test('Classic, clear top scorer → that player wins', () {
      final players = [
        Player(id: 'p1', name: 'A', color: 0xFF000001),
        Player(id: 'p2', name: 'B', color: 0xFF000002),
        Player(id: 'p3', name: 'C', color: 0xFF000003),
      ];
      final scores = {'p1': 6, 'p2': 4, 'p3': 2};
      final state = _makeState(mode: GameMode.classic, players: players, scores: scores);

      final winners = GameState.winnerIds(state);
      expect(winners, equals({'p1'}));
    });

    test('Classic, top tie → both returned', () {
      final players = [
        Player(id: 'p1', name: 'A', color: 0xFF000001),
        Player(id: 'p2', name: 'B', color: 0xFF000002),
        Player(id: 'p3', name: 'C', color: 0xFF000003),
      ];
      final scores = {'p1': 6, 'p2': 6, 'p3': 2};
      final state = _makeState(mode: GameMode.classic, players: players, scores: scores);

      final winners = GameState.winnerIds(state);
      expect(winners, equals({'p1', 'p2'}));
    });

    test('Classic, all-deadlock (all scores 0) → empty set (draw)', () {
      final players = [
        Player(id: 'p1', name: 'A', color: 0xFF000001),
        Player(id: 'p2', name: 'B', color: 0xFF000002),
        Player(id: 'p3', name: 'C', color: 0xFF000003),
      ];
      final scores = {'p1': 0, 'p2': 0, 'p3': 0};
      final state = _makeState(mode: GameMode.classic, players: players, scores: scores);

      final winners = GameState.winnerIds(state);
      expect(winners, isEmpty, reason: 'all-zero scores = draw');
    });
  });
}
