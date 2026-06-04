// lib/multiplayer/network/mimic_client.dart
//
// WebSocket client that runs on guest devices for Mimic multiplayer sessions.
// Connects to a MimicServer host, handles message parsing, automatic player ID
// assignment from the server's "welcome" event, and retry-based reconnection.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds
/// and the `avoid_print` lint is satisfied.
void _log(String message) => debugPrint('[MimicClient] $message');

/// A WebSocket client that connects to a [MimicServer] host.
///
/// Usage:
/// ```dart
/// final client = MimicClient();
/// await client.connect('192.168.1.42', 4567);
///
/// client.messageStream.listen((msg) {
///   print('From host: $msg');
/// });
///
/// client.send({'type': 'answer', 'word': 'apple'});
/// client.disconnect();
/// ```
class MimicClient {
  // ─────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────

  /// Maximum number of reconnection attempts before giving up.
  static const int _maxReconnectAttempts = 3;

  /// Delay between reconnection attempts.
  static const Duration _reconnectDelay = Duration(seconds: 1);

  // ─────────────────────────────────────────────────────────────────────
  // Internal state
  // ─────────────────────────────────────────────────────────────────────

  WebSocket? _socket;
  bool _connected = false;
  String? _assignedPlayerId;

  /// The last IP address used for connection (needed for reconnect).
  String? _lastIp;

  /// The last port used for connection (needed for reconnect).
  int? _lastPort;

  /// Stream controller for inbound messages from the server.
  /// Each message is a decoded JSON map.
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─────────────────────────────────────────────────────────────────────
  // Public getters
  // ─────────────────────────────────────────────────────────────────────

  /// Whether the client currently has an active WebSocket connection.
  bool get isConnected => _connected;

  /// The player ID assigned by the server via the `"welcome"` message,
  /// or `null` if not yet received.
  String? get assignedPlayerId => _assignedPlayerId;

  /// Stream of parsed JSON messages received from the server.
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // ─────────────────────────────────────────────────────────────────────
  // Connection
  // ─────────────────────────────────────────────────────────────────────

  /// Connects to a [MimicServer] at the given [ip] and [port].
  ///
  /// On success, begins listening for server messages. The server will
  /// send a `{"type":"welcome","playerId":"..."}` message that is
  /// automatically captured and stored in [assignedPlayerId].
  Future<void> connect(String ip, int port) async {
    // Store for potential reconnect.
    _lastIp = ip;
    _lastPort = port;

    try {
      final uri = 'ws://$ip:$port';
      _log('Connecting to $uri ...');

      _socket = await WebSocket.connect(uri);
      _connected = true;

      _log('Connected to $uri');

      _socket!.listen(
        _onDataReceived,
        onError: (Object error) {
          _log('Socket error: $error');
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: true,
      );
    } catch (e) {
      _log('Connection failed: $e');
      _connected = false;
    }
  }

  /// Closes the WebSocket connection cleanly.
  void disconnect() {
    try {
      _connected = false;
      _socket?.close(WebSocketStatus.normalClosure, 'Client disconnecting');
      _socket = null;
      _assignedPlayerId = null;
      _log('Disconnected.');
    } catch (e) {
      _log('Error during disconnect: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────────────────

  /// Sends a JSON-encoded [message] to the host server.
  void send(Map<String, dynamic> message) {
    if (_socket == null || !_connected) {
      _log('Cannot send — not connected.');
      return;
    }
    try {
      _socket!.add(jsonEncode(message));
    } catch (e) {
      _log('Failed to send message: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Reconnection
  // ─────────────────────────────────────────────────────────────────────

  /// Attempts to re-establish the connection up to [_maxReconnectAttempts]
  /// times with a [_reconnectDelay] between each attempt.
  ///
  /// Uses the IP and port from the most recent [connect] call.
  /// Does nothing if no previous connection parameters are available.
  Future<void> reconnect() async {
    if (_lastIp == null || _lastPort == null) {
      _log('Cannot reconnect — no previous connection parameters.');
      return;
    }

    // Ensure old socket is cleaned up before retrying.
    _cleanupSocket();

    for (int attempt = 1; attempt <= _maxReconnectAttempts; attempt++) {
      _log('Reconnect attempt $attempt/$_maxReconnectAttempts ...');

      await connect(_lastIp!, _lastPort!);

      if (_connected) {
        _log('Reconnected successfully on attempt $attempt.');
        return;
      }

      // Wait before the next attempt (skip delay after the last failure).
      if (attempt < _maxReconnectAttempts) {
        await Future<void>.delayed(_reconnectDelay);
      }
    }

    _log('Reconnection failed after $_maxReconnectAttempts attempts.');
  }

  // ─────────────────────────────────────────────────────────────────────
  // Private — message handling
  // ─────────────────────────────────────────────────────────────────────

  /// Parses an inbound message from the server and emits it on
  /// [messageStream]. Automatically captures the player ID from
  /// the server's `"welcome"` message.
  void _onDataReceived(dynamic rawData) {
    try {
      final Map<String, dynamic> message =
          jsonDecode(rawData as String) as Map<String, dynamic>;

      // Capture the player ID assigned by the server.
      if (message['type'] == 'welcome' && message.containsKey('playerId')) {
        _assignedPlayerId = message['playerId'] as String;
        _log('Assigned playerId: $_assignedPlayerId');
      }

      _messageController.add(message);
    } catch (e) {
      _log('Bad message from server: $e');
    }
  }

  /// Handles an unexpected disconnect (host closed or network dropped).
  void _handleDisconnect() {
    if (!_connected) return; // already handled

    _connected = false;
    _log('Connection lost.');

    _cleanupSocket();

    // Emit a synthetic disconnect event so the UI can react.
    _messageController.add({
      'type': 'disconnected',
    });
  }

  /// Closes and nulls the socket without emitting disconnect events.
  void _cleanupSocket() {
    try {
      _socket?.close(WebSocketStatus.goingAway, 'Cleanup');
    } catch (_) {
      // Socket may already be closed — ignore.
    }
    _socket = null;
  }
}
