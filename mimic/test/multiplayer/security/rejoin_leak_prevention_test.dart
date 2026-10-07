import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimic/game/data/word_packs.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/game_sync.dart';
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

  final Map<String, String> _rejoinTokens = {};

  @override
  bool hasRejoinToken(String playerId) => _rejoinTokens.containsKey(playerId);

  @override
  bool verifyRejoinToken(String playerId, String? token) =>
      token != null && _rejoinTokens[playerId] == token;

  @override
  void remapRejoinToken(String oldPlayerId, String newPlayerId) {
    final token = _rejoinTokens.remove(oldPlayerId);
    if (token != null) {
      _rejoinTokens[newPlayerId] = token;
    }
  }

  void registerRejoinToken(String playerId, String token) {
    _rejoinTokens[playerId] = token;
  }

  @override
  void disconnect() {
    _isConnected = false;
    _role = NetworkRole.none;
    _connectedPlayerIds.clear();
    _rejoinTokens.clear();
    notifyListeners();
  }
}

void main() {
  group('SEC-03: Multiplayer Rejoin Secret Redaction Tests', () {
    const secretWordPair = WordPair(
      realWord: 'Astronaut',
      mimicWord: 'Alien',
      realWordContext: 'Space traveler from Earth',
      mimicWordContext: 'Extraterrestrial creature',
      realWordProContext: 'Pro Space traveler',
      mimicWordProContext: 'Pro Alien creature',
    );

    late GameState sampleState;

    setUp(() {
      sampleState = GameState(
        selectedMode: GameMode.classic,
        currentRound: 1,
        maxRounds: 3,
        players: [
          Player(id: 'host', name: 'Host Player', color: 0xFF111111),
          Player(id: 'villager_1', name: 'Alice', color: 0xFF222222),
          Player(id: 'mimic_1', name: 'Bob', color: 0xFF333333),
          Player(id: 'mimic_2', name: 'Charlie', color: 0xFF444444),
        ],
        mimicIds: ['mimic_1', 'mimic_2'],
        currentWordPair: secretWordPair,
        secondMimicWord: 'Martian',
      );
    });

    test('serializeSanitizedState sanitizes all secrets for a villager', () {
      final sanitized = GameSync.serializeSanitizedState(
        sampleState,
        forPlayerId: 'villager_1',
      );

      // 1. Mimic IDs must be empty so villager cannot discover who the Mimics are
      expect(sanitized['mimicIds'], isEmpty);

      // 2. Second mimic word must be null
      expect(sanitized['secondMimicWord'], isNull);

      // 3. Word pair must contain only the villager's assigned word for both fields
      final wordPairMap = sanitized['currentWordPair'] as Map<String, dynamic>;
      expect(wordPairMap['realWord'], 'Astronaut');
      expect(wordPairMap['mimicWord'], 'Astronaut');
      expect(wordPairMap['realWordContext'], 'Space traveler from Earth');
      expect(wordPairMap['mimicWordContext'], 'Space traveler from Earth');

      // 4. Secret mimic words must NOT appear in the entire JSON payload
      final jsonString = jsonEncode(sanitized);
      expect(jsonString.contains('Alien'), isFalse,
          reason: 'Mimic word Alien must not be leaked in villager snapshot');
      expect(jsonString.contains('Martian'), isFalse,
          reason: 'Second mimic word Martian must not be leaked in villager snapshot');
    });

    test('serializeSanitizedState reveals only own identity for a mimic', () {
      final sanitized = GameSync.serializeSanitizedState(
        sampleState,
        forPlayerId: 'mimic_1',
      );

      // 1. Mimic only sees their own ID, not the second mimic
      expect(sanitized['mimicIds'], equals(['mimic_1']));

      // 2. Second mimic word must be null
      expect(sanitized['secondMimicWord'], isNull);

      // 3. Word pair must contain only the mimic word for both fields
      final wordPairMap = sanitized['currentWordPair'] as Map<String, dynamic>;
      expect(wordPairMap['realWord'], 'Alien');
      expect(wordPairMap['mimicWord'], 'Alien');
      expect(wordPairMap['realWordContext'], 'Extraterrestrial creature');
      expect(wordPairMap['mimicWordContext'], 'Extraterrestrial creature');

      // 4. Real word (Astronaut) must NOT appear in mimic snapshot
      final jsonString = jsonEncode(sanitized);
      expect(jsonString.contains('Astronaut'), isFalse,
          reason: 'Real word Astronaut must not be leaked to mimic');
      expect(sanitized['mimicIds'].contains('mimic_2'), isFalse,
          reason: 'Second mimic ID must not be leaked in mimicIds to first mimic');
    });

    test('Host _handleRejoin redacts state attached to rejoinAccepted message', () async {
      final fakeNetworkService = FakeNetworkService();
      fakeNetworkService.role = NetworkRole.host;
      fakeNetworkService.connectedPlayerIds.addAll(['villager_1', 'mimic_1']);

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

      // Set up the game on host
      final gameStateNotifier = container.read(gameStateProvider.notifier);
      gameStateNotifier.initializeMultiplayerPlayers([
        Player(id: 'host', name: 'Host', color: 0xFF111111),
        Player(id: 'villager_1', name: 'Alice', color: 0xFF222222),
        Player(id: 'mimic_1', name: 'Bob', color: 0xFF333333),
      ]);
      // Manually set mimic and word pair
      gameStateNotifier.state = gameStateNotifier.state.copyWith(
        currentRound: 1,
        mimicIds: ['mimic_1'],
        currentWordPair: secretWordPair,
        secondMimicWord: 'Martian',
      );

      // Force instantiation of sync notifier
      container.read(gameStateSyncProvider.notifier);

      fakeNetworkService.registerRejoinToken('villager_1', 'sec_rejoin_token_123');

      // Simulate a dropped villager reconnecting with new connection ID 'villager_1_reconnected'
      fakeNetworkService.simulateMessageReceived({
        'type': 'requestRejoin',
        'senderId': 'villager_1_reconnected',
        'playerId': 'villager_1',
        'name': 'Alice',
        'rejoinToken': 'sec_rejoin_token_123',
      });
      await Future<void>.delayed(Duration.zero);

      // Verify that rejoinAccepted was sent to the rejoining client
      final rejoinMessages = fakeNetworkService.sentToMessages
          .where((m) => m['playerId'] == 'villager_1_reconnected')
          .toList();

      expect(rejoinMessages, isNotEmpty);
      final response = rejoinMessages.first['message'] as Map<String, dynamic>;
      expect(response['type'], 'rejoinAccepted');
      expect(response['role'], 'villager');
      expect(response['word'], 'Astronaut');

      // CRITICAL CHECK: Verify the embedded gameState payload does NOT leak mimic secrets
      final stateSnapshot = response['gameState'] as Map<String, dynamic>;
      expect(stateSnapshot['mimicIds'], isEmpty);
      expect(stateSnapshot['secondMimicWord'], isNull);

      final responseJson = jsonEncode(response);
      expect(responseJson.contains('Alien'), isFalse,
          reason: 'rejoinAccepted payload must not leak mimic word');
      expect(responseJson.contains('Martian'), isFalse,
          reason: 'rejoinAccepted payload must not leak second mimic word');
    });

    test('Host _handleRejoin redacts state when an unknown/untrusted peer requests rejoin', () async {
      final fakeNetworkService = FakeNetworkService();
      fakeNetworkService.role = NetworkRole.host;

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
        Player(id: 'villager_1', name: 'Alice', color: 0xFF222222),
        Player(id: 'mimic_1', name: 'Bob', color: 0xFF333333),
      ]);
      gameStateNotifier.state = gameStateNotifier.state.copyWith(
        currentRound: 1,
        mimicIds: ['mimic_1'],
        currentWordPair: secretWordPair,
      );

      container.read(gameStateSyncProvider.notifier);

      // Rogue connection attempts to harvest game state
      fakeNetworkService.simulateMessageReceived({
        'type': 'requestRejoin',
        'senderId': 'rogue_sniffer',
        'playerId': 'non_existent_id',
        'name': 'Hacker',
      });
      await Future<void>.delayed(Duration.zero);

      final rogueMessages = fakeNetworkService.sentToMessages
          .where((m) => m['playerId'] == 'rogue_sniffer')
          .toList();

      expect(rogueMessages, isNotEmpty);
      final response = rogueMessages.first['message'] as Map<String, dynamic>;
      final stateSnapshot = response['gameState'] as Map<String, dynamic>;

      // Rogue peer must receive zero mimic IDs and cannot see mimic word
      expect(stateSnapshot['mimicIds'], isEmpty);
      final responseJson = jsonEncode(response);
      expect(responseJson.contains('Alien'), isFalse);
    });
  });
}
