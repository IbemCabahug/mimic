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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/game/game.dart';
import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/player_setup_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/screens/voting_screen.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/vault/trigger/trigger_detector.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Helper / Utility Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Build a standard MaterialApp containing Riverpod overrides and routing tables for game screens.
Widget buildGameTestApp({
  required Widget home,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: gameTheme,
      home: home,
      routes: {
        '/': (_) => const HomeScreen(),
        '/player-setup': (_) => const PlayerSetupScreen(),
        '/word-reveal': (_) => const WordRevealScreen(),
        '/discussion': (_) => const DiscussionScreen(),
        '/voting': (_) => const VotingScreen(),
        '/results': (_) => const ResultsScreen(),
        '/vault-pin': (_) => const Scaffold(body: Text('VAULT_PIN_SCREEN')),
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests Main Entry
// ═══════════════════════════════════════════════════════════════════════

void main() {
  // Reset singleton callback registry before tests
  setUp(() {
    TriggerCallbackRegistry().setOnTap(null);
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1 · HomeScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('1 · HomeScreen', () {
    testWidgets('Renders MIMIC logo, Play button, and Particle animation CustomPaint', (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(home: const HomeScreen(), container: container));
      await tester.pumpAndSettle();

      // Verify the MIMIC logo text renders
      expect(find.text('MIMIC'), findsOneWidget);

      // Verify the particle animation widget is present (represented by CustomPaint using ParticlePainter)
      expect(
        find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is ParticlePainter,
        ),
        findsOneWidget,
        reason: 'Particle animation CustomPaint must be present on HomeScreen',
      );

      // Verify Play button is present and navigates to PlayerSetupScreen on click
      final playButton = find.widgetWithText(ElevatedButton, 'Play');
      expect(playButton, findsOneWidget);

      await tester.tap(playButton);
      await tester.pumpAndSettle();

      // Assert we navigated to PlayerSetupScreen
      expect(find.text('Player Setup'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2 · PlayerSetupScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('2 · PlayerSetupScreen', () {
    testWidgets('Adds player textfields, enforces play capacity limits, and navigates', (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(home: const PlayerSetupScreen(), container: container));
      await tester.pumpAndSettle();

      // Initially, 2 blank fields are rendered.
      expect(find.byType(TextField), findsNWidgets(2));

      // Start Game should be disabled because names are empty
      final startGameFinder = find.widgetWithText(ElevatedButton, 'Start Game');
      expect(startGameFinder, findsOneWidget);
      ElevatedButton startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNull,
          reason: 'Start Game must be disabled with less than 2 named players');

      // Tap 'Add Player' button
      final addPlayerButton = find.widgetWithText(OutlinedButton, 'Add Player');
      expect(addPlayerButton, findsOneWidget);
      await tester.tap(addPlayerButton);
      await tester.pumpAndSettle();

      // Third TextField entry should be added
      expect(find.byType(TextField), findsNWidgets(3));

      // Populate names for the first two players to satisfy start conditions (2+ named players)
      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'Bob');
      await tester.pumpAndSettle();

      // Start Game should now be enabled
      startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNotNull,
          reason: 'Start Game must be enabled when 2+ named players are populated');

      // Tap Start Game
      await tester.tap(startGameFinder);
      await tester.pumpAndSettle();

      // Verify we navigated to WordRevealScreen
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Pass the phone to this player'), findsOneWidget);

      // Verify player records were successfully populated in Riverpod state container
      final state = container.read(gameStateProvider);
      expect(state.players.length, 2);
      expect(state.players[0].name, 'Alice');
      expect(state.players[1].name, 'Bob');
      expect(state.mimicId, isNotNull,
          reason: 'StateNotifier must automatically assign a player as the Mimic');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3 · WordRevealScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('3 · WordRevealScreen', () {
    testWidgets('Each player views word privately, shows Mimic role, and navigates to discussion', (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      // Seed 2 players
      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      final state = container.read(gameStateProvider);
      final aliceId = state.players[0].id;
      final bobId = state.players[1].id;

      // Force Alice to be the Mimic for testing predictability
      notifier.state = state.copyWith(
        mimicId: aliceId,
        currentWord: 'Guitar',
      );

      await tester.pumpWidget(buildGameTestApp(home: const WordRevealScreen(), container: container));
      await tester.pumpAndSettle();

      // 1. Alice (Mimic) views word
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Tap to reveal your word'), findsOneWidget);

      // Tap Reveal
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reveal'));
      await tester.pumpAndSettle();

      // Alice should see her decoy Mimic word and role banner
      expect(find.text('You are the Mimic!'), findsOneWidget);

      // Tap Next Player
      await tester.tap(find.widgetWithText(ElevatedButton, 'Next Player'));
      await tester.pumpAndSettle();

      // 2. Bob (Real Player) views word
      expect(find.text('Bob'), findsOneWidget);

      // Tap Reveal
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reveal'));
      await tester.pumpAndSettle();

      // Bob should see the real word message
      expect(find.text('Remember your word!'), findsOneWidget);

      // Since Bob is the final player, 'Start Discussion' button appears
      final startDiscButton = find.widgetWithText(ElevatedButton, 'Start Discussion');
      expect(startDiscButton, findsOneWidget);

      // Tap Start Discussion
      await tester.tap(startDiscButton);
      await tester.pumpAndSettle();

      // Verify navigation to DiscussionScreen
      expect(find.text('Discussion'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4 · VotingScreen Tests
  // ═══════════════════════════════════════════════════════════════════════
  group('4 · VotingScreen', () {
    testWidgets('Renders all player cards, handles votes, displays reveal button, and contains invisible detector', (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      await tester.pumpWidget(buildGameTestApp(home: const VotingScreen(), container: container));
      await tester.pumpAndSettle();

      // Verify both player cards are rendered
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Voter is Alice initially, and Reveal Results button is absent
      expect(find.text('Voter: Alice'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Reveal Results'), findsNothing);

      // Alice votes for Bob
      await tester.tap(find.widgetWithText(ElevatedButton, 'Bob'));
      await tester.pumpAndSettle();

      // Voter is Bob now
      expect(find.text('Voter: Bob'), findsOneWidget);

      // Bob votes for Alice
      await tester.tap(find.widgetWithText(ElevatedButton, 'Alice'));
      await tester.pumpAndSettle();

      // Both players voted
      expect(find.text('All Voted'), findsOneWidget);
      
      // Reveal Results button becomes visible
      final revealResultsFinder = find.widgetWithText(ElevatedButton, 'Reveal Results');
      expect(revealResultsFinder, findsOneWidget);

      // TriggerDetector is present and invisible (transparent SizedBox.expand)
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
    testWidgets('Plays reveal animation, displays scores, navigation buttons function, and has invisible detector', (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);
      notifier.addPlayer('Bob', 0xFF1D9E75);

      final state = container.read(gameStateProvider);
      final aliceId = state.players[0].id;
      final bobId = state.players[1].id;

      notifier.state = state.copyWith(
        mimicId: aliceId,
        currentWord: 'Guitar',
      );

      final voteCounts = {aliceId: 2, bobId: 0};

      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await tester.pumpAndSettle();

      // Initially, Mimic identity remains hidden (animation has not fired)
      expect(find.text('Alice'), findsNothing);

      // Advance clock past 1.5 seconds to play reveal animation
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // Mimic name and victory/defeat messages render
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('The group correctly identified the Mimic!'), findsOneWidget);
      expect(find.text('Scoreboard'), findsOneWidget);

      // Test "Play Again" button navigates back to word reveal
      final playAgainBtn = find.widgetWithText(ElevatedButton, 'Play Again');
      expect(playAgainBtn, findsOneWidget);
      await tester.tap(playAgainBtn);
      await tester.pumpAndSettle();
      expect(find.byType(WordRevealScreen), findsOneWidget);

      // Rebuild and reveal to test "New Game"
      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // Test "New Game" resets game state and redirects to player setup
      final newGameBtn = find.widgetWithText(OutlinedButton, 'New Game');
      expect(newGameBtn, findsOneWidget);
      await tester.tap(newGameBtn);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerSetupScreen), findsOneWidget);
      expect(container.read(gameStateProvider).players.length, 0,
          reason: 'New Game must clear/reset all players from state');

      // Verify TriggerDetector overlay is present and invisible
      expect(find.byType(TriggerDetector), findsOneWidget);
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
