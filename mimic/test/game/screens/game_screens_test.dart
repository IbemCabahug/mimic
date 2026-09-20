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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/game/screens/home_screen.dart';
import 'package:mimic/game/screens/mode_select_screen.dart';
import 'package:mimic/game/screens/pack_select_screen.dart';
import 'package:mimic/game/screens/player_setup_screen.dart';
import 'package:mimic/game/screens/word_reveal_screen.dart';
import 'package:mimic/game/screens/voting_screen.dart';
import 'package:mimic/game/screens/final_standings_screen.dart';
import 'package:mimic/game/screens/results_screen.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/vault/trigger/trigger_detector.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/services/quick_entry_service.dart';

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
        '/final-standings': (_) => const FinalStandingsScreen(),
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

// ═══════════════════════════════════════════════════════════════════════════
// F27 helpers — in-memory secure storage + network stub for the Pro
// quick-entry long-press matrix (no device, no plugin channels).
// ═══════════════════════════════════════════════════════════════════════════

class _F27FakePlatform implements PlatformService {
  final Map<String, String> store = {};

  @override
  bool isWeb() => false;

  @override
  Future<String?> secureRead(String key) async => store[key];

  @override
  Future<Map<String, String>> secureReadAll() async => Map.from(store);

  @override
  Future<void> secureWrite(String key, String value) async {
    store[key] = value;
  }

  @override
  Future<void> secureDelete(String key) async {
    store.remove(key);
  }

  @override
  Future<void> saveEncryptedFile(String path, Uint8List data) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List?> readEncryptedFile(String path) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteFile(String path) async => throw UnimplementedError();

  @override
  Future<File> resolveVaultFile(String path) async =>
      throw UnimplementedError();
}

/// NetworkService stub whose only job is to answer [role] — the one thing
/// [isMultiplayerSessionActive] consults on the entry path.
class _StubNetworkService extends NetworkService {
  _StubNetworkService(NetworkRole role) : _stubRole = role;
  final NetworkRole _stubRole;

  @override
  NetworkRole get role => _stubRole;
}

/// Pro install, preference ON, vault exists, not concealed — the fully
/// allowed environment. Individual tests break one condition at a time.
_F27FakePlatform _readyF27Platform() {
  final fake = _F27FakePlatform();
  fake.store[proEntitlementKey] = proEntitlementValue;
  fake.store[quickEntryEnabledKey] = quickEntryEnabledValue;
  fake.store[quickEntryVaultSaltKey] = 'a-salt';
  fake.store[quickEntryVaultConcealedKey] = 'false';
  return fake;
}

ProviderContainer _f27Container(
  _F27FakePlatform fake, {
  NetworkRole role = NetworkRole.none,
  // true pins the billing-era gate (the entitlement key decides); false
  // exercises the pre-billing launch window where isPro() answers true for
  // every install and no entitlement is needed.
  bool billingEnforced = true,
}) {
  return ProviderContainer(overrides: [
    platformServiceProvider.overrideWithValue(fake),
    if (billingEnforced)
      proStatusServiceProvider
          .overrideWith((ref) => ProStatusService(fake, billingEnforced: true)),
    if (role != NetworkRole.none)
      networkServiceProvider.overrideWith((ref) => _StubNetworkService(role)),
  ]);
}

/// Pump HomeScreen, long-press the MIMIC title, then pump enough frames
/// for the async gate to finish and any navigation to render.
Future<void> pumpHomeAndLongPress(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    buildGameTestApp(home: const HomeScreen(), container: container),
  );
  await pumpScreen(tester);
  await tester.longPress(find.text('MIMIC'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
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
  // F27 · Pro quick-entry long-press on the MIMIC title
  // ═══════════════════════════════════════════════════════════════════════
  group('F27 · quick-entry long-press', () {
    testWidgets('free user: long-press stays an ordinary game tap',
        (WidgetTester tester) async {
      // Preference left ON with a vault present — ONLY the entitlement is
      // missing, and that alone must deny (disguise preservation: no
      // navigation, no error, nothing to notice).
      final fake = _readyF27Platform()
        ..store.remove(proEntitlementKey);
      await pumpHomeAndLongPress(tester, _f27Container(fake));

      expect(find.text('VAULT_PIN_SCREEN'), findsNothing);
      expect(find.text('MIMIC'), findsOneWidget);
    });

    testWidgets('pro but preference off: nothing happens (default OFF holds)',
        (WidgetTester tester) async {
      final fake = _readyF27Platform()
        ..store.remove(quickEntryEnabledKey);
      await pumpHomeAndLongPress(tester, _f27Container(fake));

      expect(find.text('VAULT_PIN_SCREEN'), findsNothing);
    });

    testWidgets('pro + on but no vault exists: nothing happens',
        (WidgetTester tester) async {
      final fake = _readyF27Platform()
        ..store.remove(quickEntryVaultSaltKey);
      await pumpHomeAndLongPress(tester, _f27Container(fake));

      expect(find.text('VAULT_PIN_SCREEN'), findsNothing);
    });

    testWidgets('pro + on but the vault is concealed: nothing happens',
        (WidgetTester tester) async {
      final fake = _readyF27Platform()
        ..store[quickEntryVaultConcealedKey] = quickEntryVaultConcealedValue;
      await pumpHomeAndLongPress(tester, _f27Container(fake));

      expect(find.text('VAULT_PIN_SCREEN'), findsNothing);
    });

    testWidgets('everything set: long-press lands on the PIN screen, which still does the authentication',
        (WidgetTester tester) async {
      await pumpHomeAndLongPress(tester, _f27Container(_readyF27Platform()));

      expect(find.text('VAULT_PIN_SCREEN'), findsOneWidget);
      // Home stays underneath (pushNamed, not replacement).
      expect(find.text('MIMIC'), findsOneWidget);
    });

    testWidgets('multiplayer session active: denied even when everything else is on',
        (WidgetTester tester) async {
      await pumpHomeAndLongPress(
        tester,
        _f27Container(_readyF27Platform(), role: NetworkRole.host),
      );

      expect(find.text('VAULT_PIN_SCREEN'), findsNothing);
    });

    testWidgets('PRE-BILLING WINDOW: no entitlement, everything else on — the long-press still opens the PIN screen (kBillingEnforced == false)',
        (WidgetTester tester) async {
      // The launch window reads Pro for every install before storage is
      // consulted, so early downloaders get the quick entry without any
      // Play entitlement. The other checks (preference, vault, conceal)
      // keep doing their job.
      final fake = _readyF27Platform()
        ..store.remove(proEntitlementKey);
      await pumpHomeAndLongPress(
        tester,
        _f27Container(fake, billingEnforced: false),
      );

      expect(find.text('VAULT_PIN_SCREEN'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2a · PLAY AGAIN roster keeps a back button (F31)
  // ═══════════════════════════════════════════════════════════════════════
  // Owner report: after a finished game (Survival in particular), PLAY AGAIN
  // wiped the whole route stack, so Roster Setup was the ONLY route and the
  // app bar showed no back arrow — the player was stranded. The fix keeps the
  // home route ('/') beneath the roster: stale game screens are still
  // removed, but back (arrow, system back, swipe) now returns home.
  group('2a · PLAY AGAIN roster back button', () {
    testWidgets('PLAY AGAIN leaves home beneath the roster and the back arrow works',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(
        home: const Scaffold(body: Text('GAME_HOME')),
        container: container,
      ));
      await pumpScreen(tester);

      // End of a game: final standings sits on top of home.
      Navigator.of(tester.element(find.text('GAME_HOME')))
          .pushNamed('/final-standings');
      await pumpScreen(tester);

      await tester.tap(find.text('PLAY AGAIN'));
      await pumpScreen(tester);

      // Roster is up — and it is NOT a stranded root: the back arrow exists
      // because home is still beneath it.
      expect(find.text('ROSTER SETUP'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget,
          reason: 'the PLAY AGAIN roster must keep a way back to home');

      await tester.tap(find.byType(BackButton));
      // Two pumps > the 300ms pop transition, so the roster route is really
      // gone from the stack before the assertion runs.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('GAME_HOME'), findsOneWidget,
          reason: 'back must land on the game home screen');
      expect(find.text('ROSTER SETUP'), findsNothing);

      // The stale game screens were still cleared by PLAY AGAIN: nothing but
      // home and the roster ever existed above home.
      expect(find.text('FINAL STANDINGS'), findsNothing);
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

      // Starts with 3 text fields by default
      expect(find.byType(TextField), findsNWidgets(3));

      final startGameFinder = find.widgetWithText(ElevatedButton, 'START GAME');
      expect(startGameFinder, findsOneWidget);
      ElevatedButton startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNull,
          reason: 'START GAME must be disabled with less than 3 named players');

      final addPlayerButton = find.widgetWithText(OutlinedButton, 'ADD PLAYER');
      expect(addPlayerButton, findsOneWidget);
      await tester.tap(addPlayerButton);
      await pumpScreen(tester);

      // Now 4 fields
      expect(find.byType(TextField), findsNWidgets(4));

      await tester.enterText(find.byType(TextField).at(0), 'Alice');
      await tester.enterText(find.byType(TextField).at(1), 'Bob');
      await pumpScreen(tester);

      // Still disabled because only 2 players are named
      startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNull,
          reason: 'START GAME must be disabled with only 2 named players');

      // Add third player
      await tester.enterText(find.byType(TextField).at(2), 'Charlie');
      await pumpScreen(tester);

      startGameButton = tester.widget<ElevatedButton>(startGameFinder);
      expect(startGameButton.onPressed, isNotNull,
          reason: 'START GAME must be enabled when 3+ named players are populated');

      await tester.tap(startGameFinder);
      await pumpScreen(tester);

      // Navigates to PackSelectScreen (mimic assigned there, not here)
      expect(find.byType(PackSelectScreen), findsOneWidget);

      final state = container.read(gameStateProvider);
      expect(state.players.length, 3);
      expect(state.players[0].name, 'Alice');
      expect(state.players[1].name, 'Bob');
      expect(state.players[2].name, 'Charlie');
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

    testWidgets('Word context: the info button opens the describing-angles sheet and pauses the auto-hide',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);

      final state = container.read(gameStateProvider);
      notifier.state = state.copyWith(
        currentWordPair: const WordPair(
          realWord: 'Cemetery',
          mimicWord: 'Garden',
          realWordContext:
              'Rows of carved stone markers, mourners leaving flowers.',
          mimicWordContext: 'Tended beds of blooms and a watering can.',
        ),
      );

      await tester.pumpWidget(
          buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);

      // Alice is not the Mimic — reveal shows her real word and the button.
      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      expect(find.text('REMEMBER YOUR WORD'), findsOneWidget);
      expect(find.text('NEED DESCRIBING ANGLES?'), findsOneWidget);

      // The sheet carries HER word's context (the real side).
      // Fixed pumps, never pumpAndSettle: this screen's horror widgets
      // animate forever, so settling would time out.
      await tester.tap(find.text('NEED DESCRIBING ANGLES?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('DESCRIBING ANGLES'), findsOneWidget);
      expect(find.text('Rows of carved stone markers, mourners leaving flowers.'),
          findsOneWidget);

      // The 3-second auto-hide is paused while the sheet is open: after
      // four seconds the screen is still in the revealed state.
      await tester.pump(const Duration(seconds: 4));
      expect(find.widgetWithText(ElevatedButton, 'PROCEED'), findsNothing);
      expect(find.text('DESCRIBING ANGLES'), findsOneWidget);

      // Closing the sheet starts a fresh 3-second window. Any dismissal
      // path (the GOT IT button, a barrier tap, a swipe) restarts the
      // countdown, so five seconds of pumping covers whichever frame
      // scheduled it.
      await tester.tap(find.widgetWithText(ElevatedButton, 'GOT IT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('DESCRIBING ANGLES'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 100));
      // Alice is the only player, so she is the last player — the pass
      // screen offers START DISCUSSION rather than PROCEED.
      expect(find.text('PASS THE DEVICE'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'START DISCUSSION'),
          findsOneWidget);
    });

    testWidgets('Word context: a Mimic sees their own word context, never the real side',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);

      final state = container.read(gameStateProvider);
      final aliceId = state.players[0].id;
      notifier.state = state.copyWith(
        mimicIds: [aliceId],
        currentWordPair: const WordPair(
          realWord: 'Cemetery',
          mimicWord: 'Garden',
          realWordContext:
              'Rows of carved stone markers, mourners leaving flowers.',
          mimicWordContext: 'Tended beds of blooms and a watering can.',
        ),
      );

      await tester.pumpWidget(
          buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);

      // Alice is the Mimic — the sheet must describe HER word, not the real one.
      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);
      expect(find.text('YOU ARE THE MIMIC'), findsOneWidget);

      await tester.tap(find.text('NEED DESCRIBING ANGLES?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tended beds of blooms and a watering can.'), findsOneWidget);
      expect(find.text('Rows of carved stone markers, mourners leaving flowers.'),
          findsNothing);
    });

    testWidgets('Word context: a pair without authored context renders no button at all',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      final notifier = container.read(gameStateProvider.notifier);

      notifier.addPlayer('Alice', 0xFF7F77DD);

      // No contexts (the shape of unauthored languages and pairs synced
      // from older peers) — the button must be absent entirely.
      final state = container.read(gameStateProvider);
      notifier.state = state.copyWith(
        currentWordPair: const WordPair(realWord: 'Guitar', mimicWord: 'Piano'),
      );

      await tester.pumpWidget(
          buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);

      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      expect(find.text('REMEMBER YOUR WORD'), findsOneWidget);
      expect(find.text('NEED DESCRIBING ANGLES?'), findsNothing);
    });

    testWidgets('Word context: a Pro install sees the DETAILED angles',
        (WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        isProProvider.overrideWith((ref) => true),
      ]);
      final notifier = container.read(gameStateProvider.notifier);
      notifier.addPlayer('Alice', 0xFF7F77DD);

      final state = container.read(gameStateProvider);
      notifier.state = state.copyWith(
        currentWordPair: const WordPair(
          realWord: 'Cemetery',
          mimicWord: 'Garden',
          realWordContext: 'General angles: mood, quiet, respect.',
          realWordProContext: 'Detailed angles: angels, slabs, marble, lilies.',
        ),
      );

      await tester.pumpWidget(
          buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);
      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      await tester.tap(find.text('NEED DESCRIBING ANGLES?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Detailed angles: angels, slabs, marble, lilies.'),
          findsOneWidget);
      expect(find.text('General angles: mood, quiet, respect.'), findsNothing);
    });

    testWidgets('Word context: a free install sees the GENERALIZED angles',
        (WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        isProProvider.overrideWith((ref) => false),
      ]);
      final notifier = container.read(gameStateProvider.notifier);
      notifier.addPlayer('Alice', 0xFF7F77DD);

      final state = container.read(gameStateProvider);
      notifier.state = state.copyWith(
        currentWordPair: const WordPair(
          realWord: 'Cemetery',
          mimicWord: 'Garden',
          realWordContext: 'General angles: mood, quiet, respect.',
          realWordProContext: 'Detailed angles: angels, slabs, marble, lilies.',
        ),
      );

      await tester.pumpWidget(
          buildGameTestApp(home: const WordRevealScreen(), container: container));
      await pumpScreen(tester);
      await tester.tap(find.byType(GestureDetector).first);
      await pumpScreen(tester);

      await tester.tap(find.text('NEED DESCRIBING ANGLES?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('General angles: mood, quiet, respect.'), findsOneWidget);
      expect(find.text('Detailed angles: angels, slabs, marble, lilies.'),
          findsNothing);
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

    testWidgets('END GAME resets state and navigates to home',
        (WidgetTester tester) async {
      final (:container, :voteCounts) = await buildResultsState();

      // Home is the REAL HomeScreen so navigating to '/' (homeRoute) lands here.
      await tester.pumpWidget(buildGameTestApp(
        home: const HomeScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      // Reach ResultsScreen the way the app does — pushed on top of home.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute(
        builder: (_) => ResultsScreen(voteCounts: voteCounts),
      ));
      await pumpScreen(tester);

      // Let the reveal animation finish so the action buttons render.
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 200));

      final endGameBtn = find.widgetWithText(OutlinedButton, 'END GAME');
      expect(endGameBtn, findsOneWidget);
      await tester.tap(endGameBtn);
      // Let pushNamedAndRemoveUntil finish: the new HomeScreen animates in and the
      // old ResultsScreen route is removed and disposed. Use fixed pumps (NOT
      // pumpAndSettle) because ResultsScreen has looping animations.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ResultsScreen), findsNothing);
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
