// lib/multiplayer/screens/host_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/game/game.dart';

/// Log helper
void _log(String message) => debugPrint('[HostScreen] $message');

class HostScreen extends ConsumerStatefulWidget {
  final String hostName;

  const HostScreen({
    super.key,
    this.hostName = 'Host',
  });

  @override
  ConsumerState<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends ConsumerState<HostScreen> {
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  final Map<String, String> _playerNames = {};

  @override
  void initState() {
    super.initState();
    // Add host as the first player
    _playerNames['host'] = widget.hostName.trim().isEmpty ? 'Host' : widget.hostName;

    // Start the server on entering the screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startHosting();
    });
  }

  Future<void> _startHosting() async {
    final netService = ref.read(networkServiceProvider);
    await netService.startAsHost();
    
    if (netService.isConnected) {
      _subscribeToNetworkMessages();
      _log('Hosting started successfully.');
    } else {
      _log('Failed to start hosting.');
    }
  }

  void _subscribeToNetworkMessages() {
    _messageSubscription = ref.read(networkServiceProvider).messageStream.listen(
      (message) {
        final type = message['type'];
        final senderId = message['senderId'];

        if (type == 'join' || type == 'playerJoined') {
          final name = message['name'] as String? ?? 'Guest';
          setState(() {
            _playerNames[senderId] = name;
          });
          _broadcastLobbyUpdate();
        } else if (type == 'playerLeft') {
          final playerId = message['playerId'] as String?;
          if (playerId != null) {
            setState(() {
              _playerNames.remove(playerId);
            });
            _broadcastLobbyUpdate();
          }
        }
      },
      onError: (Object error) {
        _log('Error in network message stream: $error');
      },
    );
  }

  void _broadcastLobbyUpdate() {
    // Compile players roster to share with all guests
    final playersList = _playerNames.entries.map((e) => {
      'id': e.key,
      'name': e.value,
    }).toList();

    ref.read(networkServiceProvider).send({
      'type': 'lobbyUpdate',
      'players': playersList,
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  /// Encodes a 32-bit IPv4 address into a 6-character Base62 room code.
  String _encodeRoomCode(String ip, int port) {
    final parts = ip.split('.');
    if (parts.length != 4) return '000000';

    try {
      final ipInt = (int.parse(parts[0]) << 24) |
                    (int.parse(parts[1]) << 16) |
                    (int.parse(parts[2]) << 8) |
                    int.parse(parts[3]);

      // Handle sign-extension by converting to an unsigned 64-bit value in double or 64-bit int
      int unsignedIp = ipInt & 0xFFFFFFFF;

      const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final buffer = StringBuffer();
      int temp = unsignedIp;

      while (temp > 0) {
        buffer.write(chars[temp % 62]);
        temp = temp ~/ 62;
      }

      final result = buffer.toString().split('').reversed.join();
      return result.padLeft(6, '0');
    } catch (e) {
      _log('Error encoding room code: $e');
      return '000000';
    }
  }

  void _onBackPress() {
    ref.read(networkServiceProvider).disconnect();
    Navigator.of(context).pop();
  }

  void _startGame() {
    if (_playerNames.length < 2) return;

    final gameStateNotifier = ref.read(gameStateProvider.notifier);
    gameStateNotifier.resetGame();

    // Roster setup colors matching Horror Theme
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

    int index = 0;
    _playerNames.forEach((playerId, name) {
      final color = colors[index % colors.length];
      gameStateNotifier.addPlayer(name, color);
      index++;
    });

    // Notify clients that the game is starting
    ref.read(networkServiceProvider).send({
      'type': 'gameStart',
    });

    Navigator.of(context).pushNamed(MimicGame.packSelectRoute);
  }

  @override
  Widget build(BuildContext context) {
    final netService = ref.watch(networkServiceProvider);
    final isConnected = netService.isConnected;
    final hostIp = netService.hostIp;

    // Generate room code and QR string
    final roomCode = (isConnected && hostIp != null && hostIp != '0.0.0.0')
        ? _encodeRoomCode(hostIp, netService.port)
        : 'LOBBY';

    final qrData = (isConnected && hostIp != null)
        ? '$hostIp:${netService.port}'
        : '0.0.0.0:${netService.port}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackPress();
      },
      child: Scaffold(
        backgroundColor: HorrorColors.voidBlack,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.crimson),
            onPressed: _onBackPress,
          ),
          title: Text(
            'HOST LOBBY',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 26,
              letterSpacing: 2.0,
            ),
          ),
        ),
        body: StaticOverlay(
          child: SafeArea(
            child: isConnected
                ? Column(
                    children: [
                      // WAITING FOR PLAYERS flickering title
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: FlickerWidget(
                          child: Text(
                            'WAITING FOR PLAYERS...',
                            style: GoogleFonts.creepster(
                              color: HorrorColors.crimson,
                              fontSize: 22,
                              letterSpacing: 3.0,
                              shadows: [
                                Shadow(
                                  color: HorrorColors.crimson.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Monospace Room Code Display Box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: HorrorColors.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: HorrorColors.darkRedTint, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: HorrorColors.crimson.withValues(alpha: 0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ROOM CODE',
                                    style: GoogleFonts.inter(
                                      color: HorrorColors.ashGray,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    roomCode,
                                    style: GoogleFonts.shareTechMono(
                                      color: HorrorColors.fogWhite,
                                      fontSize: 32,
                                      letterSpacing: 6.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: HorrorColors.crimson),
                                tooltip: 'Copy Room Code',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: roomCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: HorrorColors.bloodRed,
                                      content: Text(
                                        'Room code copied to clipboard!',
                                        style: GoogleFonts.inter(color: HorrorColors.fogWhite),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // QR Code Container (White card for high scanner contrast)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: HorrorColors.crimson, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: HorrorColors.crimson.withValues(alpha: 0.15),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            size: 160,
                            gapless: false,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Share this code with your players',
                        style: GoogleFonts.inter(
                          color: HorrorColors.ashGray,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Victims List header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'VICTIMS IN LOBBY',
                              style: GoogleFonts.creepster(
                                color: HorrorColors.fogWhite,
                                fontSize: 18,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              '${_playerNames.length} / 8',
                              style: GoogleFonts.shareTechMono(
                                color: HorrorColors.crimson,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Players list View
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _playerNames.length,
                          itemBuilder: (context, index) {
                            final playerId = _playerNames.keys.elementAt(index);
                            final playerName = _playerNames[playerId]!;
                            final isHost = playerId == 'host';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: HorrorColors.cardSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isHost ? HorrorColors.crimson : HorrorColors.darkRedTint,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isHost ? HorrorColors.crimson : HorrorColors.bloodRed,
                                      child: Text(
                                        (index + 1).toString(),
                                        style: GoogleFonts.creepster(
                                          color: HorrorColors.fogWhite,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        playerName,
                                        style: GoogleFonts.inter(
                                          color: HorrorColors.fogWhite,
                                          fontSize: 16,
                                          fontWeight: isHost ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isHost)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: HorrorColors.darkRedTint,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: HorrorColors.crimson, width: 0.8),
                                        ),
                                        child: Text(
                                          'HOST',
                                          style: GoogleFonts.inter(
                                            color: HorrorColors.crimson,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Bottom start button
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _playerNames.length >= 2 ? _startGame : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HorrorColors.crimson,
                              foregroundColor: HorrorColors.fogWhite,
                              disabledBackgroundColor: HorrorColors.cardSurface,
                              disabledForegroundColor: HorrorColors.ashGray,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: _playerNames.length >= 2
                                      ? HorrorColors.bloodRed
                                      : Colors.transparent,
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
                      ),
                    ],
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: HorrorColors.crimson),
                        SizedBox(height: 20),
                        Text(
                          'Starting server...',
                          style: TextStyle(
                            color: HorrorColors.fogWhite,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
