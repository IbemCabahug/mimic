// lib/multiplayer/network/network_service.dart
//
// Abstraction layer over MimicServer and MimicClient.
// This is the ONLY network file that UI and game logic should import.
// Routes all messaging through a unified API regardless of host/guest role.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mimic_client.dart';
import 'mimic_server.dart';

export 'package:mimic/core/providers/provider_registration.dart' show networkServiceProvider;


/// Log helper — uses [debugPrint] so output is suppressed in release builds
/// and the `avoid_print` lint is satisfied.
void _log(String message) => debugPrint('[NetworkService] $message');

// ═══════════════════════════════════════════════════════════════════════════
// Role Enum
// ═══════════════════════════════════════════════════════════════════════════

/// Describes this device's role in the multiplayer session.
enum NetworkRole {
  /// Not connected to any session.
  none,

  /// Running the server; other players connect to this device.
  host,

  /// Connected to another device's server as a guest player.
  guest,
}

// ═══════════════════════════════════════════════════════════════════════════
// NetworkService
// ═══════════════════════════════════════════════════════════════════════════

/// Unified networking facade for Mimic multiplayer.
///
/// Wraps [MimicServer] (for the host) and [MimicClient] (for guests) behind
/// a single API so the rest of the app never needs to know which role this
/// device plays.
///
/// Usage:
/// ```dart
/// final net = ref.read(networkServiceProvider);
///
/// // As host:
/// await net.startAsHost();
/// print('Players can join at ${net.hostIp}:${net.port}');
///
/// // As guest:
/// await net.joinAsGuest('192.168.1.42', 4567);
///
/// // Send (routes automatically):
/// net.send({'type': 'answer', 'word': 'apple'});
///
/// // Listen:
/// net.messageStream.listen((msg) => handleMessage(msg));
///
/// // Cleanup:
/// net.disconnect();
/// ```
class NetworkService extends ChangeNotifier {
  // ─────────────────────────────────────────────────────────────────────
  // Internal state
  // ─────────────────────────────────────────────────────────────────────

  MimicServer? _server;
  MimicClient? _client;
  NetworkRole _role = NetworkRole.none;

  /// Subscription to the active server/client message stream, so we can
  /// cancel it on disconnect and avoid dangling listeners.
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  /// Unified stream controller that re-emits messages from whichever
  /// transport (server or client) is currently active.
  final StreamController<Map<String, dynamic>> _unifiedStream =
      StreamController<Map<String, dynamic>>.broadcast();

  // ─────────────────────────────────────────────────────────────────────
  // Public getters
  // ─────────────────────────────────────────────────────────────────────

  /// The current role of this device in the multiplayer session.
  NetworkRole get role => _role;

  /// The host IP address (only meaningful when [role] is [NetworkRole.host]).
  String? get hostIp => _server?.hostIp;

  /// The port used for the multiplayer session — always `4567`.
  int get port => 4567;

  /// Whether a network session is currently active.
  bool get isConnected {
    switch (_role) {
      case NetworkRole.host:
        return _server != null;
      case NetworkRole.guest:
        return _client?.isConnected ?? false;
      case NetworkRole.none:
        return false;
    }
  }

  /// Unified stream of messages from the active transport.
  ///
  /// - **Host**: receives messages from all connected clients (each with a
  ///   `"senderId"` field).
  /// - **Guest**: receives messages broadcast by the server.
  Stream<Map<String, dynamic>> get messageStream => _unifiedStream.stream;

  /// List of connected player IDs (host only). Returns an empty list for
  /// guests or when not connected.
  List<String> get connectedPlayerIds =>
      _server?.connectedPlayerIds ?? const [];

  /// The player ID assigned to this device by the server (guest only).
  /// Returns `null` for hosts or when not connected.
  String? get assignedPlayerId => _client?.assignedPlayerId;

  // ─────────────────────────────────────────────────────────────────────
  // Host lifecycle
  // ─────────────────────────────────────────────────────────────────────

  /// Creates a [MimicServer], starts it, and sets this device's role to
  /// [NetworkRole.host].
  ///
  /// If already in a session, [disconnect] is called first to clean up.
  Future<void> startAsHost() async {
    try {
      // Clean up any existing session.
      if (_role != NetworkRole.none) {
        disconnect();
      }

      _server = MimicServer();
      await _server!.start();

      _role = NetworkRole.host;

      // Pipe server messages into the unified stream.
      _messageSubscription = _server!.messageStream.listen(
        (message) => _unifiedStream.add(message),
        onError: (Object error) => _log('Server stream error: $error'),
      );

      _log('Started as host on ${_server!.hostIp}:${_server!.port}');
      notifyListeners();
    } catch (e) {
      _log('Failed to start as host: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Guest lifecycle
  // ─────────────────────────────────────────────────────────────────────

  /// Creates a [MimicClient], connects to the given [ip] and [port], and
  /// sets this device's role to [NetworkRole.guest].
  ///
  /// If already in a session, [disconnect] is called first to clean up.
  Future<void> joinAsGuest(String ip, int port) async {
    try {
      // Clean up any existing session.
      if (_role != NetworkRole.none) {
        disconnect();
      }

      _client = MimicClient();
      await _client!.connect(ip, port);

      if (!_client!.isConnected) {
        _log('Failed to connect to $ip:$port');
        _client = null;
        return;
      }

      _role = NetworkRole.guest;

      // Pipe client messages into the unified stream.
      _messageSubscription = _client!.messageStream.listen(
        (message) {
          _unifiedStream.add(message);

          // If disconnected event arrives, reset role.
          if (message['type'] == 'disconnected') {
            _log('Received disconnect event from server.');
            _resetState();
          }
        },
        onError: (Object error) => _log('Client stream error: $error'),
      );

      _log('Joined as guest at $ip:$port');
      notifyListeners();
    } catch (e) {
      _log('Failed to join as guest: $e');
    }
  }

  /// Reconnects the guest client to the host.
  Future<void> reconnect() async {
    if (_role == NetworkRole.guest && _client != null) {
      await _client!.reconnect();
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Messaging
  // ─────────────────────────────────────────────────────────────────────

  /// Sends a [message] through the active transport.
  ///
  /// - **Host**: broadcasts to all connected clients via [MimicServer.broadcast].
  /// - **Guest**: sends to the host via [MimicClient.send].
  void send(Map<String, dynamic> message) {
    try {
      switch (_role) {
        case NetworkRole.host:
          _server?.broadcast(message);
          break;
        case NetworkRole.guest:
          _client?.send(message);
          break;
        case NetworkRole.none:
          _log('Cannot send — not connected.');
          break;
      }
    } catch (e) {
      _log('Failed to send message: $e');
    }
  }

  /// Sends a [message] to a specific [playerId]. **Host only.**
  ///
  /// Does nothing if the current role is not [NetworkRole.host].
  void sendTo(String playerId, Map<String, dynamic> message) {
    if (_role != NetworkRole.host) {
      _log('sendTo is only available for the host.');
      return;
    }
    try {
      _server?.sendTo(playerId, message);
    } catch (e) {
      _log('Failed to sendTo $playerId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Disconnect
  // ─────────────────────────────────────────────────────────────────────

  /// Stops the server or disconnects the client, depending on the current
  /// role, and resets back to [NetworkRole.none].
  void disconnect() {
    try {
      switch (_role) {
        case NetworkRole.host:
          _server?.stop();
          break;
        case NetworkRole.guest:
          _client?.disconnect();
          break;
        case NetworkRole.none:
          break;
      }
    } catch (e) {
      _log('Error during disconnect: $e');
    }
    _resetState();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────

  /// Cleans up internal state and notifies listeners.
  void _resetState() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _server = null;
    _client = null;
    _role = NetworkRole.none;

    _log('Session ended — role reset to none.');
    notifyListeners();
  }
}


