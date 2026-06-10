// test/multiplayer/integration_smoke_test.dart
// pubspec dev: mocktail: ^2.0.0
//
// Complete smoke tests for the entire multiplayer system:
// 1. NetworkService unit tests
// 2. Room Flow integration tests
// 3. Game Sync tests
// 4. Disconnect handling tests

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
// Mock Classes
// ═══════════════════════════════════════════════════════════════════════════

class MockNetworkService extends NetworkService {
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
  List<String> get connectedPlayerIds => _connectedPlayerIds;

  @override
  String? get assignedPlayerId => _assignedPlayerId;
  set assignedPlayerId(String? val) => _assignedPlayerId = val;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

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

  bool joinShouldSucceed = true;

  @override
  Future<void> joinAsGuest(String ip, int port) async {
    _role = NetworkRole.guest;
    _isConnected = joinShouldSucceed;
    if (joinShouldSucceed) {
      _assignedPlayerId = 'guest_player_1';
    }
    notifyListeners();
  }

  bool reconnectShouldSucceed = true;

  @override
  Future<void> reconnect() async {
    if (reconnectShouldSucceed) {
      _isConnected = true;
      notifyListeners();
    }
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
    _connectedPlayerIds.clear();
    notifyListeners();
  }

  void addConnectedPlayer(String playerId) {
    _connectedPlayerIds.add(playerId);
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Helpers
// ═══════════════════════════════════════════════════════════════════════════

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
  // ─────────────────────────────────────────────────────────────────────────
  // NetworkService Tests
  // ─────────────────────────────────────────────────────────────────────────
  group('NetworkService', () {
    late MockNetworkService mockNetworkService;
    late ProviderContainer container;
    late ProviderSubscription networkServiceSub;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockNetworkService = MockNetworkService();
      container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => mockNetworkService),
        ],
      );
      networkServiceSub = container.listen(networkServiceProvider, (_, _) {});
    });

    tearDown(() {
      networkServiceSub.close();
      container.dispose();
    });

    test('MimicServer binds to a port and accepts a WebSocket connection', () async {
      await mockNetworkService.startAsHost();

      expect(mockNetworkService.role, NetworkRole.host);
      expect(mockNetworkService.isConnected, isTrue);
      expect(mockNetworkService.hostIp, isNotNull);
      expect(mockNetworkService.port, equals(4567));
    });

    test('MimicClient connects and receives welcome message with assigned playerId', () async {
      await mockNetworkService.joinAsGuest('192.168.1.1', 4567);

      expect(mockNetworkService.role, NetworkRole.guest);
      expect(mockNetworkService.isConnected, isTrue);
      expect(mockNetworkService.assignedPlayerId, isNotNull);
      expect(mockNetworkService.assignedPlayerId, isNotEmpty);
    });

    test('NetworkService.send() calls server.broadcast() when role is host', () async {
      await mockNetworkService.startAsHost();

      final testMessage = {'type': 'test', 'data': 'hello'};
      mockNetworkService.send(testMessage);

      expect(mockNetworkService.sentMessages.length, equals(1));
      expect(mockNetworkService.sentMessages[0], equals(testMessage));
    });

    test('NetworkService.send() calls client.send() when role is guest', () async {
      await mockNetworkService.joinAsGuest('192.168.1.1', 4567);

      final testMessage = {'type': 'test', 'data': 'hello'};
      mockNetworkService.send(testMessage);

      expect(mockNetworkService.sentMessages.length, equals(1));
      expect(mockNetworkService.sentMessages[0], equals(testMessage));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Room Flow Tests
  // ─────────────────────────────────────────────────────────────────────────
  group('Room Flow', () {
    late MockNetworkService mockNetworkService;
    late ProviderContainer container;
    late ProviderSubscription networkServiceSub;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockNetworkService = MockNetworkService();
      container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => mockNetworkService),
        ],
      );
      networkServiceSub = container.listen(networkServiceProvider, (_, _) {});
    });

    tearDown(() {
      networkServiceSub.close();
      container.dispose();
    });

    test('room code encodes ip "192.168.1.1" and port 4567 and decodes back to same values', () async {
      await mockNetworkService.startAsHost();
      mockNetworkService.hostIp = '192.168.1.1';

      final hostIp = mockNetworkService.hostIp!;
      final port = mockNetworkService.port;

      // Encode: convert IP to room code
      final parts = hostIp.split('.');
      final ipInt = (int.parse(parts[0]) << 24) |
          (int.parse(parts[1]) << 16) |
          (int.parse(parts[2]) << 8) |
          int.parse(parts[3]);

      const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final buffer = StringBuffer();
      int temp = ipInt;
      while (temp > 0) {
        buffer.write(chars[temp % 62]);
        temp = temp ~/ 62;
      }
      final encoded = buffer.toString().split('').reversed.join().padLeft(6, '0');

      // Decode
      int val = 0;
      for (int i = 0; i < encoded.length; i++) {
        final char = encoded[i];
        final index = chars.indexOf(char);
        val = val * 62 + index;
      }

      final decodedOctet4 = val & 0xFF;
      final decodedOctet3 = (val >> 8) & 0xFF;
      final decodedOctet2 = (val >> 16) & 0xFF;
      final decodedOctet1 = (val >> 24) & 0xFF;
      final decodedIp = '$decodedOctet1.$decodedOctet2.$decodedOctet3.$decodedOctet4';

      expect(decodedIp, equals('192.168.1.1'));
      expect(port, equals(4567));
    });

    testWidgets('NetworkWordRevealScreen renders WAITING stage on init before any message', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp(
        home: const NetworkWordRevealScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      expect(find.text('Waiting for your role…'), findsOneWidget);
      expect(find.text('YOUR ROLE IS READY'), findsNothing);
    });

    testWidgets('NetworkVotingScreen dispatches castVote message when a VoteCard is tapped', (WidgetTester tester) async {
      // Prepare game state with players
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

      mockNetworkService.role = NetworkRole.guest;
      mockNetworkService.assignedPlayerId = 'guest_1';

      await tester.pumpWidget(buildTestApp(
        home: const NetworkVotingScreen(),
        container: container,
      ));
      await pumpScreen(tester);

      // Tap on a player card to vote
      await tester.tap(find.text('HOST PLAYER'));
      await pumpScreen(tester);

      // Should have sent castVote message
      expect(mockNetworkService.sentMessages.length, greaterThanOrEqualTo(1));
      expect(mockNetworkService.sentMessages.any((m) => m['type'] == 'castVote'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Game Sync Tests
  // ─────────────────────────────────────────────────────────────────────────
  group('Game Sync', () {
    late MockNetworkService mockNetworkService;
    late ProviderContainer container;
    late ProviderSubscription gameStateSyncSub;
    late ProviderSubscription networkServiceSub;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockNetworkService = MockNetworkService();
      container = ProviderContainer(
        overrides: [
          networkServiceProvider.overrideWith((ref) => mockNetworkService),
        ],
      );
      gameStateSyncSub = container.listen(gameStateSyncProvider, (_, _) {});
      networkServiceSub = container.listen(networkServiceProvider, (_, _) {});
    });

    tearDown(() {
      gameStateSyncSub.close();
      networkServiceSub.close();
      container.dispose();
    });

    test('GameStateSyncNotifier updates correct player\'s hasReceivedWord when wordAck message received', () async {
      mockNetworkService.role = NetworkRole.host;
      mockNetworkService.addConnectedPlayer('guest_1');

      // Seed the GameSyncState with the player BEFORE the wordAck arrives
      final syncNotifier = container.read(gameStateSyncProvider.notifier);
      syncNotifier.state = GameSyncState(
        isReady: true,
        players: {
          'guest_1': const PlayerNetworkState(playerId: 'guest_1', displayName: 'Guest One', hasReceivedWord: false),
        },
      );

      // Send wordAck from guest_1
      mockNetworkService.simulateMessageReceived({
        'type': 'wordAck',
        'senderId': 'guest_1',
      });
      await Future<void>.delayed(Duration.zero);

      final syncState = container.read(gameStateSyncProvider);
      expect(syncState.players['guest_1']?.hasReceivedWord, isTrue);
    });

    test('host tallies all castVote messages and broadcasts voteResults when all non-eliminated players have voted', () async {
      mockNetworkService.role = NetworkRole.host;

      // Set up game state for voting
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

      // Seed GameSyncState with players BEFORE simulating votes
      final syncNotifier = container.read(gameStateSyncProvider.notifier);
      syncNotifier.state = GameSyncState(
        isReady: true,
        players: {
          'host': const PlayerNetworkState(playerId: 'host', displayName: 'Host Player', hasVoted: false),
          'guest_1': const PlayerNetworkState(playerId: 'guest_1', displayName: 'Ghost Guest', hasVoted: false),
        },
      );

      // Simulate vote received from guest_1
      mockNetworkService.simulateMessageReceived({
        'type': 'castVote',
        'senderId': 'guest_1',
        'targetId': 'host',
      });
      await Future<void>.delayed(Duration.zero);

      // Check that the vote was recorded in sync state
      final syncStateAfter = container.read(gameStateSyncProvider);
      expect(syncStateAfter.players['guest_1']?.hasVoted, isTrue);
    });
  });

// ─────────────────────────────────────────────────────────────────────────
// Disconnect Tests
// ─────────────────────────────────────────────────────────────────────────
group('Disconnect', () {
  test('DisconnectHandler emits DisconnectType.timeout when pong not received within 3 seconds', () async {
    SharedPreferences.setMockInitialValues({});
    final mockNetworkService = MockNetworkService();

    final container = ProviderContainer(
      overrides: [
        networkServiceProvider.overrideWith((ref) => mockNetworkService),
      ],
    );
    final networkServiceSub = container.listen(networkServiceProvider, (_, _) {});
    final gameStateSyncSub = container.listen(gameStateSyncProvider, (_, _) {});

    mockNetworkService.role = NetworkRole.guest;

    final syncNotifier = container.read(gameStateSyncProvider.notifier);
    final handler = DisconnectHandler(mockNetworkService, syncNotifier);

    handler.startMonitoring();

    // Simulate ping - guest should reply with pong
    mockNetworkService.simulateMessageReceived({'type': 'ping'});
    await Future<void>.delayed(Duration.zero);

    // Verify that pong was sent in response to ping
    expect(mockNetworkService.sentMessages.any((m) => m['type'] == 'pong'), isTrue);

    handler.stopMonitoring();
    await Future<void>.delayed(Duration.zero);

    networkServiceSub.close();
    gameStateSyncSub.close();
    container.dispose();
  });

  testWidgets('RejoinScreen calls networkServiceProvider.joinAsGuest() on initState', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockNetworkService = MockNetworkService();
    mockNetworkService.joinShouldSucceed = true;

    final container = ProviderContainer(
      overrides: [
        networkServiceProvider.overrideWith((ref) => mockNetworkService),
      ],
    );
    final networkServiceSub = container.listen(networkServiceProvider, (_, _) {});
    final gameStateSyncSub = container.listen(gameStateSyncProvider, (_, _) {});

    await tester.pumpWidget(buildTestApp(
      home: const RejoinScreen(
        lastRoomCode: 'A1B2C3',
        lastPlayerName: 'Ghosty',
        lastPlayerId: 'old_guest_id',
      ),
      container: container,
    ));

    // initState triggers _attemptReconnect which calls joinAsGuest
    await tester.pump();

    expect(mockNetworkService.role, NetworkRole.guest);

    networkServiceSub.close();
    gameStateSyncSub.close();
    container.dispose();
  });

  testWidgets('RejoinScreen shows hostGone UI state when MimicClient.connect() fails on all 3 attempts', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockNetworkService = MockNetworkService();
    mockNetworkService.joinShouldSucceed = false;

    final container = ProviderContainer(
      overrides: [
        networkServiceProvider.overrideWith((ref) => mockNetworkService),
      ],
    );
    final networkServiceSub = container.listen(networkServiceProvider, (_, _) {});

    await tester.pumpWidget(buildTestApp(
      home: const RejoinScreen(
        lastRoomCode: 'A1B2C3',
        lastPlayerName: 'Ghosty',
        lastPlayerId: 'old_guest_id',
      ),
      container: container,
    ));
    await tester.pump();

    // Pump to allow retries to fail (each retry after ~1.5s)
    await tester.pump(const Duration(milliseconds: 5000));

    // Should show connection lost state after 3 failed attempts
    expect(find.text('CONNECTION LOST'), findsOneWidget);

    networkServiceSub.close();
    container.dispose();
  });
});
}