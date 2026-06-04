// lib/multiplayer/screens/lobby_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/game.dart';

/// Log helper
void _log(String message) => debugPrint('[LobbyScreen] $message');

class LobbyPlayer {
  final String id;
  final String name;
  bool isReady;

  LobbyPlayer({
    required this.id,
    required this.name,
    this.isReady = false,
  });
}

class LobbyScreen extends ConsumerStatefulWidget {
  final bool isHost;
  final Map<String, String>? initialPlayers;

  const LobbyScreen({
    super.key,
    required this.isHost,
    this.initialPlayers,
  });

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<LobbyPlayer> _players = [];
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  bool _isSelfReady = false;

  @override
  void initState() {
    super.initState();

    // Host initializes list with itself and any guest who joined first
    if (widget.isHost && widget.initialPlayers != null) {
      widget.initialPlayers!.forEach((id, name) {
        _players.add(LobbyPlayer(
          id: id,
          name: name,
          isReady: id == 'host', // Host is ready by default
        ));
      });
      _isSelfReady = true;
    }

    _subscribeToEvents();
  }

  void _subscribeToEvents() {
    final netService = ref.read(networkServiceProvider);

    _messageSubscription = netService.messageStream.listen(
      (message) {
        if (!mounted) return;
        final type = message['type'];

        if (widget.isHost) {
          _handleHostMessages(message, type);
        } else {
          _handleGuestMessages(message, type);
        }
      },
      onError: (Object error) {
        _log('Error on message stream: $error');
      },
    );
  }

  void _handleHostMessages(Map<String, dynamic> message, dynamic type) {
    final senderId = message['senderId'] as String?;

    if (type == 'playerJoined') {
      final name = message['name'] as String? ?? 'Survivor';
      if (senderId != null && !_players.any((p) => p.id == senderId)) {
        setState(() {
          _players.add(LobbyPlayer(id: senderId, name: name));
        });
        _listKey.currentState?.insertItem(
          _players.length - 1,
          duration: const Duration(milliseconds: 300),
        );
        _broadcastLobbyUpdate();
      }
    } else if (type == 'playerLeft') {
      final playerId = message['playerId'] as String?;
      if (playerId != null) {
        final index = _players.indexWhere((p) => p.id == playerId);
        if (index != -1) {
          final removedPlayer = _players.removeAt(index);
          _listKey.currentState?.removeItem(
            index,
            (context, animation) => _buildPlayerCard(removedPlayer, animation, index),
            duration: const Duration(milliseconds: 300),
          );
          _broadcastLobbyUpdate();
        }
      }
    } else if (type == 'playerReady') {
      final playerId = message['playerId'] as String?;
      if (playerId != null) {
        final index = _players.indexWhere((p) => p.id == playerId);
        if (index != -1) {
          setState(() {
            _players[index].isReady = true;
          });
          _broadcastLobbyUpdate();
        }
      }
    }
  }

  void _handleGuestMessages(Map<String, dynamic> message, dynamic type) {
    if (type == 'lobbyUpdate') {
      final List<dynamic> playersData = message['players'] as List<dynamic>;
      _syncPlayersList(playersData.cast<Map<String, dynamic>>());
    } else if (type == 'startGame') {
      _startGameTransition();
    } else if (type == 'disconnected') {
      _showHostEndedDialog();
    }
  }

  void _syncPlayersList(List<Map<String, dynamic>> newPlayersList) {
    final newIds = newPlayersList.map((p) => p['id'] as String).toSet();

    // 1. Remove players not in host list
    for (int i = _players.length - 1; i >= 0; i--) {
      final player = _players[i];
      if (!newIds.contains(player.id)) {
        final removedPlayer = _players.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => _buildPlayerCard(removedPlayer, animation, i),
          duration: const Duration(milliseconds: 300),
        );
      }
    }

    // 2. Add or update players
    for (int i = 0; i < newPlayersList.length; i++) {
      final data = newPlayersList[i];
      final id = data['id'] as String;
      final name = data['name'] as String;
      final isReady = data['isReady'] as bool? ?? false;

      final existingIndex = _players.indexWhere((p) => p.id == id);
      if (existingIndex == -1) {
        final newPlayer = LobbyPlayer(id: id, name: name, isReady: isReady);
        _players.add(newPlayer);
        _listKey.currentState?.insertItem(
          _players.length - 1,
          duration: const Duration(milliseconds: 300),
        );
      } else {
        if (_players[existingIndex].isReady != isReady) {
          setState(() {
            _players[existingIndex].isReady = isReady;
          });
        }
      }
    }

    // Check if self ready state has been confirmed in the host roster
    final selfId = ref.read(networkServiceProvider).assignedPlayerId;
    final selfIndex = _players.indexWhere((p) => p.id == selfId);
    if (selfIndex != -1) {
      setState(() {
        _isSelfReady = _players[selfIndex].isReady;
      });
    }
  }

  void _broadcastLobbyUpdate() {
    final playersList = _players.map((p) => {
      'id': p.id,
      'name': p.name,
      'isReady': p.isReady,
    }).toList();

    ref.read(networkServiceProvider).send({
      'type': 'lobbyUpdate',
      'players': playersList,
    });
  }

  void _toggleReady() {
    if (_isSelfReady) return;

    final netService = ref.read(networkServiceProvider);
    final selfId = netService.assignedPlayerId;

    if (selfId != null) {
      netService.send({
        'type': 'playerReady',
        'playerId': selfId,
      });
      setState(() {
        _isSelfReady = true;
      });
    }
  }

  bool get _allReady {
    if (_players.isEmpty) return false;
    // Host is implicitly ready. Ensure all guests are ready.
    return _players.every((p) => p.isReady);
  }

  void _hostStartGame() {
    if (!_allReady) return;

    // Transition host to setup flow and notify all guests
    ref.read(networkServiceProvider).send({
      'type': 'startGame',
    });

    _startGameTransition();
  }

  void _startGameTransition() {
    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    gameStateNotifier.resetGame();

    final colors = [
      0xFF8B0000, // bloodRed
      0xFFC41E3A, // crimson
      0xFF4A0E17, // deep wine
      0xFF7D1C1C, // rust red
      0xFF5C0632, // dark magenta
      0xFF360000, // near black red
      0xFFB22222, // firebrick red
      0xFF800000, // maroon
    ];

    for (int i = 0; i < _players.length; i++) {
      final p = _players[i];
      gameStateNotifier.addPlayer(p.name, colors[i % colors.length]);
    }

    Navigator.of(context).pushNamed(MimicGame.modeSelectRoute);
  }

  void _showHostEndedDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: HorrorColors.deepSurface,
          title: Text(
            'ROOM CLOSED',
            style: GoogleFonts.creepster(color: HorrorColors.crimson),
          ),
          content: Text(
            'Host ended the room. Returning to main menu.',
            style: GoogleFonts.inter(color: HorrorColors.fogWhite),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss dialog
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Text(
                'OK',
                style: GoogleFonts.creepster(color: HorrorColors.crimson, fontSize: 18),
              ),
            ),
          ],
        );
      },
    );
  }

  void _leaveRoom() {
    ref.read(networkServiceProvider).disconnect();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _leaveRoom();
      },
      child: Scaffold(
        backgroundColor: HorrorColors.voidBlack,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.crimson),
            onPressed: _leaveRoom,
          ),
          title: HeartbeatPulse(
            child: Text(
              'THE GATHERING',
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 26,
                letterSpacing: 2.0,
              ),
            ),
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HorrorColors.darkRedTint,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: HorrorColors.crimson, width: 1),
                  ),
                  child: Text(
                    '${_players.length} / 8 PLAYERS',
                    style: GoogleFonts.shareTechMono(
                      color: HorrorColors.fogWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: StaticOverlay(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Player List
                Expanded(
                  child: AnimatedList(
                    key: _listKey,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    initialItemCount: _players.length,
                    itemBuilder: (context, index, animation) {
                      return _buildPlayerCard(_players[index], animation, index);
                    },
                  ),
                ),

                // Bottom Interface controls
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      if (widget.isHost) ...[
                        // Host Controls
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _allReady ? _hostStartGame : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HorrorColors.crimson,
                              foregroundColor: HorrorColors.fogWhite,
                              disabledBackgroundColor: HorrorColors.cardSurface,
                              disabledForegroundColor: HorrorColors.ashGray,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: _allReady ? HorrorColors.bloodRed : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: Text(
                              'START GAME',
                              style: GoogleFonts.creepster(
                                fontSize: 20,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Room code watermark display at bottom
                        Text(
                          'ROOM CODE: ${ref.read(networkServiceProvider).hostIp != null ? _encodeHostIp(ref.read(networkServiceProvider).hostIp!) : "------"}',
                          style: GoogleFonts.shareTechMono(
                            color: HorrorColors.ashGray,
                            fontSize: 12,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ] else ...[
                        // Guest Controls
                        if (!_isSelfReady)
                          SpookyPressableCard(
                            onTap: _toggleReady,
                            child: Container(
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                color: HorrorColors.crimson,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: HorrorColors.bloodRed, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  'I\'M READY',
                                  style: GoogleFonts.creepster(
                                    color: HorrorColors.fogWhite,
                                    fontSize: 20,
                                    letterSpacing: 2.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (_allReady)
                          // Shimmer StaticOverlay look when everyone is ready
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: HorrorColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: HorrorColors.crimson, width: 1.0),
                            ),
                            child: Center(
                              child: FlickerWidget(
                                child: Text(
                                  'Waiting for host to start…',
                                  style: GoogleFonts.inter(
                                    color: HorrorColors.crimson,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              color: HorrorColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: HorrorColors.darkRedTint, width: 1.0),
                            ),
                            child: Center(
                              child: Text(
                                'Waiting for other players…',
                                style: GoogleFonts.inter(
                                  color: HorrorColors.ashGray,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(LobbyPlayer player, Animation<double> animation, int index) {
    final slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    final List<IconData> horrorIcons = [
      Icons.sentiment_very_dissatisfied,
      Icons.visibility,
      Icons.blur_on,
    ];
    final icon = horrorIcons[index % horrorIcons.length];

    return SlideTransition(
      position: slideAnimation,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: HorrorColors.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: player.isReady ? HorrorColors.crimson : HorrorColors.darkRedTint,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: HorrorColors.crimson, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  player.name,
                  style: GoogleFonts.inter(
                    color: HorrorColors.fogWhite,
                    fontSize: 16,
                    fontWeight: player.isReady ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (player.isReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HorrorColors.darkRedTint,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: HorrorColors.crimson, width: 1),
                  ),
                  child: Text(
                    'READY',
                    style: GoogleFonts.creepster(
                      color: HorrorColors.crimson,
                      fontSize: 12,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _encodeHostIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return '000000';
    try {
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
    } catch (_) {
      return '000000';
    }
  }
}

// Extension extension on Map.entries
extension EntriesMap<K, V> on Map<K, V> {
  Iterable<MapEntry<K, V>> entries() => this.entries;
}

class SpookyPressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  const SpookyPressableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<SpookyPressableCard> createState() => _SpookyPressableCardState();
}

class _SpookyPressableCardState extends State<SpookyPressableCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => widget.enabled ? _controller.forward() : null,
      onTapUp: (_) => widget.enabled ? _controller.reverse() : null,
      onTapCancel: () => widget.enabled ? _controller.reverse() : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
