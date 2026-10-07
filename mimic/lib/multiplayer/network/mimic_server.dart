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

  /// Ephemeral session token required for handshake authentication (SEC-04).
  /// When non-null, clients must transmit {'type': 'handshake', 'token': ...}
  /// before they are assigned a playerId or allowed to participate.
  String? sessionToken;

  /// Maximum inbound payload size (32 KB) to prevent memory exhaustion DoS (SEC-11).
  static const int maxPayloadBytes = 32 * 1024;

  /// Pending connections awaiting handshake verification.
  final Map<WebSocket, Timer> _pendingSockets = {};

  /// Connected clients keyed by generated playerId (UUID v4).
  final Map<String, WebSocket> _clients = {};

  /// Ephemeral rejoin tokens mapped to assigned player IDs (AUDIT-02).
  final Map<String, String> _playerRejoinTokens = {};

  /// Per-client rate limiters (SEC-11).
  final Map<String, ClientRateLimiter> _rateLimiters = {};
  final Map<String, int> _rateLimitViolations = {};

  /// IP-level handshake failure tracker to prevent LAN brute force of room codes (VULN-03).
  final Map<String, List<DateTime>> _failedHandshakesPerIp = {};
  final Map<String, DateTime> _bannedIps = {};

  /// Checks if [ip] is temporarily banned from handshaking (VULN-03).
  bool isIpBanned(String ip) {
    final bannedUntil = _bannedIps[ip];
    if (bannedUntil == null) return false;
    if (DateTime.now().isAfter(bannedUntil)) {
      _bannedIps.remove(ip);
      _failedHandshakesPerIp.remove(ip);
      return false;
    }
    return true;
  }

  void _recordFailedHandshake(String ip) {
    if (ip == 'unknown') return;
    final now = DateTime.now();
    final list = _failedHandshakesPerIp.putIfAbsent(ip, () => []);
    list.removeWhere((timestamp) => now.difference(timestamp) > const Duration(minutes: 5));
    list.add(now);
    if (list.length >= 10) {
      _bannedIps[ip] = now.add(const Duration(minutes: 5));
      _log('IP $ip temporarily banned for 5 minutes due to 10 failed handshake attempts (VULN-03).');
    }
  }

  /// Normalizes handshake and room code tokens by removing hyphens, spaces and whitespace (VULN-10).
  static String normalizeToken(String? token) {
    if (token == null) return '';
    return token.replaceAll('-', '').replaceAll(' ', '').trim();
  }

  /// Stream controller for inbound messages from clients.
  /// Each message is a decoded JSON map with an injected `"senderId"` field.
  final StreamController<Map<String, dynamic>> _onMessage =
      StreamController<Map<String, dynamic>>.broadcast();

  /// The IP address the server is bound to, or `null` if not started.
  String? get hostIp => _boundIp;

  /// The port the server listens on.
  int get port => _defaultPort;

  /// Stream of parsed JSON messages received from any connected client.
  /// Each message includes a `"senderId"` field identifying the source player.
  Stream<Map<String, dynamic>> get messageStream => _onMessage.stream;

  /// List of currently connected player IDs.
  List<String> get connectedPlayerIds => List<String>.unmodifiable(_clients.keys);

  /// Whether a rejoin token exists for [playerId] (AUDIT-02).
  bool hasRejoinToken(String playerId) => _playerRejoinTokens.containsKey(playerId);

  /// Verifies whether the provided [token] matches the stored rejoin token
  /// for [playerId] (AUDIT-02).
  bool verifyRejoinToken(String playerId, String? token) {
    if (token == null || token.isEmpty) return false;
    final stored = _playerRejoinTokens[playerId];
    return stored != null && stored == token;
  }

  /// Remaps an existing player's rejoin token to a new socket player ID upon successful rejoin (AUDIT-02).
  void remapRejoinToken(String oldPlayerId, String newPlayerId) {
    final token = _playerRejoinTokens.remove(oldPlayerId);
    if (token != null) {
      _playerRejoinTokens[newPlayerId] = token;
    }
  }

  /// Registers a rejoin token for a player ID (mocking/testing helper).
  void registerRejoinToken(String playerId, String token) {
    _playerRejoinTokens[playerId] = token;
  }

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
      // Cancel pending handshake timers and close unauthenticated sockets.
      for (final timer in _pendingSockets.values) {
        timer.cancel();
      }
      for (final socket in _pendingSockets.keys) {
        try {
          socket.close(WebSocketStatus.goingAway, 'Server shutting down');
        } catch (e) {
          _log('Error closing pending socket: $e');
        }
      }
      _pendingSockets.clear();

      // Close every WebSocket gracefully.
      for (final entry in _clients.entries) {
        try {
          entry.value.close(WebSocketStatus.goingAway, 'Server shutting down');
        } catch (e) {
          _log('Error closing client ${entry.key}: $e');
        }
      }
      _clients.clear();
      _playerRejoinTokens.clear();
      _rateLimiters.clear();
      _rateLimitViolations.clear();
      _failedHandshakesPerIp.clear();
      _bannedIps.clear();

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
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    if (isIpBanned(clientIp)) {
      _log('Rejected connection from rate-limited IP $clientIp (handshake brute-force protection)');
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..write('Too many failed handshake attempts. Try again later.')
        ..close();
      return;
    }

    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _onClientConnected(socket, clientIp: clientIp);
    } catch (e) {
      _log('WebSocket upgrade failed: $e');
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket upgrade required')
        ..close();
    }
  }

  /// Processes a newly connected WebSocket client.
  void _onClientConnected(WebSocket socket, {String clientIp = 'unknown'}) {
    final playerId = _generateUuidV4();
    bool isAuthenticated = (sessionToken == null || sessionToken!.isEmpty);

    if (!isAuthenticated) {
      final timer = Timer(const Duration(seconds: 5), () {
        _pendingSockets.remove(socket);
        _recordFailedHandshake(clientIp);
        _rejectSocket(socket, 'Handshake timeout');
      });
      _pendingSockets[socket] = timer;
    } else {
      _clients[playerId] = socket;
      final rejoinToken = _generateRejoinToken();
      _playerRejoinTokens[playerId] = rejoinToken;
      _log('Player connected: $playerId (${_clients.length} total)');
      _sendWelcome(socket, playerId, rejoinToken: rejoinToken);
    }

    socket.listen(
      (dynamic data) {
        if (data is! String) {
          _log('Rejected non-text frame from $playerId');
          return;
        }

        // Frame size limit (SEC-11)
        if (data.length > maxPayloadBytes) {
          _log('Frame from $playerId exceeded maxPayloadBytes (${data.length} > $maxPayloadBytes)');
          if (isAuthenticated) {
            try {
              socket.close(WebSocketStatus.messageTooBig, 'Payload too large');
            } catch (_) {}
            _onClientDisconnected(playerId);
          } else {
            _pendingSockets.remove(socket)?.cancel();
            _rejectSocket(socket, 'Payload too large');
          }
          return;
        }

        // Rate limiting (SEC-11)
        final limiter = _rateLimiters.putIfAbsent(playerId, () => ClientRateLimiter());
        if (!limiter.tryConsume()) {
          final violations = (_rateLimitViolations[playerId] ?? 0) + 1;
          _rateLimitViolations[playerId] = violations;
          _log('Rate limit exceeded for $playerId ($violations violations)');
          if (violations >= 20) {
            _log('Terminating $playerId for excessive rate limit violations');
            try {
              socket.close(WebSocketStatus.policyViolation, 'Rate limit exceeded');
            } catch (_) {}
            if (isAuthenticated) {
              _onClientDisconnected(playerId);
            } else {
              _pendingSockets.remove(socket)?.cancel();
            }
          }
          return;
        }
        _rateLimitViolations[playerId] = 0;

        if (!isAuthenticated) {
          try {
            final Map<String, dynamic> message =
                jsonDecode(data) as Map<String, dynamic>;
            final incoming = normalizeToken(message['token'] as String?);
            final expected = normalizeToken(sessionToken);
            if (message['type'] == 'handshake' && incoming == expected) {
              isAuthenticated = true;
              _pendingSockets.remove(socket)?.cancel();
              _failedHandshakesPerIp.remove(clientIp);
              _clients[playerId] = socket;
              final rejoinToken = _generateRejoinToken();
              _playerRejoinTokens[playerId] = rejoinToken;
              _log('Player authenticated: $playerId (${_clients.length} total)');
              _sendWelcome(socket, playerId, rejoinToken: rejoinToken);
              return;
            }
          } catch (_) {}

          _pendingSockets.remove(socket)?.cancel();
          _recordFailedHandshake(clientIp);
          _rejectSocket(socket, 'Invalid handshake token');
          return;
        }

        _onDataReceived(playerId, data);
      },
      onError: (Object error) {
        _pendingSockets.remove(socket)?.cancel();
        _log('Socket error from $playerId: $error');
        if (isAuthenticated) {
          _onClientDisconnected(playerId);
        }
      },
      onDone: () {
        _pendingSockets.remove(socket)?.cancel();
        if (isAuthenticated) {
          _onClientDisconnected(playerId);
        }
      },
      cancelOnError: true,
    );
  }

  void _sendWelcome(WebSocket socket, String playerId, {String? rejoinToken}) {
    try {
      socket.add(jsonEncode({
        'type': 'welcome',
        'playerId': playerId,
        if (rejoinToken != null) 'rejoinToken': rejoinToken,
      }));
    } catch (e) {
      _log('Failed to send welcome to $playerId: $e');
    }
  }

  void _rejectSocket(WebSocket socket, String reason) {
    _log('Rejecting unauthenticated connection: $reason');
    try {
      socket.close(WebSocketStatus.policyViolation, reason);
    } catch (_) {}
  }

  /// Parses an inbound message, attaches the sender ID, and pushes it
  /// to the [messageStream].
  void _onDataReceived(String playerId, dynamic rawData) {
    try {
      final Map<String, dynamic> message =
          jsonDecode(rawData as String) as Map<String, dynamic>;

      // Inject the authenticated sender identity so downstream handlers
      // cannot be spoofed by a client claiming a different ID (SEC-04).
      message['senderId'] = playerId;

      // Force castVote to bind strictly to verified senderId (SEC-04)
      if (message['type'] == 'castVote') {
        message['voterId'] = playerId;
      }

      _onMessage.add(message);
    } catch (e) {
      _log('Bad message from $playerId: $e');
    }
  }

  /// Cleans up after a client disconnects and notifies remaining players.
  void _onClientDisconnected(String playerId) {
    final removed = _clients.remove(playerId);
    _rateLimiters.remove(playerId);
    _rateLimitViolations.remove(playerId);
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

  /// Generates a cryptographically strong 128-bit base64url rejoin token (AUDIT-02).
  static String _generateRejoinToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }
}

/// Lightweight token bucket rate limiter to prevent socket flooding (SEC-11).
class ClientRateLimiter {
  final double capacity;
  final double refillRatePerSecond;
  double _tokens;
  DateTime _lastRefill;

  ClientRateLimiter({
    this.capacity = 30.0,
    this.refillRatePerSecond = 15.0,
  })  : _tokens = capacity,
        _lastRefill = DateTime.now();

  bool tryConsume([double tokens = 1.0]) {
    final now = DateTime.now();
    final elapsedSeconds =
        now.difference(_lastRefill).inMicroseconds / 1000000.0;
    _tokens = (_tokens + elapsedSeconds * refillRatePerSecond).clamp(0.0, capacity);
    _lastRefill = now;

    if (_tokens >= tokens) {
      _tokens -= tokens;
      return true;
    }
    return false;
  }
}

