// pubspec: mobile_scanner: ^5.2.3
// lib/multiplayer/screens/join_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/game/game.dart';

/// Log helper
void _log(String message) => debugPrint('[JoinScreen] $message');

enum ConnectionStatus {
  idle,
  connecting,
  connected,
  failed,
}

class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  ConnectionStatus _status = ConnectionStatus.idle;
  String? _errorMessage;

  StreamSubscription<Map<String, dynamic>>? _welcomeSubscription;

  @override
  void dispose() {
    _welcomeSubscription?.cancel();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Decodes a 6-character Base62 room code back into a 32-bit IPv4 address string and port.
  Map<String, dynamic>? _decodeRoomCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.length != 6) return null;

    const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    int val = 0;

    for (int i = 0; i < cleanCode.length; i++) {
      final char = cleanCode[i];
      final index = chars.indexOf(char);
      if (index == -1) return null; // Invalid character
      val = val * 62 + index;
    }

    // Deconstruct back to 4 IP octets
    final octet4 = val & 0xFF;
    final octet3 = (val >> 8) & 0xFF;
    final octet2 = (val >> 16) & 0xFF;
    final octet1 = (val >> 24) & 0xFF;

    return {
      'ip': '$octet1.$octet2.$octet3.$octet4',
      'port': 4567, // Default port
    };
  }

  /// Encodes an IP address to a room code for QR scanned autoconnect synchronization.
  String _encodeRoomCode(String ip, int port) {
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

  void _onConnectPressed() {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _status = ConnectionStatus.failed;
        _errorMessage = 'Code must be exactly 6 characters';
      });
      return;
    }

    final connectionData = _decodeRoomCode(code);
    if (connectionData == null || connectionData['ip'] == '0.0.0.0') {
      setState(() {
        _status = ConnectionStatus.failed;
        _errorMessage = 'Failed — check code';
      });
      return;
    }

    _connectToHost(connectionData['ip'] as String, connectionData['port'] as int);
  }

  Future<void> _connectToHost(String ip, int port) async {
    setState(() {
      _status = ConnectionStatus.connecting;
      _errorMessage = null;
    });

    final netService = ref.read(networkServiceProvider);

    try {
      await netService.joinAsGuest(ip, port);

      if (!netService.isConnected) {
        setState(() {
          _status = ConnectionStatus.failed;
          _errorMessage = 'Failed — check code';
        });
        return;
      }

      // Listen for the welcome packet from the host
      _welcomeSubscription?.cancel();
      _welcomeSubscription = netService.messageStream.listen((message) {
        if (message['type'] == 'welcome') {
          setState(() {
            _status = ConnectionStatus.connected;
          });
          _welcomeSubscription?.cancel();
        }
      });

      // 5-second timeout for the welcome packet receipt
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _status == ConnectionStatus.connecting) {
          _welcomeSubscription?.cancel();
          netService.disconnect();
          setState(() {
            _status = ConnectionStatus.failed;
            _errorMessage = 'Failed — connection timeout';
          });
        }
      });

    } catch (e) {
      _log('Connection exception: $e');
      setState(() {
        _status = ConnectionStatus.failed;
        _errorMessage = 'Failed — check code';
      });
    }
  }

  void _startQrScan() {
    showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        return Dialog(
          backgroundColor: HorrorColors.deepSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: HorrorColors.crimson, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  'SCAN QR CODE',
                  style: GoogleFonts.creepster(color: HorrorColors.crimson, fontSize: 20),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: HorrorColors.ashGray),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Container(
                width: 250,
                height: 250,
                margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HorrorColors.darkRedTint, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final String? rawValue = barcode.rawValue;
                      if (rawValue != null && rawValue.isNotEmpty) {
                        Navigator.of(context).pop(rawValue);
                        break;
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((scannedValue) {
      if (scannedValue != null) {
        _onQrScanned(scannedValue);
      }
    });
  }

  void _onQrScanned(String value) {
    final parts = value.trim().split(':');
    if (parts.length == 2) {
      final ip = parts[0];
      final port = int.tryParse(parts[1]) ?? 4567;

      final roomCode = _encodeRoomCode(ip, port);
      setState(() {
        _codeController.text = roomCode;
      });

      _connectToHost(ip, port);
    } else {
      setState(() {
        _status = ConnectionStatus.failed;
        _errorMessage = 'Failed — check code';
      });
    }
  }

  void _onJoinLobbyPressed() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: HorrorColors.bloodRed,
          content: Text(
            'Codename is required',
            style: GoogleFonts.inter(color: HorrorColors.fogWhite),
          ),
        ),
      );
      return;
    }

    // Send introduction packet
    ref.read(networkServiceProvider).send({
      'type': 'playerJoined',
      'name': name,
    });

    // Navigate to wait room
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const LobbyScreen(),
      ),
    );
  }

  void _onBackPress() {
    ref.read(networkServiceProvider).disconnect();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
            'JOIN LOBBY',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 26,
              letterSpacing: 2.0,
            ),
          ),
        ),
        body: StaticOverlay(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'JOIN THE HUNT',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.creepster(
                      color: HorrorColors.crimson,
                      fontSize: 28,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter a 6-character room code to join or scan host\'s QR code.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: HorrorColors.ashGray,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Room Code Input Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codeController,
                          style: GoogleFonts.shareTechMono(
                            color: HorrorColors.fogWhite,
                            fontSize: 22,
                            letterSpacing: 4.0,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLength: 6,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            UpperCaseTextFormatter(),
                          ],
                          decoration: InputDecoration(
                            hintText: 'A1B2C3',
                            counterText: '',
                            hintStyle: GoogleFonts.shareTechMono(color: HorrorColors.ashGray),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _status == ConnectionStatus.connecting ? null : _onConnectPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HorrorColors.crimson,
                            foregroundColor: HorrorColors.fogWhite,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'CONNECT',
                            style: GoogleFonts.creepster(
                              fontSize: 16,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Status Area
                  _buildStatusArea(),

                  const SizedBox(height: 8),

                  // Divider OR
                  Row(
                    children: [
                      const Expanded(child: Divider(color: HorrorColors.darkRedTint, thickness: 1.5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: GoogleFonts.creepster(
                            color: HorrorColors.ashGray,
                            fontSize: 16,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: HorrorColors.darkRedTint, thickness: 1.5)),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // SCAN QR CODE Button
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _status == ConnectionStatus.connecting ? null : _startQrScan,
                      icon: const Icon(Icons.qr_code_scanner, color: HorrorColors.crimson),
                      label: Text(
                        'SCAN QR CODE',
                        style: GoogleFonts.creepster(
                          color: HorrorColors.crimson,
                          fontSize: 18,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: HorrorColors.crimson, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                  // Player Name Input (shown on connection success)
                  if (_status == ConnectionStatus.connected) ...[
                    const SizedBox(height: 48),
                    Text(
                      'YOUR CODENAME',
                      style: GoogleFonts.creepster(
                        color: HorrorColors.fogWhite,
                        fontSize: 16,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: GoogleFonts.inter(color: HorrorColors.fogWhite),
                      cursorColor: HorrorColors.crimson,
                      decoration: InputDecoration(
                        hintText: 'Enter Codename',
                        hintStyle: GoogleFonts.inter(color: HorrorColors.ashGray),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _onJoinLobbyPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HorrorColors.crimson,
                          foregroundColor: HorrorColors.fogWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'JOIN LOBBY',
                          style: GoogleFonts.creepster(
                            fontSize: 18,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusArea() {
    switch (_status) {
      case ConnectionStatus.idle:
        return const SizedBox.shrink();
      case ConnectionStatus.connecting:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: HorrorColors.crimson, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text(
                'Connecting…',
                style: TextStyle(color: HorrorColors.fogWhite, fontSize: 14),
              ),
            ],
          ),
        );
      case ConnectionStatus.connected:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
              SizedBox(width: 12),
              Text(
                'Connected!',
                style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      case ConnectionStatus.failed:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: HorrorColors.crimson, size: 22),
              const SizedBox(width: 12),
              Text(
                _errorMessage ?? 'Failed — check code',
                style: const TextStyle(color: HorrorColors.crimson, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
    }
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  List<Map<String, dynamic>> _lobbyPlayers = [];

  @override
  void initState() {
    super.initState();
    _subscribeToLobbyUpdates();
  }

  void _subscribeToLobbyUpdates() {
    _messageSubscription = ref.read(networkServiceProvider).messageStream.listen(
      (message) {
        if (!mounted) return;
        final type = message['type'];
        if (type == 'lobbyUpdate') {
          final List<dynamic> players = message['players'] as List<dynamic>;
          setState(() {
            _lobbyPlayers = players.cast<Map<String, dynamic>>();
          });
        } else if (type == 'gameStart') {
          // Navigate to the word reveal screen
          Navigator.of(context).pushNamed(MimicGame.wordRevealRoute);
        } else if (type == 'disconnected') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: HorrorColors.bloodRed,
              content: Text(
                'Disconnected from host.',
                style: GoogleFonts.inter(color: HorrorColors.fogWhite),
              ),
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      onError: (Object error) {
        _log('Lobby message error: $error');
      },
    );
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _leaveLobby() {
    ref.read(networkServiceProvider).disconnect();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _leaveLobby();
      },
      child: Scaffold(
        backgroundColor: HorrorColors.voidBlack,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: HorrorColors.crimson),
            onPressed: _leaveLobby,
          ),
          title: Text(
            'WAITING ROOM',
            style: GoogleFonts.creepster(
              color: HorrorColors.crimson,
              fontSize: 26,
              letterSpacing: 2.0,
            ),
          ),
        ),
        body: StaticOverlay(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlickerWidget(
                    child: Text(
                      'PREPARING THE TRIAL...',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.creepster(
                        color: HorrorColors.crimson,
                        fontSize: 24,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for the host to commence...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: HorrorColors.ashGray,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Victims in Lobby Header
                  Row(
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
                        '${_lobbyPlayers.length} / 8',
                        style: GoogleFonts.shareTechMono(
                          color: HorrorColors.crimson,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Player List
                  Expanded(
                    child: ListView.builder(
                      itemCount: _lobbyPlayers.length,
                      itemBuilder: (context, index) {
                        final player = _lobbyPlayers[index];
                        final id = player['id'] as String;
                        final name = player['name'] as String;
                        final isHost = id == 'host';
                        final isSelf = id == ref.read(networkServiceProvider).assignedPlayerId;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: HorrorColors.cardSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isHost
                                    ? HorrorColors.crimson
                                    : (isSelf ? HorrorColors.fogWhite : HorrorColors.darkRedTint),
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
                                    '$name${isSelf ? " (You)" : ""}',
                                    style: GoogleFonts.inter(
                                      color: HorrorColors.fogWhite,
                                      fontSize: 16,
                                      fontWeight: (isHost || isSelf)
                                          ? FontWeight.bold
                                          : FontWeight.normal,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
