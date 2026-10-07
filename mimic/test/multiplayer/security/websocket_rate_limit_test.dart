// test/multiplayer/security/websocket_rate_limit_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimic/multiplayer/chat_service.dart';
import 'package:mimic/multiplayer/game_sync.dart';
import 'package:mimic/multiplayer/network/mimic_client.dart';
import 'package:mimic/multiplayer/network/mimic_server.dart';
import 'package:mimic/multiplayer/network/network_service.dart';

class MockNetworkService implements NetworkService {
  final List<Map<String, dynamic>> sentMessages = [];
  final StreamController<Map<String, dynamic>> _incoming =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messageStream => _incoming.stream;

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  void emit(Map<String, dynamic> message) {
    _incoming.add(message);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SEC-11: WebSocket Rate Limiting & Frame Size Constraints', () {
    test('ClientRateLimiter enforces capacity and token refills', () async {
      final limiter = ClientRateLimiter(
        capacity: 5.0,
        refillRatePerSecond: 10.0,
      );

      // Consume up to capacity
      for (int i = 0; i < 5; i++) {
        expect(limiter.tryConsume(), isTrue);
      }

      // Exhausted
      expect(limiter.tryConsume(), isFalse);

      // Wait 250ms -> should refill ~2.5 tokens
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(limiter.tryConsume(), isTrue);
    });

    test('ChatService rejects oversized messages (> 500 chars)', () {
      final mockNet = MockNetworkService();
      final chat = ChatService();
      chat.attach(mockNet, localPlayerId: 'p1', localPlayerName: 'Player 1');
      chat.setPhase(ChatPhase.active);

      final validMessage = 'A' * 500;
      expect(chat.sendMessage(validMessage), isTrue);
      expect(mockNet.sentMessages.length, 1);

      final oversizedMessage = 'A' * 501;
      expect(chat.sendMessage(oversizedMessage), isFalse);
      expect(mockNet.sentMessages.length, 1); // No new message sent
    });

    test('ChatService drops incoming oversized messages', () async {
      final mockNet = MockNetworkService();
      final chat = ChatService();
      chat.attach(mockNet, localPlayerId: 'p1', localPlayerName: 'Player 1');
      chat.setPhase(ChatPhase.active);

      // Emit incoming valid message
      mockNet.emit(GameSync.buildChatMessage(
        senderId: 'p2',
        senderName: 'Player 2',
        text: 'Hello world',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chat.messages.length, 1);

      // Emit incoming oversized message (> 500 chars)
      mockNet.emit(GameSync.buildChatMessage(
        senderId: 'p2',
        senderName: 'Player 2',
        text: 'B' * 501,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chat.messages.length, 1); // Oversized message dropped
    });

    test('ChatService enforces client send rate limiting (max 5 per 2s)', () {
      final mockNet = MockNetworkService();
      final chat = ChatService();
      chat.attach(mockNet, localPlayerId: 'p1', localPlayerName: 'Player 1');
      chat.setPhase(ChatPhase.active);

      // Send 5 rapid messages (allowed)
      for (int i = 0; i < 5; i++) {
        expect(chat.sendMessage('Message $i'), isTrue);
      }

      // 6th rapid message is rejected by rate limiter
      expect(chat.sendMessage('Spam message'), isFalse);
      expect(mockNet.sentMessages.length, 5);
    });

    test('MimicServer drops frames exceeding maxPayloadBytes', () async {
      final server = MimicServer();
      await server.start();
      final hostIp = server.hostIp ?? '127.0.0.1';
      final port = server.port;

      final socket = await WebSocket.connect('ws://$hostIp:$port');
      final receivedMessages = <Map<String, dynamic>>[];
      server.messageStream.listen((msg) {
        receivedMessages.add(msg);
      });

      // Wait for welcome message
      final welcomeCompleter = Completer<void>();
      socket.listen((data) {
        final decoded = jsonDecode(data as String) as Map<String, dynamic>;
        if (decoded['type'] == 'welcome') {
          welcomeCompleter.complete();
        }
      });
      await welcomeCompleter.future.timeout(const Duration(seconds: 2));

      // Send normal message
      socket.add(jsonEncode({'type': 'ping'}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(receivedMessages.any((m) => m['type'] == 'ping'), isTrue);

      // Send oversized payload (exceeding maxPayloadBytes = 32KB)
      final hugePayload = jsonEncode({
        'type': 'huge',
        'data': 'X' * (MimicServer.maxPayloadBytes + 100),
      });
      socket.add(hugePayload);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Oversized frame must NOT be pushed to messageStream
      expect(receivedMessages.any((m) => m['type'] == 'huge'), isFalse);

      socket.close();
      server.stop();
    });
  });
}
