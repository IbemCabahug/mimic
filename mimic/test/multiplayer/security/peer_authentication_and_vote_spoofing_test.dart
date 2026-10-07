import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/network/mimic_client.dart';
import 'package:mimic/multiplayer/network/mimic_server.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';

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
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  @override
  void sendTo(String playerId, Map<String, dynamic> message) {
    sentToMessages.add({'playerId': playerId, 'message': message});
  }

  @override
  void disconnect() {
    _isConnected = false;
    _role = NetworkRole.none;
    _connectedPlayerIds.clear();
    notifyListeners();
  }
}

void main() {
  group('SEC-04: Peer Authentication & Vote Spoofing Prevention', () {
    group('1. MimicServer Handshake Authentication', () {
      late MimicServer server;

      setUp(() async {
        server = MimicServer();
        server.sessionToken = 'SECURE_ROOM_TOKEN';
        await server.start();
      });

      tearDown(() {
        server.stop();
      });

      test('Accepts client providing valid handshake token', () async {
        final client = MimicClient();
        addTearDown(client.disconnect);

        await client.connect(server.hostIp ?? '127.0.0.1', server.port,
            handshakeToken: 'SECURE_ROOM_TOKEN');

        // Wait for welcome message
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(client.isConnected, isTrue);
        expect(client.assignedPlayerId, isNotNull);
        expect(server.connectedPlayerIds.contains(client.assignedPlayerId), isTrue);
      });

      test('Rejects client providing invalid handshake token', () async {
        final socket = await WebSocket.connect('ws://${server.hostIp ?? "127.0.0.1"}:${server.port}');
        socket.add(jsonEncode({
          'type': 'handshake',
          'token': 'WRONG_TOKEN',
        }));

        final completer = Completer<int?>();
        socket.listen(
          (_) {},
          onDone: () => completer.complete(socket.closeCode),
          onError: (_) => completer.complete(socket.closeCode),
        );

        final closeCode = await completer.future.timeout(const Duration(seconds: 2));
        expect(closeCode, equals(WebSocketStatus.policyViolation));
        expect(server.connectedPlayerIds, isEmpty);
      });

      test('Rejects client sending premature action message without handshake', () async {
        final socket = await WebSocket.connect('ws://${server.hostIp ?? "127.0.0.1"}:${server.port}');
        socket.add(jsonEncode({
          'type': 'castVote',
          'voterId': 'innocent_player',
          'targetId': 'target_player',
        }));

        final completer = Completer<int?>();
        socket.listen(
          (_) {},
          onDone: () => completer.complete(socket.closeCode),
          onError: (_) => completer.complete(socket.closeCode),
        );

        final closeCode = await completer.future.timeout(const Duration(seconds: 2));
        expect(closeCode, equals(WebSocketStatus.policyViolation));
        expect(server.connectedPlayerIds, isEmpty);
      });
    });

    group('2. Vote Spoofing Prevention in Network Layer', () {
      late MimicServer server;

      setUp(() async {
        server = MimicServer();
        await server.start();
      });

      tearDown(() {
        server.stop();
      });

      test('MimicServer strictly overwrites client voterId with verified socket senderId', () async {
        final client = MimicClient();
        addTearDown(client.disconnect);

        await client.connect(server.hostIp ?? '127.0.0.1', server.port);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final verifiedPlayerId = client.assignedPlayerId;
        expect(verifiedPlayerId, isNotNull);

        final completer = Completer<Map<String, dynamic>>();
        server.messageStream.listen((msg) {
          if (msg['type'] == 'castVote') {
            completer.complete(msg);
          }
        });

        // Client attempts to spoof vote on behalf of 'victim_player'
        client.send({
          'type': 'castVote',
          'voterId': 'victim_player',
          'targetId': 'someone_else',
        });

        final received = await completer.future.timeout(const Duration(seconds: 2));
        // Critical: voterId and senderId must both be verifiedPlayerId, NOT 'victim_player'
        expect(received['senderId'], equals(verifiedPlayerId));
        expect(received['voterId'], equals(verifiedPlayerId));
      });
    });

    group('3. Vote Spoofing Prevention in GameStateSyncNotifier', () {
      test('GameStateSyncNotifier binds castVote strictly to verified senderId over voterId', () async {
        final fakeNetworkService = FakeNetworkService();
        fakeNetworkService.role = NetworkRole.host;
        fakeNetworkService.connectedPlayerIds.addAll(['victim_player', 'attacker_player']);

        final container = ProviderContainer(
          overrides: [
            networkServiceProvider.overrideWith((ref) => fakeNetworkService),
          ],
        );
        final syncSub = container.listen(gameStateSyncProvider, (_, _) {});
        final netSub = container.listen(networkServiceProvider, (_, _) {});
        addTearDown(() {
          syncSub.close();
          netSub.close();
          container.dispose();
        });

        final gameStateNotifier = container.read(gameStateProvider.notifier);
        gameStateNotifier.initializeMultiplayerPlayers([
          Player(id: 'host', name: 'Host', color: 0xFF111111),
          Player(id: 'victim_player', name: 'Victim', color: 0xFF222222),
          Player(id: 'attacker_player', name: 'Attacker', color: 0xFF333333),
        ]);

        container.read(gameStateSyncProvider.notifier);

        // Register players in network state
        fakeNetworkService.simulateMessageReceived({
          'type': 'playerJoined',
          'senderId': 'victim_player',
          'name': 'Victim',
        });
        fakeNetworkService.simulateMessageReceived({
          'type': 'playerJoined',
          'senderId': 'attacker_player',
          'name': 'Attacker',
        });
        await Future<void>.delayed(Duration.zero);

        // Attacker sends vote spoof attempting to attribute their vote to victim_player
        fakeNetworkService.simulateMessageReceived({
          'type': 'castVote',
          'senderId': 'attacker_player', // Verified socket connection
          'voterId': 'victim_player',     // Spoofed payload claim
          'targetId': 'host',
        });
        await Future<void>.delayed(Duration.zero);

        final syncState = container.read(gameStateSyncProvider);

        // Attacker is marked as having voted, Victim has NOT voted
        expect(syncState.players['attacker_player']?.hasVoted, isTrue,
            reason: 'The socket sender must be the one marked as having voted');
        expect(syncState.players['victim_player']?.hasVoted, isFalse,
            reason: 'The spoofed victim must NOT have their vote consumed');
      });
    });
  });
}
