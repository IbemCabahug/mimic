// test/multiplayer/multiplayer_test.dart
//
// Complete tests for multiplayer logic:
// 1. GameStateSyncNotifier unit tests
// 2. DisconnectHandler unit tests
// 3. NetworkWordRevealScreen widget tests
// 4. NetworkVotingScreen widget tests

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/network/disconnect_handler.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';
import 'package:mimic/multiplayer/screens/network_word_reveal_screen.dart';
import 'package:mimic/multiplayer/screens/network_voting_screen.dart';
import 'package:mimic/multiplayer/screens/rejoin_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Fakes & Mocks
// ═══════════════════════════════════════════════════════════════════════════

class FakeNetworkService extends NetworkService {
  NetworkRole _role = NetworkRole.none;
  String? _hostIp;
  String? _assignedPlayerId;
  final List<String> _connectedPlayerIds = [];
  bool _isConnected = false;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentMessages = [];
  final List<Map<String, dynamic>> sentToMessages = [];

  @override
  NetworkRole get role => _role;
  set role(NetworkRole val) {
    _role = val;
    notifyListeners();
  }

  @override
  String? get hostIp => _hostIp;
  set hostIp(String? val) => _hostIp = val;

  @override
  int get port => 4567;

  @override
  bool get isConnected => _isConnected;
  set isConnected(bool val) {
    _isConnected = val;
    notifyListeners();
  }

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  List<String> get connectedPlayerIds => _connectedPlayerIds;

  @override
  String? get assignedPlayerId => _assignedPlayerId;
  set assignedPlayerId(String? val) => _assignedPlayerId = val;

  void simulateMessageReceived(Map<String, dynamic> msg) {
    _messageController.add(msg);
  }

  @override
  Future<void> startAsHost() async {
    _role = NetworkRole.host;
    _isConnected = true;
    _hostIp = '192.168.1.100';
    notifyListeners();
  }

  bool shouldJoinSucceed = true;

  @override
  Future<void> joinAsGuest(String ip, int port) async {
    _role = NetworkRole.guest;
    _isConnected = shouldJoinSucceed;
    if (shouldJoinSucceed) {
      _assignedPlayerId = 'guest_player_1';
    }
    notifyListeners();
  }

  bool reconnectCalled = false;
  @override
  Future<void> reconnect() async {
    reconnectCalled = true;
    _isConnected = true;
    notifyListeners();
  }

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  @override
  void sendTo(String playerId, Map<String, dynamic> message) {
    sentToMessages.add({'playerId': playerId, 'message': message});
  }

  @override
  void disconnect() {
    _role = NetworkRole.none;
    _isConnected = false;
    _hostIp = null;
    _assignedPlayerId = null;
    _connectedPlayerIds.clear();
    notifyListeners();
  }
}

// Helper to pump screens with GoogleFonts loaded and proper MaterialApp routes
Widget buildTestApp({
  required Widget home,
  required ProviderContainer container,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: HorrorTheme.themeData,
      home: home,
      routes: {
        '/discussion': (_) => const Scaffold(body: Text('DISCUSSION_SCREEN')),
        '/multiplayer': (_) => const Scaffold(body: Text('MULTIPLAYER_SCREEN')),
      },
    ),
  );
}

Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

// ═══════════════════════════════════════════════════════════════════════════
// Main Test Entry
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  group('Multiplayer Game Tests', () {
    late FakeNetworkService fakeNetworkService;
    late ProviderContainer container;
    late ProviderSubscription gameStateSyncSub;
    late ProviderSubscription networkServiceSub;

    setUp(() {
      fakeNetworkService = FakeNetworkService();
      container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => fakeNetworkService),
        ],
      );
      // Keep providers alive during tests to prevent FakeNetworkService from being disposed
      gameStateSyncSub = container.listen(gameStateSyncProvider, (_, __) {});
      networkServiceSub = container.listen(networkServiceProvider, (_, __) {});
    });

    tearDown(() {
      gameStateSyncSub.close();
      networkServiceSub.close();
      container.dispose();
    });


    // ─────────────────────────────────────────────────────────────────────────
    // 1 · GameStateSyncNotifier Tests
    // ─────────────────────────────────────────────────────────────────────────
    group('1 · GameStateSyncNotifier', () {
      test('Initializes state correctly', () {
        final notifier = container.read(gameStateSyncProvider.notifier);
        final state = container.read(gameStateSyncProvider);

        expect(state.isReady, isFalse);
        expect(state.error, isNull);
        expect(state.players, isEmpty);
      });

      test('Host starts game and assigns roles correctly', () async {
        fakeNetworkService.role = NetworkRole.host;
        fakeNetworkService.connectedPlayerIds.addAll(['guest_1', 'guest_2']);

        final notifier = container.read(gameStateSyncProvider.notifier);

        // Send startGame message to host sync notifier
        fakeNetworkService.simulateMessageReceived({'type': 'startGame'});
        await Future<void>.delayed(Duration.zero);

        final syncState = container.read(gameStateSyncProvider);
        expect(syncState.isReady, isTrue);
        expect(syncState.players.length, 3); // host + 2 guests
        expect(syncState.players.containsKey('host'), isTrue);
        expect(syncState.players.containsKey('guest_1'), isTrue);
        expect(syncState.players.containsKey('guest_2'), isTrue);

        // Verify that roleAssigned messages were sent to the guests
        expect(fakeNetworkService.sentToMessages.length, 2);
        expect(fakeNetworkService.sentToMessages[0]['playerId'], 'guest_1');
        expect(fakeNetworkService.sentToMessages[0]['message']['type'], 'roleAssigned');
      });

      test('Handles wordAck from players correctly', () async {
        fakeNetworkService.role = NetworkRole.host;
        fakeNetworkService.connectedPlayerIds.addAll(['guest_1']);

        final notifier = container.read(gameStateSyncProvider.notifier);

        fakeNetworkService.simulateMessageReceived({'type': 'startGame'});
        await Future<void>.delayed(Duration.zero);

        // guest_1 acknowledges
        fakeNetworkService.simulateMessageReceived({
          'type': 'wordAck',
          'senderId': 'guest_1',
        });
        await Future<void>.delayed(Duration.zero);

        final syncState = container.read(gameStateSyncProvider);
        expect(syncState.players['guest_1']?.hasReceivedWord, isTrue);
      });

      test('Handles playerJoined correctly (updates list)', () async {
        fakeNetworkService.role = NetworkRole.host;
        final notifier = container.read(gameStateSyncProvider.notifier);

        fakeNetworkService.simulateMessageReceived({
          'type': 'playerJoined',
          'senderId': 'guest_new',
          'name': 'ScaryPlayer',
        });
        await Future<void>.delayed(Duration.zero);

        final syncState = container.read(gameStateSyncProvider);
        expect(syncState.players['guest_new']?.displayName, 'ScaryPlayer');
      });

      test('Handles playerLeft correctly (removes or eliminates player)', () async {
        fakeNetworkService.role = NetworkRole.host;
        fakeNetworkService.connectedPlayerIds.add('guest_1');

        final notifier = container.read(gameStateSyncProvider.notifier);

        fakeNetworkService.simulateMessageReceived({'type': 'startGame'});
        await Future<void>.delayed(Duration.zero);

        // Player leaves before game starts (currentRound == 0)
        fakeNetworkService.simulateMessageReceived({
          'type': 'playerLeft',
          'playerId': 'guest_1',
        });
        await Future<void>.delayed(Duration.zero);

        final syncState = container.read(gameStateSyncProvider);
        expect(syncState.players.containsKey('guest_1'), isFalse);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2 · DisconnectHandler Tests
    // ─────────────────────────────────────────────────────────────────────────
    group('2 · DisconnectHandler', () {
      test('Monitors network messages and handles ping/pong', () async {
        fakeNetworkService.role = NetworkRole.guest;
        final syncNotifier = container.read(gameStateSyncProvider.notifier);
        final handler = DisconnectHandler(fakeNetworkService, syncNotifier);

        handler.startMonitoring();

        // Simulate ping from Host
        fakeNetworkService.simulateMessageReceived({'type': 'ping'});
        await Future<void>.delayed(Duration.zero);

        // Guest should reply with pong
        expect(fakeNetworkService.sentMessages.length, 1);
        expect(fakeNetworkService.sentMessages[0]['type'], 'pong');

        handler.stopMonitoring();
      });

      testWidgets('Timeout triggers guest reconnection or escalation', (WidgetTester tester) async {
        fakeNetworkService.role = NetworkRole.guest;
        fakeNetworkService.isConnected = true;

        final syncNotifier = container.read(gameStateSyncProvider.notifier);
        final handler = DisconnectHandler(fakeNetworkService, syncNotifier);

        // Start monitoring (uses 5s ping and 3s pong timeout)
        handler.startMonitoring();

        // Trigger guest timeout manually by simulating timeout event
        fakeNetworkService.simulateMessageReceived({'type': 'disconnected'});
        await tester.pump();

        // Reconnect should be attempted
        expect(fakeNetworkService.reconnectCalled, isTrue);

        handler.stopMonitoring();
        await tester.pumpAndSettle(); // Flush any pending Riverpod invalidation timers
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3 · NetworkWordRevealScreen Widget Tests
    // ─────────────────────────────────────────────────────────────────────────
    group('3 · NetworkWordRevealScreen', () {
      testWidgets('Shows Waiting screen when role is null', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp(
          home: const NetworkWordRevealScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        expect(find.text('Waiting for your role…'), findsOneWidget);
        expect(find.text('YOUR ROLE IS READY'), findsNothing);
      });

      testWidgets('Shows Ready to Reveal screen when role is assigned', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp(
          home: const NetworkWordRevealScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        // Simulate receiving role
        fakeNetworkService.simulateMessageReceived({
          'type': 'roleAssigned',
          'role': 'villager',
          'word': 'vampire',
        });
        await pumpScreen(tester);

        expect(find.text('Waiting for your role…'), findsNothing);
        expect(find.text('YOUR ROLE IS READY'), findsOneWidget);
        expect(find.text('Cover your screen from other players.'), findsOneWidget);
        expect(find.text('TAP ANYWHERE TO REVEAL'), findsOneWidget);
      });

      testWidgets('Shows role and word on tap and allows navigation on "I\'M READY"', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp(
          home: const NetworkWordRevealScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        fakeNetworkService.simulateMessageReceived({
          'type': 'roleAssigned',
          'role': 'villager',
          'word': 'vampire',
        });
        await pumpScreen(tester);

        // Tap to reveal
        await tester.tap(find.text('TAP ANYWHERE TO REVEAL'));
        await pumpScreen(tester);

        expect(find.text('YOUR WORD IS'), findsOneWidget);
        expect(find.text('VAMPIRE'), findsOneWidget);
        expect(find.text('Remember your word.'), findsOneWidget);

        final readyButton = find.text("I'M READY");
        expect(readyButton, findsOneWidget);

        // Tap ready
        await tester.tap(readyButton);
        await pumpScreen(tester);

        // Sent wordAck to host
        expect(fakeNetworkService.sentMessages.length, 1);
        expect(fakeNetworkService.sentMessages[0]['type'], 'wordAck');

        // Navigates to discussion route (mocked route text is rendered)
        expect(find.text('DISCUSSION_SCREEN'), findsOneWidget);
      });

      testWidgets('Shows Mimic instructions for the Impostor role', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp(
          home: const NetworkWordRevealScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        fakeNetworkService.simulateMessageReceived({
          'type': 'roleAssigned',
          'role': 'mimic',
          'word': null,
        });
        await pumpScreen(tester);

        // Tap to reveal
        await tester.tap(find.text('TAP ANYWHERE TO REVEAL'));
        await pumpScreen(tester);

        expect(find.text('YOU ARE\nTHE MIMIC'), findsOneWidget);
        expect(find.text('Blend in. Trust no one.'), findsOneWidget);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4 · NetworkVotingScreen Widget Tests
    // ─────────────────────────────────────────────────────────────────────────
    group('4 · NetworkVotingScreen', () {
      testWidgets('Renders voting list and casts vote', (WidgetTester tester) async {
        // Prepare GameState with players
        final gameStateNotifier = container.read(gameStateProvider.notifier);
        gameStateNotifier.state = GameState(
          selectedMode: GameMode.classic,
          players: [
            Player(id: 'host', name: 'Host Player', color: 0xFF8B0000),
            Player(id: 'guest_1', name: 'Ghost Guest', color: 0xFFC41E3A),
          ],
          mimicIds: ['guest_1'],
          currentRound: 1,
          maxRounds: 3,
          suspicionScores: {},
          eliminatedPlayers: [],
          ghostPlayers: [],
          selectedPacks: [],
          scores: {},
          currentCategory: 'Scary',
        );

        // Prepare GameStateSyncNotifier with matching players
        final syncNotifier = container.read(gameStateSyncProvider.notifier);
        syncNotifier.state = GameSyncState(
          isReady: true,
          players: {
            'host': const PlayerNetworkState(playerId: 'host', displayName: 'Host Player'),
            'guest_1': const PlayerNetworkState(playerId: 'guest_1', displayName: 'Ghost Guest'),
          },
        );

        fakeNetworkService.role = NetworkRole.guest;
        fakeNetworkService.assignedPlayerId = 'guest_1';

        await tester.pumpWidget(buildTestApp(
          home: const NetworkVotingScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        // Verify players are displayed (Ghost Guest is current player and filtered out of choices)
        expect(find.text('HOST PLAYER'), findsOneWidget);
        expect(find.text('GHOST GUEST'), findsNothing);

        // Tap on a player card to vote
        await tester.tap(find.text('HOST PLAYER'));
        await pumpScreen(tester);

        // Should have sent the vote via NetworkService
        expect(fakeNetworkService.sentMessages.length, 1);
        expect(fakeNetworkService.sentMessages[0]['type'], 'castVote');
        expect(fakeNetworkService.sentMessages[0]['targetId'], 'host');
      });

      testWidgets('Handles voteResults broadcast and displays eliminated player', (WidgetTester tester) async {
        // Prepare state
        final gameStateNotifier = container.read(gameStateProvider.notifier);
        gameStateNotifier.state = GameState(
          selectedMode: GameMode.classic,
          players: [
            Player(id: 'host', name: 'Host Player', color: 0xFF8B0000),
            Player(id: 'guest_1', name: 'Ghost Guest', color: 0xFFC41E3A),
          ],
          mimicIds: ['guest_1'],
          currentRound: 1,
          maxRounds: 3,
          suspicionScores: {},
          eliminatedPlayers: [],
          ghostPlayers: [],
          selectedPacks: [],
          scores: {},
          currentCategory: 'Scary',
        );

        final syncNotifier = container.read(gameStateSyncProvider.notifier);
        syncNotifier.state = GameSyncState(
          isReady: true,
          players: {
            'host': const PlayerNetworkState(playerId: 'host', displayName: 'Host Player'),
            'guest_1': const PlayerNetworkState(playerId: 'guest_1', displayName: 'Ghost Guest'),
          },
        );

        fakeNetworkService.role = NetworkRole.guest;
        fakeNetworkService.assignedPlayerId = 'guest_1';

        await tester.pumpWidget(buildTestApp(
          home: const NetworkVotingScreen(),
          container: container,
        ));
        await pumpScreen(tester);

        // Receive voteResults from host
        fakeNetworkService.simulateMessageReceived({
          'type': 'voteResults',
          'counts': {'host': 0, 'guest_1': 1},
          'eliminated': 'guest_1',
          'isMimic': true,
          'role': 'mimic',
          'displayName': 'Ghost Guest',
        });
        await pumpScreen(tester);

        // Results screen animation triggers. Let's pump longer duration to complete scale/fade transitions.
        await tester.pump(const Duration(seconds: 4));

        expect(find.text('JUDGMENT'), findsOneWidget);
        expect(find.text('GHOST GUEST'), findsAtLeastNWidgets(1));
        expect(find.text('has been eliminated!'), findsOneWidget);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5 · RejoinScreen Tests
    // ─────────────────────────────────────────────────────────────────────────
    group('5 · RejoinScreen', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      testWidgets('Shows Reconnecting state and auto-reconnects', (WidgetTester tester) async {
        fakeNetworkService.role = NetworkRole.guest;

        await tester.pumpWidget(buildTestApp(
          home: const RejoinScreen(
            lastRoomCode: 'AAAAAA',
            lastPlayerName: 'Ghosty',
            lastPlayerId: 'old_guest_id',
          ),
          container: container,
        ));
        await tester.pump(); // Run post-frame callbacks to trigger _attemptReconnect

        // Attempting connection shows Reconnecting...
        expect(find.text('RECONNECTING…'), findsOneWidget);
        expect(find.text('Attempt 1 of 3'), findsOneWidget);

        // Simulate host rejoinAccepted response
        fakeNetworkService.simulateMessageReceived({
          'type': 'rejoinAccepted',
          'role': 'villager',
          'word': 'ghost',
          'playerId': 'new_guest_id',
          'phase': 'discussion',
          'gameState': {
            'selectedMode': 'classic',
            'players': [
              {'id': 'host', 'name': 'Host Player', 'color': 0xFF8B0000},
              {'id': 'new_guest_id', 'name': 'Ghosty', 'color': 0xFFC41E3A},
            ],
            'mimicIds': <String>[],
            'currentRound': 1,
          },
        });

        // Let the frame advance
        await tester.pump(const Duration(seconds: 1));

        // It should show reconnected
        expect(find.text('RECONNECTED'), findsOneWidget);

        // Wait 1 second for navigation
        await tester.pump(const Duration(seconds: 2));

        // Navigates to discussion screen
        expect(find.text('DISCUSSION_SCREEN'), findsOneWidget);
      });

      testWidgets('Failed reconnect after 3 attempts shows connection lost', (WidgetTester tester) async {
        fakeNetworkService.shouldJoinSucceed = false;

        await tester.pumpWidget(buildTestApp(
          home: const RejoinScreen(
            lastRoomCode: 'AAAAAA',
            lastPlayerName: 'Ghosty',
            lastPlayerId: 'old_guest_id',
          ),
          container: container,
        ));
        await tester.pump();

        // Pump multiple times to allow retry timers to fire
        await tester.pump(const Duration(milliseconds: 1600)); // retry 1
        await tester.pump(const Duration(milliseconds: 1600)); // retry 2
        await tester.pump(const Duration(milliseconds: 1600)); // retry 3
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('CONNECTION LOST'), findsOneWidget);
        expect(find.text('TRY AGAIN'), findsOneWidget);
        expect(find.text('LEAVE GAME'), findsOneWidget);
      });

      testWidgets('Host leaving shows host gone screen', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestApp(
          home: const RejoinScreen(
            lastRoomCode: 'AAAAAA',
            lastPlayerName: 'Ghosty',
            lastPlayerId: 'old_guest_id',
          ),
          container: container,
        ));
        await tester.pump();

        // Simulate host disconnect
        fakeNetworkService.simulateMessageReceived({'type': 'disconnected'});
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('THE HOST HAS LEFT'), findsOneWidget);
        expect(find.text('This room no longer exists.'), findsOneWidget);
        expect(find.text('RETURN TO MENU'), findsOneWidget);
      });
    });
  });
}
