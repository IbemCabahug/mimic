// lib/multiplayer/chat_service.dart
//
// Text chat message relay for the discussion phase.
// Works with NetworkService to send/receive chat messages.
// Auto-disabled during word reveal, voting, and results phases.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimic/multiplayer/game_sync.dart';
import 'package:mimic/multiplayer/network/network_service.dart';

/// Log helper — uses [debugPrint] so output is suppressed in release builds.
void _log(String message) => debugPrint('[ChatService] $message');

// ═══════════════════════════════════════════════════════════════════════════
// Chat Message Model
// ═══════════════════════════════════════════════════════════════════════════

/// Represents a single chat message in the discussion phase.
class ChatMessage {
  /// Unique message ID.
  final String id;

  /// Sender's player ID.
  final String senderId;

  /// Sender's display name.
  final String senderName;

  /// Message text content.
  final String text;

  /// Timestamp when the message was sent.
  final DateTime timestamp;

  /// Whether this message was sent by the local player.
  final bool isLocal;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.isLocal = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Chat Phase Control
// ═══════════════════════════════════════════════════════════════════════════

/// Phases where chat is allowed or blocked.
enum ChatPhase {
  /// Chat is enabled.
  active,

  /// Chat is disabled (word reveal, voting, results).
  disabled,
}

// ═══════════════════════════════════════════════════════════════════════════
// ChatService
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing text chat during multiplayer discussion phases.
///
/// Features:
/// - Send and receive messages via the existing [NetworkService]
/// - Phase-aware: automatically disables during voting/reveal/results
/// - Maintains scrollable message history per session
/// - Notifies listeners on new messages for UI updates
///
/// Usage:
/// ```dart
/// final chat = ref.read(chatServiceProvider);
/// chat.attach(networkService, localPlayerId: 'id', localPlayerName: 'name');
///
/// // Send a message
/// chat.sendMessage('I think Player 3 is the Mimic!');
///
/// // Listen for updates
/// chat.addListener(() {
///   final messages = chat.messages; // Updated list
/// });
///
/// // Control phases
/// chat.setPhase(ChatPhase.disabled); // During voting
/// chat.setPhase(ChatPhase.active);   // During discussion
/// ```
class ChatService extends ChangeNotifier {
  // ─────────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────────

  NetworkService? _networkService;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  String _localPlayerId = '';
  String _localPlayerName = '';
  ChatPhase _phase = ChatPhase.disabled;

  final List<ChatMessage> _messages = [];
  int _messageCounter = 0;

  // ─────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────

  /// All chat messages in chronological order.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Current chat phase.
  ChatPhase get phase => _phase;

  /// Whether chat is currently active and accepting messages.
  bool get isActive => _phase == ChatPhase.active;

  /// Number of messages in the current session.
  int get messageCount => _messages.length;

  /// Whether the service is attached to a network session.
  bool get isAttached => _networkService != null;

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  /// Attach to a [NetworkService] and start listening for chat messages.
  void attach(
    NetworkService networkService, {
    required String localPlayerId,
    required String localPlayerName,
  }) {
    detach(); // Clean up any previous session

    _networkService = networkService;
    _localPlayerId = localPlayerId;
    _localPlayerName = localPlayerName;
    _messages.clear();
    _messageCounter = 0;

    // Listen for incoming chat messages
    _messageSubscription = networkService.messageStream.listen(_onMessage);

    _log('Attached — player: $_localPlayerName ($localPlayerId)');
    notifyListeners();
  }

  /// Detach from the network and stop listening.
  void detach() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _networkService = null;
    _phase = ChatPhase.disabled;
    _log('Detached');
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Phase Control
  // ─────────────────────────────────────────────────────────────────────

  /// Set the current chat phase.
  /// Chat is only allowed when phase is [ChatPhase.active].
  void setPhase(ChatPhase phase) {
    if (_phase != phase) {
      _phase = phase;
      _log('Phase changed to: ${phase.name}');
      notifyListeners();
    }
  }

  /// Enable chat (convenience method for discussion phase).
  void enable() => setPhase(ChatPhase.active);

  /// Disable chat (convenience method for voting/reveal/results).
  void disable() => setPhase(ChatPhase.disabled);

  // ─────────────────────────────────────────────────────────────────────
  // Sending
  // ─────────────────────────────────────────────────────────────────────

  /// Send a text message to all players.
  /// Returns false if chat is disabled or not attached.
  bool sendMessage(String text) {
    if (!isActive || _networkService == null) {
      _log('Cannot send — chat is ${isActive ? "not attached" : "disabled"}');
      return false;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // Build the network message
    final networkMsg = GameSync.buildChatMessage(
      senderId: _localPlayerId,
      senderName: _localPlayerName,
      text: trimmed,
    );

    // Send over network
    _networkService!.send(networkMsg);

    // Add to local messages immediately (optimistic update)
    _messageCounter++;
    final localMessage = ChatMessage(
      id: '${_localPlayerId}_$_messageCounter',
      senderId: _localPlayerId,
      senderName: _localPlayerName,
      text: trimmed,
      timestamp: DateTime.now(),
      isLocal: true,
    );
    _messages.add(localMessage);

    _log('Sent: "$trimmed"');
    notifyListeners();
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────
  // Receiving
  // ─────────────────────────────────────────────────────────────────────

  /// Handle incoming network messages — filter for chat messages.
  void _onMessage(Map<String, dynamic> message) {
    final type = GameSync.getMessageType(message);
    if (type != GameMessageType.chatMessage) return;

    final parsed = GameSync.parseChatMessage(message);
    if (parsed == null) return;

    // Don't duplicate our own messages (we already added them optimistically)
    if (parsed.senderId == _localPlayerId) return;

    _messageCounter++;
    final chatMessage = ChatMessage(
      id: '${parsed.senderId}_$_messageCounter',
      senderId: parsed.senderId,
      senderName: parsed.senderName,
      text: parsed.text,
      timestamp: parsed.timestamp,
      isLocal: false,
    );

    _messages.add(chatMessage);
    _log('Received from ${parsed.senderName}: "${parsed.text}"');
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Session Management
  // ─────────────────────────────────────────────────────────────────────

  /// Clear all messages (e.g., at the start of a new round).
  void clearMessages() {
    _messages.clear();
    _messageCounter = 0;
    _log('Messages cleared');
    notifyListeners();
  }

  /// Add a system message (e.g., "Player X was eliminated").
  void addSystemMessage(String text) {
    _messageCounter++;
    _messages.add(ChatMessage(
      id: 'system_$_messageCounter',
      senderId: 'system',
      senderName: 'SYSTEM',
      text: text,
      timestamp: DateTime.now(),
      isLocal: false,
    ));
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Riverpod Provider
// ═══════════════════════════════════════════════════════════════════════════

final chatServiceProvider = ChangeNotifierProvider<ChatService>((ref) {
  return ChatService();
});
