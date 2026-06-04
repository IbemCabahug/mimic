// lib/multiplayer/screens/rejoin_screen.dart
//
// Reconnects a guest device to a host session mid-game after a disconnection.
// Decodes Base62 room codes, communicates with the host to verify and fetch
// role/word/gameState assignments, and auto-restores to the correct game phase.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/game/state/game_state.dart';
import 'package:mimic/multiplayer/network/network_service.dart';
import 'package:mimic/multiplayer/state/game_state_sync_notifier.dart';
import 'package:mimic/multiplayer/game_sync.dart';

enum RejoinStatus { attempting, success, failed, hostGone }

class RejoinScreen extends ConsumerStatefulWidget {
  final String lastRoomCode;
  final String lastPlayerName;
  final String lastPlayerId;

  const RejoinScreen({
    super.key,
    required this.lastRoomCode,
    required this.lastPlayerName,
    required this.lastPlayerId,
  });

  @override
  ConsumerState<RejoinScreen> createState() => _RejoinScreenState();
}

class _RejoinScreenState extends ConsumerState<RejoinScreen>
    with TickerProviderStateMixin {
  RejoinStatus _status = RejoinStatus.attempting;
  int _attemptCount = 0;
  String? _failReason;

  StreamSubscription<Map<String, dynamic>>? _messageSub;
  Timer? _timeoutTimer;

  // ─── Pulsing opacity animation for loading ──────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Automatically trigger rejoin attempt on boot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRejoinFlow();
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Rejoin Flow ───────────────────────────────────────────────────

  Future<void> _startRejoinFlow() async {
    setState(() {
      _status = RejoinStatus.attempting;
      _attemptCount = 0;
      _failReason = null;
    });

    _attemptReconnect();
  }

  Future<void> _attemptReconnect() async {
    if (_attemptCount >= 3) {
      setState(() {
        _status = RejoinStatus.failed;
        _failReason = 'Reconnection timed out after 3 attempts.';
      });
      return;
    }

    setState(() {
      _attemptCount++;
    });

    final decoded = _decodeRoomCode(widget.lastRoomCode);
    if (decoded == null) {
      setState(() {
        _status = RejoinStatus.failed;
        _failReason = 'Invalid room code format.';
      });
      return;
    }

    final String ip = decoded['ip'] as String;
    final int port = decoded['port'] as int;
    final netService = ref.read(networkServiceProvider);

    try {
      // 1. Join network server as guest
      await netService.joinAsGuest(ip, port);

      if (!netService.isConnected) {
        // Wait 1.5 seconds and retry if host is unavailable
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        _attemptReconnect();
        return;
      }

      // 2. Setup subscription to listen for rejoin response
      _messageSub?.cancel();
      _messageSub = netService.messageStream.listen((message) {
        final type = message['type'] as String?;
        if (type == 'rejoinAccepted') {
          _handleRejoinAccepted(message);
        } else if (type == 'disconnected') {
          setState(() {
            _status = RejoinStatus.hostGone;
          });
        }
      });

      // 3. Send rejoin request message
      netService.send({
        'type': 'requestRejoin',
        'playerId': widget.lastPlayerId,
        'name': widget.lastPlayerName,
      });

      // 4. Start response timeout timer (3 seconds)
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 3), () {
        if (_status == RejoinStatus.attempting) {
          netService.disconnect();
          _attemptReconnect();
        }
      });

    } catch (e) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      _attemptReconnect();
    }
  }

  Future<void> _handleRejoinAccepted(Map<String, dynamic> message) async {
    _messageSub?.cancel();
    _timeoutTimer?.cancel();

    final role = message['role'] as String?;
    final word = message['word'] as String?;
    final newPlayerId = message['playerId'] as String?;
    final phase = message['phase'] as String? ?? 'discussion';
    final isMimic = role == 'mimic';

    // Update GameStateNotifier
    ref.read(gameStateProvider.notifier).updateGuestRoleAndWord(
          isMimic: isMimic,
          word: word ?? '',
          playerId: newPlayerId ?? '',
        );

    // Apply the remote GameState snapshot
    final gameStateData = message['gameState'] as Map<String, dynamic>?;
    if (gameStateData != null) {
      final deserialized = GameSync.deserializeState(gameStateData);
      if (deserialized != null) {
        ref.read(gameStateProvider.notifier).applyRemoteState(deserialized);
      }
    }

    // Persist new details for subsequent dropouts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_room_code', widget.lastRoomCode);
    if (newPlayerId != null) {
      await prefs.setString('last_player_id', newPlayerId);
      await prefs.setString('last_player_name', widget.lastPlayerName);
    }

    if (!mounted) return;

    setState(() {
      _status = RejoinStatus.success;
    });

    // Auto-navigate after 1 second flash
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      _routeToCorrectScreen(phase);
    });
  }

  void _routeToCorrectScreen(String phase) {
    if (phase == 'voting') {
      Navigator.of(context).pushReplacementNamed(MimicGame.votingRoute);
    } else if (phase == 'wordReveal') {
      Navigator.of(context).pushReplacementNamed(MimicGame.wordRevealRoute);
    } else {
      // Default to discussion
      Navigator.of(context).pushReplacementNamed(MimicGame.discussionRoute);
    }
  }

  void _leaveGame() {
    ref.read(networkServiceProvider).disconnect();
    _popToMenu();
  }

  void _popToMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).pushReplacementNamed(MimicGame.multiplayerRoute);
  }

  // ─── Room Code Decode ──────────────────────────────────────────────

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

    final octet4 = val & 0xFF;
    final octet3 = (val >> 8) & 0xFF;
    final octet2 = (val >> 16) & 0xFF;
    final octet1 = (val >> 24) & 0xFF;

    return {
      'ip': '$octet1.$octet2.$octet3.$octet4',
      'port': 4567,
    };
  }

  // ─── UI Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        opacity: 0.15,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case RejoinStatus.attempting:
        return _buildAttemptingStage();
      case RejoinStatus.success:
        return _buildSuccessStage();
      case RejoinStatus.failed:
        return _buildFailedStage();
      case RejoinStatus.hostGone:
        return _buildHostGoneStage();
    }
  }

  Widget _buildAttemptingStage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlickerWidget(
            child: Text(
              'RECONNECTING…',
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 44,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: HorrorColors.crimson.withValues(alpha: 0.5),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Attempt $_attemptCount of 3',
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 48),
          FadeTransition(
            opacity: _pulseAnimation,
            child: const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(HorrorColors.crimson),
              strokeWidth: 3.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlickerWidget(
            child: Text(
              'RECONNECTED',
              style: GoogleFonts.creepster(
                color: Colors.green,
                fontSize: 44,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: Colors.green.withValues(alpha: 0.5),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Restoring game phase…',
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedStage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlickerWidget(
            child: Text(
              'CONNECTION LOST',
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 40,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: HorrorColors.crimson.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _failReason ?? 'Unable to establish connection with host.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 48),
          _buildButton(
            label: 'TRY AGAIN',
            color: HorrorColors.crimson,
            onPressed: _startRejoinFlow,
          ),
          const SizedBox(height: 16),
          _buildButton(
            label: 'LEAVE GAME',
            color: HorrorColors.cardSurface,
            borderColor: HorrorColors.ashGray.withValues(alpha: 0.3),
            onPressed: _leaveGame,
          ),
        ],
      ),
    );
  }

  Widget _buildHostGoneStage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FlickerWidget(
            child: Text(
              'THE HOST HAS LEFT',
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                color: HorrorColors.crimson,
                fontSize: 40,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: HorrorColors.crimson.withValues(alpha: 0.6),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This room no longer exists.',
            style: GoogleFonts.inter(
              color: HorrorColors.ashGray,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 48),
          _buildButton(
            label: 'RETURN TO MENU',
            color: HorrorColors.crimson,
            onPressed: _popToMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required Color color,
    Color? borderColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: HorrorColors.fogWhite,
          side: borderColor != null ? BorderSide(color: borderColor, width: 1.5) : const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 4,
          shadowColor: color.withValues(alpha: 0.4),
        ),
        child: Text(
          label,
          style: GoogleFonts.creepster(
            fontSize: 20,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
