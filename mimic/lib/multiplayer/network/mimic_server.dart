// lib/multiplayer/network/mimic_server.dart
//
// WebSocket server that runs on the host device for Mimic multiplayer sessions.
// Binds to the local Wi-Fi interface IP on port 4567 and manages player
// connections, message routing, and broadcast/unicast delivery.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds
/// and the `avoid_print` lint is satisfied.
void _log(String message) => debugPrint('[MimicServer] $message');

/// A WebSocket-based game server that runs on the host player's device.
///
/// Usage:
/// ```dart
/// final server = MimicServer();
/// await server.start();
/// print('Server running at ${server.hostIp}:${server.port}');
///
/// server.messageStream.listen((msg) {
///   print('Received: $msg');
/// });
///
/// server.broadcast({'type': 'gameStart', 'round': 1});
/// server.stop();
/// ```
class MimicServer {
  // ─────────────────────────────────────────────────────────────────────
  // Constants
  // ─────────────────────────────────────────────────────────────────────

  static const int _defaultPort = 4567;

  // ─────────────────────────────────────────────────────────────────────
  // Internal state
  // ─────────────────────────────────────────────────────────────────────

  HttpServer? _httpServer;
  String? _boundIp;

  /// Connected clients keyed by generated playerId (UUID v4).
  final Map<String, WebSocket> _clients = {};

  /// Stream controller for inbound messages from clients.
  /// Each message is a decoded JSON map with an injected `"senderId"` field.
  final StreamController<Map<String, dynamic>> _onMessage =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─────────────────────────────────────────────────────────────────────
  // Public getters
  // ─────────────────────────────────────────────────────────────────────

  /// The IP address the server is bound to, or `null` if not started.
  String? get hostIp => _boundIp;

  /// The port the server listens on.
  int get port => _defaultPort;

  /// Stream of parsed JSON messages received from any connected client.
  /// Each message includes a `"senderId"` field identifying the source player.
  Stream<Map<String, dynamic>> get messageStream => _onMessage.stream;

  /// List of currently connected player IDs.
  List<String> get connectedPlayerIds => List<String>.unmodifiable(_clients.keys);

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  /// Starts the WebSocket server.
  ///
  /// Discovers the local Wi-Fi IP address (wlan0 / en0) and binds an
  /// [HttpServer] to it on port [_defaultPort]. Falls back to `0.0.0.0`
  /// if no Wi-Fi interface is found.
  Future<void> start() async {
    try {
      _boundIp = await _resolveLocalIp();
      _httpServer = await HttpServer.bind(_boundIp!, _defaultPort);

      _log('Listening on $_boundIp:$_defaultPort');

      _httpServer!.listen(
        _handleHttpRequest,
        onError: (Object error) {
          _log('HTTP server error: $error');
        },
        onDone: () {
          _log('HTTP server closed.');
        },
      );
    } catch (e) {
      _log('Failed to start server: $e');
    }
  }

  /// Closes all client connections and shuts down the server.
  void stop() {
    try {
      // Close every WebSocket gracefully.
      for (final entry in _clients.entries) {
        try {
          entry.value.close(WebSocketStatus.goingAway, 'Server shutting down');
        } catch (e) {
          _log('Error closing client ${entry.key}: $e');
        }
      }
      _clients.clear();

      _httpServer?.close(force: true);
      _httpServer = null;
      _boundIp = null;

      _log('Server stopped.');
    } catch (e) {
      _log('Error during shutdown: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────────────────

  /// Sends a JSON-encoded [message] to every connected client.
  void broadcast(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final entry in _clients.entries) {
      try {
        entry.value.add(encoded);
      } catch (e) {
        _log('Failed to send to ${entry.key}: $e');
      }
    }
  }

  /// Sends a JSON-encoded [message] to a single client identified by [playerId].
  void sendTo(String playerId, Map<String, dynamic> message) {
    final socket = _clients[playerId];
    if (socket == null) {
      _log('sendTo failed — player $playerId not connected.');
      return;
    }
    try {
      socket.add(jsonEncode(message));
    } catch (e) {
      _log('Failed to send to $playerId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Private — HTTP upgrade & WebSocket handling
  // ─────────────────────────────────────────────────────────────────────

  /// Handles an incoming HTTP request by upgrading it to a WebSocket.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _onClientConnected(socket);
    } catch (e) {
      _log('WebSocket upgrade failed: $e');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade required')
        ..close();
    }
  }

  /// Processes a newly connected WebSocket client.
  void _onClientConnected(WebSocket socket) {
    final playerId = _generateUuidV4();

    _clients[playerId] = socket;
    _log('Player connected: $playerId (${_clients.length} total)');

    // Send welcome message with the assigned player ID.
    try {
      socket.add(jsonEncode({
        'type': 'welcome',
        'playerId': playerId,
      }));
    } catch (e) {
      _log('Failed to send welcome to $playerId: $e');
    }

    // Listen for messages and disconnection.
    socket.listen(
      (dynamic data) => _onDataReceived(playerId, data),
      onError: (Object error) {
        _log('Socket error from $playerId: $error');
        _onClientDisconnected(playerId);
      },
      onDone: () => _onClientDisconnected(playerId),
      cancelOnError: true,
    );
  }

  /// Parses an inbound message, attaches the sender ID, and pushes it
  /// to the [messageStream].
  void _onDataReceived(String playerId, dynamic rawData) {
    try {
      final Map<String, dynamic> message =
          jsonDecode(rawData as String) as Map<String, dynamic>;

      // Inject the authenticated sender identity so downstream handlers
      // cannot be spoofed by a client claiming a different ID.
      message['senderId'] = playerId;

      _onMessage.add(message);
    } catch (e) {
      _log('Bad message from $playerId: $e');
    }
  }

  /// Cleans up after a client disconnects and notifies remaining players.
  void _onClientDisconnected(String playerId) {
    final removed = _clients.remove(playerId);
    if (removed == null) return; // already cleaned up

    _log('Player disconnected: $playerId (${_clients.length} remaining)');

    // Notify remaining clients that a player has left.
    broadcast({
      'type': 'playerLeft',
      'playerId': playerId,
    });

    // Also push to the server-side message stream so the host game logic
    // can react to departures.
    _onMessage.add({
      'type': 'playerLeft',
      'playerId': playerId,
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // Private — Network utilities
  // ─────────────────────────────────────────────────────────────────────

  /// Resolves the device's local Wi-Fi IPv4 address.
  ///
  /// Scans [NetworkInterface]s for common Wi-Fi names (`wlan0` on Android/
  /// Linux, `en0` on macOS/iOS). Returns the first non-loopback IPv4
  /// address found, or `'0.0.0.0'` as a fallback.
  Future<String> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      // Preferred Wi-Fi interface names by platform.
      const wifiNames = <String>{'wlan0', 'en0', 'Wi-Fi', 'wlan1'};

      // First pass: look for a known Wi-Fi interface.
      for (final iface in interfaces) {
        if (wifiNames.contains(iface.name)) {
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // Second pass: return the first non-loopback IPv4 from any interface.
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      _log('Failed to resolve local IP: $e');
    }

    // Ultimate fallback — bind to all interfaces.
    return '0.0.0.0';
  }

  // ─────────────────────────────────────────────────────────────────────
  // Private — UUID v4 generation
  // ─────────────────────────────────────────────────────────────────────

  static final Random _random = Random.secure();

  /// Generates a RFC 4122 version 4 UUID string.
  ///
  /// Uses [Random.secure] for cryptographically strong randomness.
  /// Format: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
  static String _generateUuidV4() {
    // 16 random bytes.
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Set version (4) in byte 6: 0100xxxx
    bytes[6] = (bytes[6] & 0x0F) | 0x40;

    // Set variant (10xxxxxx) in byte 8.
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // Format as 8-4-4-4-12 hex string.
    String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');

    return '${hex(bytes[0])}${hex(bytes[1])}${hex(bytes[2])}${hex(bytes[3])}-'
        '${hex(bytes[4])}${hex(bytes[5])}-'
        '${hex(bytes[6])}${hex(bytes[7])}-'
        '${hex(bytes[8])}${hex(bytes[9])}-'
        '${hex(bytes[10])}${hex(bytes[11])}${hex(bytes[12])}'
        '${hex(bytes[13])}${hex(bytes[14])}${hex(bytes[15])}';
  }
}
