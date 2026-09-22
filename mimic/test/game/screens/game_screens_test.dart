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
import 'package:mimic/game/screens/admin_panel_screen.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/vault/trigger/trigger_detector.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/core/services/platform_service.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/vault/services/pro_status_service.dart';
import 'package:mimic/vault/services/quick_entry_service.dart';
import 'package:mimic/vault/security/secret_entry_trail.dart';
import 'package:mimic/game/game.dart';

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
  // 5b · AdminPanelScreen — the duress decoy must be escapable
  // ═══════════════════════════════════════════════════════════════════════
  group('5b · AdminPanelScreen exit', () {
    // The trail is process-wide static state; every case must start from a
    // clean slate so test order can never decide where the exit lands.
    setUp(() {
      SecretEntryTrail.clear();
    });

    testWidgets(
        'the duress decoy shows a leading RETURN TO GAME tile that returns to the game',
        (WidgetTester tester) async {
      // Taller viewport so the first two tiles are laid out (the exit must be
      // reachable without scrolling — that is the whole point of leading
      // with it).
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      // Home is the REAL HomeScreen so leaving the panel via '/' lands here.
      await tester.pumpWidget(buildGameTestApp(
        home: const HomeScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      // Enter the duress path the way PIN entry does: the decoy is pushed by
      // name and replaces the PIN screen, so it has NO app-bar back arrow —
      // this tile is the only way out.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute(
        builder: (_) => const AdminPanelScreen(),
      ));
      await pumpScreen(tester);

      expect(find.text('ADMIN PANEL'), findsOneWidget,
          reason: 'The duress PIN must land on the harmless decoy panel');

      // The exit exists, sits above every piece of game intel, and is the
      // first thing a confused bystander sees.
      expect(find.text('RETURN TO GAME'), findsOneWidget,
          reason: 'The decoy panel must offer a visible way back to the game');
      expect(
        tester.getTopLeft(find.text('RETURN TO GAME')).dy,
        lessThan(tester.getTopLeft(find.text('Reveal Mimic')).dy),
        reason: 'The exit must lead the list, before any cheat tile',
      );

      // Tapping it leaves the panel and lands on the game home screen — and
      // never in the vault.
      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'RETURN TO GAME must remove the decoy panel from the stack');
      expect(find.text('MIMIC'), findsOneWidget,
          reason: 'RETURN TO GAME must land on the game home screen');
      expect(find.text('VAULT_PIN_SCREEN'), findsNothing,
          reason: 'The duress exit must never lead into the real vault');
    });

    testWidgets(
        'system BACK on the decoy lands on the game even when nothing sits below it',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(
        home: const HomeScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      // The harsh shape: AutoLock / the vault lock button / Settings → Lock
      // Vault all push '/vault-pin' with pushNamedAndRemoveUntil, so entering
      // duress there replaces the ONLY route. This mirrors it.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
        (route) => false,
      );
      await pumpScreen(tester);
      expect(find.byType(AdminPanelScreen), findsOneWidget);

      // Android system BACK, the way a bystander leaves without reading.
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'System BACK must not leave the decoy panel on screen');
      expect(find.text('MIMIC'), findsOneWidget,
          reason: 'System BACK must land on the game home screen, '
              'not a vault route and not a closing app');
      expect(find.text('VAULT_PIN_SCREEN'), findsNothing,
          reason: 'System BACK must never lead into the real vault');
    });

    testWidgets(
        'every tile paints on its own Material, so a tap still ripples',
        (WidgetTester tester) async {
      // ListTile paints its background and ink splash on the nearest Material
      // ancestor. The tiles sit inside a rounded surface, and a
      // colour-decorated Container in that position hides the ripple (on a
      // decoy panel a curious bystander is meant to poke at) and reports
      // "ListTile background color or ink splashes may be invisible" on every
      // build — an uncaught FlutterError that fails any widget test which
      // renders this screen.
      final container = ProviderContainer();
      await tester.pumpWidget(buildGameTestApp(
        home: const AdminPanelScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      expect(find.byType(ListTile), findsWidgets,
          reason: 'The decoy panel is built out of ListTiles');
      expect(tester.takeException(), isNull,
          reason: 'No tile may report the ListTile ink/background assertion');
    });

    // Named-route harness for the origin tests: mirrors the real stack the
    // duress flow builds — game home ('/'), the voting screen, a vault
    // route and the admin panel, all pushed by name.
    Widget buildOriginTestApp(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HorrorTheme.themeData,
          initialRoute: '/',
          routes: {
            '/': (_) => const Scaffold(body: Text('GAME_HOME')),
            '/voting': (_) => const Scaffold(body: Text('VOTING_SCREEN')),
            '/results': (_) => const Scaffold(body: Text('RESULTS_SCREEN')),
            '/vault-home': (_) => const Scaffold(body: Text('VAULT_HOME')),
            '/vault-pin': (_) => const Scaffold(body: Text('VAULT_PIN_SCREEN')),
            '/admin-panel': (_) => const AdminPanelScreen(),
          },
        ),
      );
    }

    testWidgets(
        'quick-entry origin: RETURN TO GAME returns to the game home the shortcut was used on',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Exactly what the quick-entry long-press hook does before it pushes
      // the PIN route.
      SecretEntryTrail.setOrigin(MimicGame.homeRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'RETURN TO GAME must remove the decoy panel from the stack');
      expect(find.text('GAME_HOME'), findsOneWidget,
          reason: 'Shortcut entry must return to the game home it left');
    });

    testWidgets(
        'voting-gesture origin: RETURN TO GAME returns to the live voting round',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Exactly what the voting-screen TriggerDetector does before it pushes
      // the PIN route.
      SecretEntryTrail.setOrigin(MimicGame.votingRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/voting');
      await pumpScreen(tester);
      // The duress PIN replaces the PIN route, so the panel sits directly on
      // top of the still-live voting screen.
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'RETURN TO GAME must remove the decoy panel from the stack');
      expect(find.text('VOTING_SCREEN'), findsOneWidget,
          reason:
              'Gateway entry must resume the round it was opened from, '
              'not rebuild the game home');
    });

    testWidgets(
        'verdict-screen origin: RETURN TO GAME resumes the finished round instead of the game home',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Exactly what the results-screen detector does before it pushes the
      // PIN route. The voting screen replaced ITSELF with '/results' when the
      // round was revealed, so the verdict screen is the only game route
      // left below the panel — the mimic entered from there and must come
      // back to there.
      SecretEntryTrail.setOrigin(MimicGame.resultsRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/results');
      await pumpScreen(tester);
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'RETURN TO GAME must remove the decoy panel from the stack');
      expect(find.text('RESULTS_SCREEN'), findsOneWidget,
          reason: 'The verdict screen the entry was made from must resume — '
              'a 3-player survival game ends on that screen');
      expect(find.text('GAME_HOME'), findsNothing,
          reason: 'Regression: the results-screen entry used to record no '
              'origin, so the exit rebuilt the game home instead');
    });

    testWidgets(
        'vault PIN route as the stack ROOT: RETURN TO GAME exits to the game, never onto the vault prompt',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // AutoLock and Settings → Lock Vault push '/vault-pin' with
      // pushNamedAndRemoveUntil, which makes the vault PIN route the
      // navigator's FIRST route. A walk that stops on `route.isFirst` then
      // legally lands on the vault's own PIN prompt, so the exit has to
      // replace that root instead of leaving the mimic on it.
      SecretEntryTrail.clear();

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamedAndRemoveUntil('/vault-pin', (route) => false);
      await pumpScreen(tester);
      expect(find.text('VAULT_PIN_SCREEN'), findsOneWidget);

      // The duress PIN replaces the PIN route, so the panel sits directly on
      // top of the vault root.
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing);
      expect(find.text('VAULT_PIN_SCREEN'), findsNothing,
          reason: 'The exit must never leave the mimic on the vault PIN '
              'prompt — that is the leak the decoy exists to prevent');
      expect(find.text('GAME_HOME'), findsOneWidget,
          reason: 'A vault root is replaced by the game home on a cleared '
              'stack');
    });

    testWidgets(
        "the panel's bottom Exit tile takes the same exit as RETURN TO GAME",
        (WidgetTester tester) async {
      // The SYSTEM section sits at the very bottom of a long decoy list, so
      // the whole list has to lay out for the tile to exist on screen.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SecretEntryTrail.setOrigin(MimicGame.votingRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/voting');
      await pumpScreen(tester);
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('Exit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing,
          reason: 'The bottom Exit tile must also leave the decoy panel');
      expect(find.text('VOTING_SCREEN'), findsOneWidget,
          reason: 'Both exits must return the mimic to the screen the '
              'secret entry was made from');
      expect(find.text('GAME_HOME'), findsNothing,
          reason: 'Regression: Exit used to clear the stack to the game home '
              'and destroy the live round');
    });

    testWidgets(
        'a double tap on RETURN TO GAME cannot pop past the origin',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SecretEntryTrail.setOrigin(MimicGame.votingRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/voting');
      await pumpScreen(tester);
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      // Two taps inside one frame: the second lands while the first exit is
      // still animating out (a panicking bystander double-taps a leave
      // button). Without the one-shot latch the trail would already have been
      // consumed, so the second call could only pop the live round as well
      // and drop the mimic on the game home.
      await tester.tap(find.text('RETURN TO GAME'));
      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing);
      expect(find.text('VOTING_SCREEN'), findsOneWidget,
          reason: 'The second tap must not pop the live round as well');
      expect(find.text('GAME_HOME'), findsNothing,
          reason: 'A double tap must still land on the entry screen, not a '
              'rebuild of the game home');
    });

    test('the trail is single-use: every exit consumes the entry it belongs to', () {
      SecretEntryTrail.setOrigin(MimicGame.votingRoute);

      expect(SecretEntryTrail.consume(), MimicGame.votingRoute);
      expect(SecretEntryTrail.consume(), isNull,
          reason: 'A later exit must fall back to a game route rather than '
              'replay a destination from an entry that already ended');
    });

    testWidgets(
        'the real results-screen sequence records its origin and pushes the named vault PIN route',
        (WidgetTester tester) async {
      final (:container, :voteCounts) = await buildResultsState();

      await tester.pumpWidget(buildGameTestApp(
        home: ResultsScreen(voteCounts: voteCounts),
        container: container,
      ));
      await pumpScreen(tester);

      // The scoreboard's score number is the hidden hotspot (recordTap(0)),
      // and the results screen's own sequence is three of those taps. This
      // drives the real screen, so it is the regression guard for the report
      // "the gesture from the scores screen sends me to the game home".
      TriggerCallbackRegistry().recordTap(0);
      TriggerCallbackRegistry().recordTap(0);
      TriggerCallbackRegistry().recordTap(0);

      await tester.pump();
      // The hidden flash overlay holds 300 ms + 300 ms before the trigger
      // fires, and the results screen's own timeline (2 s accusation + 1.5 s
      // judgment) then has to be drained or flutter_test fails the case on a
      // pending timer. Fixed pumps only — this screen animates forever.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 200));

      expect(SecretEntryTrail.consume(), MimicGame.resultsRoute,
          reason: 'The entry must anchor the exit to the verdict screen it '
              'was made from');
      expect(find.text('VAULT_PIN_SCREEN'), findsOneWidget,
          reason: 'The results-screen sequence must still open the vault PIN '
              'route (a real named route, so RouteGuard and SecureGuard apply)');
    });

    testWidgets(
        'stale origin: RETURN TO GAME never lands on a vault route — it falls back to the game home',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // An origin left over from an earlier round that no longer exists on
      // the stack: the mimic entered duress from a vault lock screen.
      SecretEntryTrail.setOrigin(MimicGame.votingRoute);

      final container = ProviderContainer();
      await tester.pumpWidget(buildOriginTestApp(container));
      await pumpScreen(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/vault-home');
      await pumpScreen(tester);
      navigator.pushNamed('/admin-panel');
      await pumpScreen(tester);

      await tester.tap(find.text('RETURN TO GAME'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdminPanelScreen), findsNothing);
      expect(find.text('VAULT_HOME'), findsNothing,
          reason: 'The exit must close the vault, never land in it');
      expect(find.text('GAME_HOME'), findsOneWidget,
          reason: 'A stale origin falls back to the root game screen');
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
