import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/data/word_packs.dart';

Widget buildGameTestApp({
  required Widget home,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: HorrorTheme.themeData,
      home: home,
    ),
  );
}

Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('ResultsScreen handles a 1-1-1 tie without throwing and shows deadlock UI', (WidgetTester tester) async {
    final container = ProviderContainer();
    final notifier = container.read(gameStateProvider.notifier);

    notifier.addPlayer('Alice', 0xFF7F77DD);
    notifier.addPlayer('Bob', 0xFF1D9E75);
    notifier.addPlayer('Charlie', 0xFFE04A4A);

    final state = container.read(gameStateProvider);
    final aliceId = state.players[0].id;
    final bobId = state.players[1].id;
    final charlieId = state.players[2].id;

    notifier.state = state.copyWith(
      mimicIds: [aliceId],
      currentWordPair: const WordPair(realWord: 'Guitar', mimicWord: 'Piano'),
      selectedMode: GameMode.classic,
    );

    final voteCounts = <String, int>{
      aliceId: 1,
      bobId: 1,
      charlieId: 1,
    };

    await tester.pumpWidget(buildGameTestApp(
      home: ResultsScreen(voteCounts: voteCounts),
      container: container,
    ));
    
    // Pump past the initial build. Should not throw TypeError.
    await pumpScreen(tester);

    // Advance to revelation phase (2s accusation + 1.5s judgment = 3.5s)
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pump(const Duration(milliseconds: 200));

    // The revelation UI should show the deadlock message.
    expect(find.text('NO ONE WAS VOTED OUT — THE VOTE WAS A DEADLOCK'), findsOneWidget);

    // Verify state. No player eliminated and outcome recorded properly.
    final finalState = container.read(gameStateProvider);
    expect(finalState.eliminatedPlayers, isEmpty);
    expect(finalState.roundOutcomes.length, 1);
    expect(finalState.roundOutcomes.first.accusedPlayerId, isNull);
  });
}
