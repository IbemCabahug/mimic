// lib/multiplayer/network/disconnect_handler.dart
//
// Handles all disconnect scenarios gracefully for both host and guest devices.
// Monitors ping/pong health and orchestrates reconnections or lobby cleanups.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';

export 'package:mimic/core/providers/provider_registration.dart' show disconnectHandlerProvider;


/// Describes the source/cause of a disconnection event.
enum DisconnectType { hostLeft, guestLeft, networkLost, timeout }

/// Represents a distinct disconnection event in a multiplayer session.
class DisconnectEvent {
  final DisconnectType type;
  final String? playerId;
  final String? displayName;
  final DateTime timestamp;

  const DisconnectEvent({
    required this.type,
    this.playerId,
    this.displayName,
    required this.timestamp,
  });
}

/// Central controller for monitoring socket health and handling dropouts.
class DisconnectHandler {
  final NetworkService networkService;
  final GameStateSyncNotifier gameStateSyncNotifier;

  StreamSubscription<Map<String, dynamic>>? _messageSub;
  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  bool _pongReceived = true;

  final StreamController<DisconnectEvent> _disconnectController =
      StreamController<DisconnectEvent>.broadcast();

  DisconnectHandler(this.networkService, this.gameStateSyncNotifier) {
    _subscribe();
  }

  /// Broadcast stream emitting disconnection events.
  Stream<DisconnectEvent> get disconnectStream => _disconnectController.stream;

  void _subscribe() {
    _messageSub?.cancel();
    _messageSub = networkService.messageStream.listen(_handleIncomingMessage);
  }

  /// Listens to low-level message events to capture ping requests, replies,
  /// or server-reported dropouts.
  void _handleIncomingMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;

    // HOST Perspective
    if (networkService.role == NetworkRole.host) {
      if (type == 'ping') {
        final senderId = message['senderId'] as String?;
        if (senderId != null) {
          networkService.sendTo(senderId, {'type': 'pong'});
        }
      } else if (type == 'playerLeft') {
        final playerId = message['playerId'] as String?;
        if (playerId != null) {
          final displayName =
              gameStateSyncNotifier.getPlayerDisplayName(playerId);
          _handleDisconnect(DisconnectEvent(
            type: DisconnectType.guestLeft,
            playerId: playerId,
            displayName: displayName,
            timestamp: DateTime.now(),
          ));
        }
      }
    }

    // GUEST Perspective
    if (networkService.role == NetworkRole.guest) {
      if (type == 'ping') {
        networkService.send({'type': 'pong'});
      } else if (type == 'pong') {
        _pongReceived = true;
        _pongTimeoutTimer?.cancel();
      } else if (type == 'disconnected') {
        _handleDisconnect(DisconnectEvent(
          type: DisconnectType.networkLost,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  /// Sets up a periodic ping every 5 seconds.
  /// - Host: sends pings to all clients.
  /// - Guest: sends pings to Host and expects pongs within 3 seconds.
  void startMonitoring() {
    stopMonitoring(); // Cancel previous timers

    if (_messageSub == null) {
      _subscribe();
    }

    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (networkService.role == NetworkRole.host) {
        networkService.send({'type': 'ping'});
      } else if (networkService.role == NetworkRole.guest) {
        _pongReceived = false;
        networkService.send({'type': 'ping'});

        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = Timer(const Duration(seconds: 3), () {
          if (!_pongReceived) {
            _handleDisconnect(DisconnectEvent(
              type: DisconnectType.timeout,
              timestamp: DateTime.now(),
            ));
          }
        });
      }
    });
  }

  /// Cancels active ping timers and tears down message stream subscriptions.
  void stopMonitoring() {
    _pingTimer?.cancel();
    _pingTimer = null;

    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;

    _messageSub?.cancel();
    _messageSub = null;
  }

  /// Handles a resolved disconnection event based on role-specific logic.
  Future<void> _handleDisconnect(DisconnectEvent event) async {
    _disconnectController.add(event);

    if (event.type == DisconnectType.hostLeft) {
      final context = MimicGame.navigatorKey.currentContext;
      if (context != null) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: HorrorColors.deepSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
              ),
              title: Text(
                'CONNECTION LOST',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 22,
                  letterSpacing: 1.5,
                ),
              ),
              content: Text(
                'Host ended the room.',
                style: GoogleFonts.inter(
                  color: HorrorColors.fogWhite,
                  fontSize: 16,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Dismiss dialog
                    _popToMultiplayerMenu(context);
                  },
                  child: Text(
                    'OK',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.crimson,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
    } else if (event.type == DisconnectType.guestLeft) {
      final playerId = event.playerId;
      if (playerId != null) {
        // Triggers the state cleanups (removes from lobby or marks as eliminated)
        gameStateSyncNotifier.handlePlayerLeft(playerId);

        // Notify remaining clients of the departure
        networkService.send({
          'type': 'playerLeft',
          'playerId': playerId,
          'displayName': event.displayName ?? '',
        });
      }
    } else if (event.type == DisconnectType.networkLost ||
        event.type == DisconnectType.timeout) {
      if (networkService.role == NetworkRole.guest) {
        // Attempt to reconnect
        await networkService.reconnect();

        if (!networkService.isConnected) {
          // Escalates to hostLeft event if reconnection attempts fail
          _handleDisconnect(DisconnectEvent(
            type: DisconnectType.hostLeft,
            timestamp: DateTime.now(),
          ));
        }
      }
    }
  }

  void _popToMultiplayerMenu(BuildContext context) {
    bool hasMultiplayerRoute = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == MimicGame.multiplayerRoute) {
        hasMultiplayerRoute = true;
        return true;
      }
      return route.isFirst;
    });

    if (!hasMultiplayerRoute) {
      Navigator.of(context).pushReplacementNamed(MimicGame.multiplayerRoute);
    }
  }
}


