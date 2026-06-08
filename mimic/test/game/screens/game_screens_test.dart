// test/game/screens/game_screens_test.dart
//
// Complete widget tests and state notifier unit tests for the Mimic game layer.
// Covers:
// 1. HomeScreen
// 2. PlayerSetupScreen
// 3. WordRevealScreen & DiscussionScreen
// 4. VotingScreen
// 5. ResultsScreen
// 6. GameStateNotifier

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/mode_select_screen.dart';
import 'package:mimic/game/screens/pack_select_screen.dart';
import 'package:mimic/game/screens/player_setup_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/screens/voting_screen.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/vault/trigger/trigger_detector.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/data/word_packs.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Helper / Utility Functions
// ═══════════════════════════════════════════════════════════════════════════

Widget buildGameTestApp({
  required Widget home,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: HorrorTheme.themeData,
      home: home,
      routes: {
        '/mode-select': (_) => const ModeSelectScreen(),
        '/pack-select': (_) => const PackSelectScreen(),
        '/player-setup': (_) => const PlayerSetupScreen(),
        '/word-reveal': (_) => const WordRevealScreen(),
        '/discussion': (_) => const DiscussionScreen(),
        '/voting': (_) => const VotingScreen(),
        '/results': (_) => const Scaffold(body: Text('RESULTS_SCREEN')),
        '/vault-pin': (_) => const Scaffold(body: Text('VAULT_PIN_SCREEN')),
      },
    ),
  );
}

/// Pump a few frames to let initial build complete without waiting on looping animations.
Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Helper to build a fresh ResultsScreen with seeded state.
Future<({ProviderContainer container, Map<String, int> voteCounts})>
    buildResultsState() async {
  final container = ProviderContainer();
  final notifier = container.read(gameStateProvider.notifier);

  notifier.addPlayer('Alice', 0xFF7F77DD);
  notifier.addPlayer('Bob', 0xFF1D9E75);

  final state = container.read(gameStateProvider);
  final aliceId = state.players[0].id;
  final bobId = state.players[1].id;

  notifier.state = state.copyWith(
    mimicIds: [aliceId],
    currentWordPair: const WordPair(realWord: 'Guitar', mimicWord: 'Piano'),
  );

  return (container: container, voteCounts: <String, int>{aliceId: 2, bobId: 0});
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests Main Entry
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  setUp(() {
    TriggerCallbackRegistry().setOnTap(null);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1 · HomeScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('1 · HomeScreen', () {
    testWidgets('Renders MIMIC logo, Play button, and Particle animation CustomPaint',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(home: const HomeScreen(), container: container));
      await pumpScreen(tester);

      expect(find.text('MIMIC'), findsOneWidget);

      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is FogPainter,
        ),
        findsOneWidget,
        reason: 'FogPainter CustomPaint must be present on HomeScreen',
      );

      final beginButton = find.widgetWithText(ElevatedButton, 'BEGIN');
      expect(beginButton, findsOneWidget);

      await tester.tap(beginButton);
      await pumpScreen(tester);

      expect(find.byType(ModeSelectScreen), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2 · PlayerSetupScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('2 · PlayerSetupScreen', () {
    testWidgets('Adds player textfields, enforces play capacity limits, and navigates',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(home: const PlayerSetupScreen(), container: container));
      await pumpScreen(tester);

      expect(find.byType(TextField), findsNWidgets(2));

      final startGameFinder = find.widgetWithText(ElevatedButton, 'START GAME');
      expect(startGameFinder, findsOneWidget);
      ElevatedButton startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNull,
          reason: 'START GAME must be disabled with less than 2 named players');

      final addPlayerButton = find.widgetWithText(OutlinedButton, 'ADD PLAYER');
      expect(addPlayerButton, findsOneWidget);
      await tester.tap(addPlayerButton);
      await pumpScreen(tester);

      expect(find.byType(TextField), findsNWidgets(3));

      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'Bob');
      await pumpScreen(tester);

      startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNotNull,
          reason: 'START GAME must be enabled when 2+ named players are populated');

      await tester.tap(startGameFinder);
      await pumpScreen(tester);

      // Navigates to PackSelectScreen (mimic assigned there, not here)
      expect(find.byType(PackSelectScreen), findsOneWidget);

      final state = container.read(gameStateProvider);
      expect(state.players.length, 2);
      expect(state.players[0].name, 'Alice');
      expect(state.players[1].name, 'Bob');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3 · WordRevealScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('3 · WordRevealScreen', () {
    testWidgets('Each player views word privately, shows Mimic role, and navigates to discussion',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      final state = container.read(gameStateProvider);
      final aliceId = state.players[0].id;

      notifier.state = state.copyWith(
        mimicIds: [aliceId],
        currentWordPair: const WordPair(realWord: 'Guitar', mimicWord: 'Piano'),
      );

      await tester.pumpWidget(buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);

      // Alice cover screen
      expect(find.text('ALICE'), findsOneWidget);
      expect(find.text('TAP TO SEE YOUR FATE'), findsOneWidget);

      // Tap to reveal
      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      expect(find.text('YOU ARE THE MIMIC'), findsOneWidget);

      // Wait for auto-advance timer (3s)
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));

      // Pass screen — tap PROCEED to go to Bob
      expect(find.widgetWithText(ElevatedButton, 'PROCEED'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'PROCEED'));
      await pumpScreen(tester);

      // Bob cover screen
      expect(find.text('BOB'), findsOneWidget);

      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      expect(find.text('REMEMBER YOUR WORD'), findsOneWidget);

      // Wait for auto-advance timer (3s)
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));

      // Bob is last player — START DISCUSSION appears
      final startDiscButton = find.widgetWithText(ElevatedButton, 'START DISCUSSION');
      expect(startDiscButton, findsOneWidget);

      await tester.tap(startDiscButton);
      await pumpScreen(tester);

      expect(find.text('DISCUSSION'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4 · VotingScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('4 · VotingScreen', () {
    testWidgets('Renders all player cards, handles votes, displays reveal button, and contains invisible detector',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      await tester.pumpWidget(buildGameTestApp(home: const VotingScreen(), container: container));
      await pumpScreen(tester);

      expect(find.text('ALICE'), findsOneWidget);
      expect(find.text('BOB'), findsOneWidget);
      expect(find.text('VOTER: ALICE'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'REVEAL RESULTS'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'SUBMIT VOTE'), findsOneWidget);

      // Alice selects Bob, submits
      await tester.tap(find.text('BOB'));
      await pumpScreen(tester);
      final submitBtn = find.widgetWithText(ElevatedButton, 'SUBMIT VOTE');
      expect(tester.widget<ElevatedButton>(submitBtn).onPressed, isNotNull);
      await tester.tap(submitBtn);
      await pumpScreen(tester);

      expect(find.text('VOTER: BOB'), findsOneWidget);

      // Bob selects Alice, submits
      await tester.tap(find.text('ALICE'));
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'SUBMIT VOTE'));
      await pumpScreen(tester);

      expect(find.text('ALL VOTES LOCKED IN'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'REVEAL RESULTS'), findsOneWidget);

      final detectorFinder = find.byType(TriggerDetector);
      expect(detectorFinder, findsOneWidget);

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(of: detectorFinder, matching: find.byType(SizedBox)),
      );
      expect(sizedBox.width, double.infinity);
      expect(sizedBox.height, double.infinity);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5 · ResultsScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('5 · ResultsScreen', () {
    testWidgets('Plays reveal animation, displays scores, and TriggerDetector is present',
        (WidgetTester tester) async {
      final (:container, :voteCounts) = await buildResultsState();

      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await pumpScreen(tester);

      // Accusation phase — action buttons absent
      expect(find.text('NEXT ROUND'), findsNothing);

      // Advance to revelation phase (2s accusation + 1.5s judgment = 3.5s)
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 200));

      // Revelation phase — mimic name + banner + scoreboard visible
      expect(find.text('ALICE'), findsAtLeastNWidgets(1));
      expect(find.text('THE MIMIC HAS BEEN FOUND'), findsOneWidget);
      expect(find.text('SCOREBOARD'), findsOneWidget);

      // TriggerDetector overlay is present
      expect(find.byType(TriggerDetector), findsOneWidget);
    });

    testWidgets('NEXT ROUND navigates to WordRevealScreen',
        (WidgetTester tester) async {
      final (:container, :voteCounts) = await buildResultsState();

      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await pumpScreen(tester);

      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 200));

      final nextRoundBtn = find.widgetWithText(ElevatedButton, 'NEXT ROUND');
      expect(nextRoundBtn, findsOneWidget);
      await tester.tap(nextRoundBtn);
      await pumpScreen(tester);

      expect(find.byType(WordRevealScreen), findsOneWidget);
    });

    testWidgets('END GAME resets state and navigates to PlayerSetupScreen',
        (WidgetTester tester) async {
      final (:container, :voteCounts) = await buildResultsState();

      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await pumpScreen(tester);

      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 200));

      final endGameBtn = find.widgetWithText(OutlinedButton, 'END GAME');
      expect(endGameBtn, findsOneWidget);
      await tester.tap(endGameBtn);
      await pumpScreen(tester);

      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(container.read(gameStateProvider).players.length, 0,
          reason: 'End Game must clear/reset all players from state');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6 · GameStateNotifier Unit Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('6 · GameStateNotifier', () {
    test('addPlayer adds player to player list and score records', () {
      final notifier = GameStateNotifier();
      expect(notifier.state.players, isEmpty);

      notifier.addPlayer('Alice', 0xFF7F77DD);
      expect(notifier.state.players.length, 1);
      expect(notifier.state.players[0].name, 'Alice');
      expect(notifier.state.scores[notifier.state.players[0].id], 0);
    });

    test('removePlayer removes player and deletes score entry', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Alice', 0xFF7F77DD);
      final playerId = notifier.state.players[0].id;

      notifier.removePlayer(playerId);
      expect(notifier.state.players, isEmpty);
      expect(notifier.state.scores, isEmpty);
    });

    test('assignMimic selects a random player from list as the Mimic', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      notifier.assignMimic();
      expect(notifier.state.mimicId, isNotNull);
      final playerIds = notifier.state.players.map((p) => p.id).toList();
      expect(playerIds.contains(notifier.state.mimicId), isTrue);
    });

    test('updateScore updates player score records', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Alice', 0xFF7F77DD);
      final playerId = notifier.state.players[0].id;

      notifier.updateScore(playerId, 10);
      expect(notifier.state.scores[playerId], 10);
    });

    test('resetGame returns state to fresh default state', () {
      final notifier = GameStateNotifier();
      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.assignMimic();
      notifier.updateScore(notifier.state.players[0].id, 5);

      notifier.resetGame();
      expect(notifier.state.players, isEmpty);
      expect(notifier.state.scores, isEmpty);
      expect(notifier.state.mimicId, isNull);
      expect(notifier.state.currentRound, 0);
    });
  });
}
