// test/game/screens/survival_flow_test.dart
//
// F31 — Survival-mode flow correctness, after the rework:
//
// 1. Elimination is one-way. The old toggleEliminated revived any player it
//    was handed, and the results screen called it on every re-entry, so a
//    voted-out Watcher could come back to life and then be dealt the Mimic
//    role next round. That call chain no longer exists; these tests pin the
//    invariants it broke.
// 2. The game ends at TWO survivors: a further round is a guaranteed 1-1
//    voting tie with no possible elimination, so it is dead weight. The
//    score tiebreak already resolves a finished game with survivors left.
// 3. Word-reveal turns belong to alive players only — a Watcher is never
//    handed the device or announced as the next recipient.
// 4. The result screen says who was eliminated and whether the vote landed,
//    and explains the scoreboard's tiebreaker job.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/state/game_state.dart';

Widget _wrap(Widget home, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: HorrorTheme.themeData,
      home: home,
      routes: {
        '/discussion': (_) => const Scaffold(body: Text('DISCUSSION_SCREEN')),
      },
    ),
  );
}

/// Seeds a Survival round: 4 players, Bob is the Mimic, everyone votes Bob
/// out. Returns the container and the vote map to hand to ResultsScreen.
({ProviderContainer container, Map<String, int> voteCounts, List<String> ids})
    _seedSurvivalRound() {
  final container = ProviderContainer();
  final notifier = container.read(gameStateProvider.notifier);

  notifier.addPlayer('Alice', 0xFF7F77DD);
  notifier.addPlayer('Bob', 0xFF1D9E75);
  notifier.addPlayer('Cara', 0xFFD98E1D);
  notifier.addPlayer('Dan', 0xFF6E4B9E);

  final state = container.read(gameStateProvider);
  final ids = state.players.map((p) => p.id).toList();

  notifier.state = state.copyWith(
    selectedMode: GameMode.survival,
    mimicIds: [ids[1]], // Bob
    currentWordPair: const WordPair(realWord: 'Cemetery', mimicWord: 'Garden'),
  );

  return (
    container: container,
    voteCounts: <String, int>{ids[1]: 3, ids[0]: 0},
    ids: ids,
  );
}

/// Pump a couple of frames without waiting on looping animations.
Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // A · Elimination invariants (the revive bug)
  // ═══════════════════════════════════════════════════════════════════════
  group('F31-A · elimination is one-way', () {
    test('eliminatePlayer is idempotent', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Bob', 0xFF1D9E75);
      final bob = notifier.state.players.single.id;

      notifier.eliminatePlayer(bob);
      notifier.eliminatePlayer(bob);

      final bobAfter = notifier.state.players.single;
      expect(bobAfter.isAlive, isFalse);
      expect(bobAfter.isGhost, isTrue);
      expect(notifier.state.eliminatedPlayers, [bob]);
      expect(notifier.state.ghostPlayers, [bob]);
    });

    test('an eliminated player can never be dealt the Mimic role', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);
      final alice = notifier.state.players[0].id;

      notifier.eliminatePlayer(notifier.state.players[1].id);

      // Deal many times: only Alice is eligible, Bob is never the Mimic.
      for (int i = 0; i < 50; i++) {
        notifier.assignMimics();
        expect(notifier.state.mimicIds, [alice],
            reason: 'a Watcher must never be dealt the Mimic role');
      }
    });
    // __F31_A_MORE__

    test('results side effects run once: a recorded verdict is never replayed', () {
      final (:container, :voteCounts, :ids) = _seedSurvivalRound();
      final notifier = container.read(gameStateProvider.notifier);
      final bob = ids[1];

      // First verdict: eliminate Bob, award the innocents +2 each, record.
      notifier.eliminatePlayer(bob);
      notifier.updateScore(ids[0], 2);
      notifier.updateScore(ids[2], 2);
      notifier.updateScore(ids[3], 2);
      notifier.addRoundOutcome(RoundOutcome(
        round: 0,
        mimicIds: [bob],
        accusedPlayerId: bob,
      ));

      // The state contract the results-screen guard relies on: this round's
      // outcome is on record, so a re-entry is detectable — and
      // eliminatePlayer on the same id is a no-op, never a revive.
      final recorded = container
          .read(gameStateProvider)
          .roundOutcomes
          .where((o) => o.round == 0);
      expect(recorded, hasLength(1));
      expect(recorded.single.accusedPlayerId, bob);
      expect(voteCounts[bob], 3);

      notifier.eliminatePlayer(bob);
      expect(
          notifier.state.players.firstWhere((p) => p.id == bob).isAlive,
          isFalse);
      expect(notifier.state.scores[ids[0]], 2);
    });

    testWidgets('re-entering the results screen on the same votes never '
        'revives the eliminated player', (WidgetTester tester) async {
      final (:container, :voteCounts, :ids) = _seedSurvivalRound();
      final bob = ids[1];

      // First viewing — the real results screen runs its side effects.
      await tester.pumpWidget(_wrap(
        ResultsScreen(voteCounts: voteCounts),
        container,
      ));
      await tester.pump(const Duration(milliseconds: 3700));
      await tester.pump(const Duration(milliseconds: 200));

      var state = container.read(gameStateProvider);
      expect(state.players.firstWhere((p) => p.id == bob).isAlive, isFalse,
          reason: 'the voted-out player must be eliminated after the verdict');
      final scoresAfterFirst = Map<String, int>.from(state.scores);

      // Walk back and re-enter on the SAME round/votes (the old back-button
      // path). The verdict is already recorded, so this viewing must not
      // touch elimination or scores.
      await tester.pumpWidget(_wrap(
        ResultsScreen(voteCounts: voteCounts),
        container,
      ));
      await tester.pump(const Duration(milliseconds: 3700));
      await tester.pump(const Duration(milliseconds: 200));

      state = container.read(gameStateProvider);
      expect(state.players.firstWhere((p) => p.id == bob).isAlive, isFalse,
          reason: 're-entering results must never resurrect a Watcher');
      expect(state.players.where((p) => p.isAlive).length, 3);
      expect(state.scores, scoresAfterFirst,
          reason: 're-entering results must not award points twice');
      expect(
        state.roundOutcomes.where((o) => o.round == 0),
        hasLength(1),
        reason: 'the round outcome is recorded exactly once',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // B · Game over at two survivors
  // ═══════════════════════════════════════════════════════════════════════
  group('F31-B · Survival ends at two survivors', () {
    test('2 survivors = game over; 3 survivors = keep playing', () {
      final notifier = GameStateNotifier();
      for (final name in ['Alice', 'Bob', 'Cara', 'Dan']) {
        notifier.addPlayer(name, 0xFF7F77DD);
      }
      notifier.state =
          notifier.state.copyWith(selectedMode: GameMode.survival);

      expect(notifier.state.isGameOver, isFalse,
          reason: '3 survivors still have a votable round');

      notifier.eliminatePlayer(notifier.state.players[2].id);
      expect(notifier.state.isGameOver, isFalse,
          reason: '3 survivors is still playable');

      notifier.eliminatePlayer(notifier.state.players[3].id);
      expect(notifier.state.isGameOver, isTrue,
          reason: '2 survivors cannot produce a decisive vote — end the game');
    });

    test('with 2 survivors the score tiebreak decides the winner', () {
      final notifier = GameStateNotifier();
      for (final name in ['Alice', 'Bob', 'Cara']) {
        notifier.addPlayer(name, 0xFF7F77DD);
      }
      final ids = notifier.state.players.map((p) => p.id).toList();
      notifier.state = notifier.state.copyWith(
        selectedMode: GameMode.survival,
        scores: {ids[0]: 2, ids[1]: 5, ids[2]: 0},
      );

      notifier.eliminatePlayer(ids[2]);
      expect(notifier.state.isGameOver, isTrue);

      final winners = GameState.winnerIds(notifier.state);
      expect(winners, {ids[1]},
          reason: 'Bob survived with the highest score — Bob wins the tiebreak');
    });
  });
  // ═══════════════════════════════════════════════════════════════════════
  // C · Watchers take no word-reveal turn
  // ═══════════════════════════════════════════════════════════════════════
  group('F31-C · word reveal skips eliminated players', () {
    testWidgets('a Watcher is never dealt a reveal turn and never announced '
        'as the next device recipient', (WidgetTester tester) async {
      final (:container, :voteCounts, :ids) = _seedSurvivalRound();

      // Round 2 state: Bob (the Mimic) was voted out last round.
      final notifier = container.read(gameStateProvider.notifier);
      notifier.eliminatePlayer(ids[1]);
      notifier.nextRound(); // re-deals roles among the ALIVE players
      expect(
        container.read(gameStateProvider).mimicIds,
        everyElement(isNot(ids[1])),
        reason: 'precondition: the Watcher is never re-dealt as Mimic',
      );

      await tester.pumpWidget(_wrap(
        const WordRevealScreen(),
        container,
      ));
      await pumpFrames(tester);

      final state = container.read(gameStateProvider);
      final aliveIds = state.players
          .where((p) => !p.isEliminated)
          .map((p) => p.id)
          .toList();
      expect(aliveIds.length, 3);

      // Walk the whole reveal flow: every turn must be an alive player, and
      // the "hand the device to X" line must never name the Watcher.
      for (int turn = 0; turn < aliveIds.length; turn++) {
        final expectedName =
            state.players.firstWhere((p) => p.id == aliveIds[turn]).name;
        expect(find.text(expectedName.toUpperCase()), findsOneWidget,
            reason: 'turn $turn must belong to an alive player');

        await tester.tap(find.byType(GestureDetector).first);
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 100));

        final proceed = find.widgetWithText(ElevatedButton, 'PROCEED');
        final start = find.widgetWithText(ElevatedButton, 'START DISCUSSION');
        if (turn < aliveIds.length - 1) {
          expect(proceed, findsOneWidget);
          final nextName =
              state.players.firstWhere((p) => p.id == aliveIds[turn + 1]).name;
          expect(find.textContaining(nextName), findsOneWidget);
          expect(find.textContaining('BOB'), findsNothing,
              reason: 'the Watcher is never announced as the next recipient');
          await tester.tap(proceed);
          await tester.pump(const Duration(milliseconds: 300));
        } else {
          expect(start, findsOneWidget);
        }
      }

      // The header must count alive players only.
      expect(find.text('VICTIM ${aliveIds.length} OF ${aliveIds.length}'),
          findsOneWidget);
    });
  });
  // ═══════════════════════════════════════════════════════════════════════
  // D · Result screen clarity
  // ═══════════════════════════════════════════════════════════════════════
  group('F31-D · result screen clarity', () {
    testWidgets('the verdict names the eliminated player, says whether the '
        'vote landed, and explains the tiebreak',
        (WidgetTester tester) async {
      final (:container, :voteCounts, :ids) = _seedSurvivalRound();

      await tester.pumpWidget(_wrap(
        ResultsScreen(voteCounts: voteCounts),
        container,
      ));
      await tester.pump(const Duration(milliseconds: 3700));
      await tester.pump(const Duration(milliseconds: 200));

      // Bob was the Mimic and was voted out — the status card must say both
      // facts, not just "ROUND COMPLETE".
      expect(find.textContaining('was eliminated'), findsOneWidget);
      expect(find.textContaining('they were the Mimic'), findsOneWidget);
      expect(find.textContaining('ROUND COMPLETE'), findsOneWidget);

      // The scoreboard explains its tiebreaker job in Survival.
      expect(find.textContaining('Points are the tiebreaker'), findsOneWidget);

      expect(ids, hasLength(4));
    });

    testWidgets('a wrong vote says plainly that the eliminated player was '
        'NOT the Mimic', (WidgetTester tester) async {
      final (:container, :voteCounts, :ids) = _seedSurvivalRound();

      // The table votes out Alice, an innocent.
      await tester.pumpWidget(_wrap(
        ResultsScreen(voteCounts: <String, int>{ids[0]: 3}),
        container,
      ));
      await tester.pump(const Duration(milliseconds: 3700));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('was eliminated'), findsOneWidget);
      expect(find.textContaining('they were NOT the Mimic'), findsOneWidget);
      expect(find.textContaining('THE MIMIC ESCAPES'), findsOneWidget);
    });
  });
}