// test/multiplayer/security/phase_a_security_remediations_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/game/data/word_packs.dart';
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
  Future<void> startAsHost() async {
    _role = NetworkRole.host;
    _hostIp = '127.0.0.1';
    _isConnected = true;
    notifyListeners();
  }

  @override
  Future<void> joinAsGuest(String ip, int port) async {
    _role = NetworkRole.guest;
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
    _isConnected = false;
    _role = NetworkRole.none;
    _connectedPlayerIds.clear();
    notifyListeners();
  }
}

void main() {
  group('Phase A Security Remediations Test Suite', () {
    // ─────────────────────────────────────────────────────────────────────
    // AUDIT-01: Handshake Token Variable Shadowing Fix
    // ─────────────────────────────────────────────────────────────────────
    group('AUDIT-01: NetworkService Handshake Token Transmission', () {
      late NetworkService hostService;
      late NetworkService guestService;

      setUp(() async {
        hostService = NetworkService();
        guestService = NetworkService();
      });

      tearDown(() {
        hostService.disconnect();
        guestService.disconnect();
      });

      test('Guest connects and authenticates successfully using handshakeToken property', () async {
        const secretRoomCode = 'Room7X-99';
        hostService.sessionToken = secretRoomCode;
        await hostService.startAsHost();

        expect(hostService.isConnected, isTrue);
        final hostIp = hostService.hostIp ?? '127.0.0.1';
        final port = hostService.port;

        // Set handshakeToken on guest (previously ignored due to _handshakeToken variable shadowing)
        guestService.handshakeToken = secretRoomCode;
        await guestService.joinAsGuest(hostIp, port);

        // Allow WebSocket handshake and welcome packet delivery
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(guestService.isConnected, isTrue);
        expect(guestService.role, equals(NetworkRole.guest));
        expect(guestService.assignedPlayerId, isNotNull);
        expect(hostService.connectedPlayerIds.contains(guestService.assignedPlayerId), isTrue);
      });

      test('Guest handshakeToken resets cleanly when disconnect is called', () async {
        guestService.handshakeToken = 'MY_EPHEMERAL_TOKEN';
        expect(guestService.handshakeToken, equals('MY_EPHEMERAL_TOKEN'));
        guestService.disconnect();
        expect(guestService.handshakeToken, isNull);
      });

      test('Guest with mismatched handshakeToken is rejected', () async {
        hostService.sessionToken = 'CORRECT_TOKEN';
        await hostService.startAsHost();

        final hostIp = hostService.hostIp ?? '127.0.0.1';
        final port = hostService.port;

        guestService.handshakeToken = 'WRONG_TOKEN';
        await guestService.joinAsGuest(hostIp, port);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(guestService.isConnected, isFalse);
        expect(guestService.role, equals(NetworkRole.none));
        expect(hostService.connectedPlayerIds, isEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // AUDIT-02: Cryptographic Rejoin Token Authentication
    // ─────────────────────────────────────────────────────────────────────
    group('AUDIT-02: Cryptographic Rejoin Token Authentication', () {
      test('MimicServer issues unguessable rejoinToken in welcome payload upon connection', () async {
        final server = MimicServer();
        await server.start();
        addTearDown(server.stop);

        final client = MimicClient();
        addTearDown(client.disconnect);

        await client.connect(server.hostIp ?? '127.0.0.1', server.port);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(client.isConnected, isTrue);
        expect(client.assignedPlayerId, isNotNull);
        expect(client.rejoinToken, isNotNull);
        expect(client.rejoinToken!.length, greaterThanOrEqualTo(16));

        // Server internal registry must verify the token
        final isValid = server.verifyRejoinToken(client.assignedPlayerId!, client.rejoinToken);
        expect(isValid, isTrue);

        // Verification fails for incorrect token or missing token
        expect(server.verifyRejoinToken(client.assignedPlayerId!, 'forged_token'), isFalse);
        expect(server.verifyRejoinToken(client.assignedPlayerId!, null), isFalse);
      });

      test('GameStateSyncNotifier rejects rogue rejoin request missing valid rejoinToken', () async {
        final fakeNetService = FakeNetworkService();
        fakeNetService.role = NetworkRole.host;

        final container = ProviderContainer(
          overrides: [
            networkServiceProvider.overrideWith((ref) => fakeNetService),
          ],
        );
        addTearDown(container.dispose);

        final gameStateNotifier = container.read(gameStateProvider.notifier);
        gameStateNotifier.initializeMultiplayerPlayers([
          Player(id: 'host', name: 'Host', color: 0xFF111111),
          Player(id: 'alice_id', name: 'Alice', color: 0xFF222222),
          Player(id: 'bob_mimic', name: 'Bob', color: 0xFF333333),
        ]);
        gameStateNotifier.state = gameStateNotifier.state.copyWith(
          currentRound: 1,
          mimicIds: ['bob_mimic'],
          currentWordPair: const WordPair(
            realWord: 'Astronaut',
            mimicWord: 'Alien',
            realWordContext: 'Space traveler',
            mimicWordContext: 'Extraterrestrial',
          ),
        );

        // Register valid token for Bob the mimic
        fakeNetService.registerRejoinToken('bob_mimic', 'bob_secret_rejoin_token');

        // Instantiate sync notifier
        container.read(gameStateSyncProvider.notifier);

        // Rogue attempts to hijack Bob's identity with invalid token
        fakeNetService.simulateMessageReceived({
          'type': 'requestRejoin',
          'senderId': 'rogue_socket_1',
          'playerId': 'bob_mimic',
          'name': 'Hacker Bob',
          'rejoinToken': 'wrong_guess',
        });
        await Future<void>.delayed(Duration.zero);

        // Expect host to reject rejoin attempt with rejoinRejected
        final rejectMsgs = fakeNetService.sentToMessages
            .where((m) => m['playerId'] == 'rogue_socket_1')
            .toList();
        expect(rejectMsgs, isNotEmpty, reason: 'Rogue peer must receive rejection response');
        final response = rejectMsgs.first['message'] as Map<String, dynamic>;
        expect(response['type'], equals('rejoinRejected'));
        expect(response['reason'], contains('invalid or missing rejoin token'));

        // Verify Bob's identity was NOT remapped and no secret word was leaked
        expect(gameStateNotifier.state.mimicIds.contains('bob_mimic'), isTrue);
        expect(gameStateNotifier.state.mimicIds.contains('rogue_socket_1'), isFalse);
      });

      test('GameStateSyncNotifier accepts legitimate rejoin with correct rejoinToken', () async {
        final fakeNetService = FakeNetworkService();
        fakeNetService.role = NetworkRole.host;

        final container = ProviderContainer(
          overrides: [
            networkServiceProvider.overrideWith((ref) => fakeNetService),
          ],
        );
        addTearDown(container.dispose);

        final gameStateNotifier = container.read(gameStateProvider.notifier);
        gameStateNotifier.initializeMultiplayerPlayers([
          Player(id: 'host', name: 'Host', color: 0xFF111111),
          Player(id: 'alice_id', name: 'Alice', color: 0xFF222222),
        ]);
        gameStateNotifier.state = gameStateNotifier.state.copyWith(
          currentRound: 1,
          mimicIds: ['alice_id'],
          currentWordPair: const WordPair(
            realWord: 'Doctor',
            mimicWord: 'Surgeon',
            realWordContext: 'Medical doctor',
            mimicWordContext: 'Specialist surgeon',
          ),
        );

        const aliceToken = 'alice_cryptographic_token_123';
        fakeNetService.registerRejoinToken('alice_id', aliceToken);

        container.read(gameStateSyncProvider.notifier);

        // Alice reconnects with new socket ID 'alice_socket_new' and supplies her rejoinToken
        fakeNetService.simulateMessageReceived({
          'type': 'requestRejoin',
          'senderId': 'alice_socket_new',
          'playerId': 'alice_id',
          'name': 'Alice',
          'rejoinToken': aliceToken,
        });
        await Future<void>.delayed(Duration.zero);

        final acceptMsgs = fakeNetService.sentToMessages
            .where((m) => m['playerId'] == 'alice_socket_new')
            .toList();
        expect(acceptMsgs, isNotEmpty, reason: 'Legitimate peer must be accepted');
        final response = acceptMsgs.first['message'] as Map<String, dynamic>;
        expect(response['type'], equals('rejoinAccepted'));
        expect(response['role'], equals('mimic'));
        expect(response['word'], equals('Surgeon'));

        // Verify player ID was remapped in GameState
        expect(gameStateNotifier.state.mimicIds.contains('alice_socket_new'), isTrue);
        expect(gameStateNotifier.state.mimicIds.contains('alice_id'), isFalse);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // AUDIT-03: Room Code Case-Preservation & Entropy Salt
    // ─────────────────────────────────────────────────────────────────────
    group('AUDIT-03: Room Code Encoding, Case Preservation, and Entropy', () {
      String encodeIp(String ip) {
        final parts = ip.split('.');
        final ipInt = (int.parse(parts[0]) << 24) |
                      (int.parse(parts[1]) << 16) |
                      (int.parse(parts[2]) << 8) |
                      int.parse(parts[3]);
        int unsignedIp = ipInt & 0xFFFFFFFF;
        const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        final buffer = StringBuffer();
        int temp = unsignedIp;
        while (temp > 0) {
          buffer.write(chars[temp % 62]);
          temp = temp ~/ 62;
        }
        return buffer.toString().split('').reversed.join().padLeft(6, '0');
      }

      Map<String, dynamic>? decodeRoomCode(String code) {
        final cleanCode = code.replaceAll('-', '').trim();
        if (cleanCode.length < 6) return null;
        final ipPart = cleanCode.substring(0, 6);
        const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        int val = 0;
        for (int i = 0; i < ipPart.length; i++) {
          final char = ipPart[i];
          final index = chars.indexOf(char);
          if (index == -1) return null;
          val = val * 62 + index;
        }
        final octet4 = val & 0xFF;
        final octet3 = (val >> 8) & 0xFF;
        final octet2 = (val >> 16) & 0xFF;
        final octet1 = (val >> 24) & 0xFF;
        return {
          'ip': '$octet1.$octet2.$octet3.$octet4',
          'port': 4567,
          'token': code.trim(),
        };
      }

      test('Base62 mixed-case IP room codes round-trip correctly when case is preserved', () {
        const testIps = ['192.168.1.5', '10.0.0.42', '172.16.254.1', '192.168.100.88'];

        for (final ip in testIps) {
          final code = encodeIp(ip);
          final decoded = decodeRoomCode(code);
          expect(decoded, isNotNull);
          expect(decoded!['ip'], equals(ip),
              reason: 'Case-preserved room code $code must decode back to $ip');
        }
      });

      test('Uppercasing a mixed-case room code produces an incorrect IP (demonstrating AUDIT-03 bug fix)', () {
        const originalIp = '192.168.1.5';
        final correctCode = encodeIp(originalIp);

        if (correctCode.contains(RegExp(r'[a-z]'))) {
          final corruptedCode = correctCode.toUpperCase();
          final decodedCorrupted = decodeRoomCode(corruptedCode);
          expect(decodedCorrupted!['ip'], isNot(equals(originalIp)),
              reason: 'Upper-casing a Base62 code alters numeric value');
        }
      });

      test('Room code with entropy salt (e.g. 6-char IP + 2-char salt) preserves IP and full token', () {
        const originalIp = '192.168.1.50';
        final ipCode = encodeIp(originalIp);
        final saltedCode = '$ipCode-9k';

        final decoded = decodeRoomCode(saltedCode);
        expect(decoded, isNotNull);
        expect(decoded!['ip'], equals(originalIp));
        expect(decoded['token'], equals(saltedCode));
      });
    });
  });
}
