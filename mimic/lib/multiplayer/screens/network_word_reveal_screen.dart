// lib/multiplayer/screens/network_word_reveal_screen.dart
//
// Multiplayer replacement for the pass-and-play WordRevealScreen.
// Each player sees their own role/word on their own device simultaneously
// via a "roleAssigned" network message from the host.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/game.dart';
import 'package:mimic/multiplayer/network/network_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NetworkWordRevealScreen
// ═══════════════════════════════════════════════════════════════════════════

class NetworkWordRevealScreen extends ConsumerStatefulWidget {
  const NetworkWordRevealScreen({super.key});

  @override
  ConsumerState<NetworkWordRevealScreen> createState() =>
      _NetworkWordRevealScreenState();
}

class _NetworkWordRevealScreenState
    extends ConsumerState<NetworkWordRevealScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ─── State ──────────────────────────────────────────────────────────
  String? _role; // "mimic" or "villager"
  String? _word; // the assigned word (null for Mimic)
  bool _revealed = false; // true after player taps to reveal
  bool _acknowledged = false; // true after player taps "I'M READY"

  StreamSubscription<Map<String, dynamic>>? _messageSub;

  // ─── Pulsing opacity animation for "Waiting for your role…" ────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ─── Lifecycle ─────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pulsing opacity: 0.3 → 1.0 → 0.3 (smooth sine-like curve)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Listen for "roleAssigned" messages from the host.
    final networkService = ref.read(networkServiceProvider);
    _messageSub = networkService.messageStream.listen(_handleMessage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Privacy guard ────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _revealed && !_acknowledged) {
      setState(() {
        _revealed = false;
      });
    }
  }

  // ─── Network message handler ──────────────────────────────────────
  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;

    final type = message['type'] as String?;
    if (type == 'roleAssigned') {
      setState(() {
        _role = message['role'] as String?;
        _word = message['word'] as String?;
      });
    }
  }

  // ─── User actions ─────────────────────────────────────────────────
  void _onTapReveal() {
    if (_role == null) return; // safety: shouldn't be tappable yet
    setState(() {
      _revealed = true;
    });
  }

  void _onAcknowledge() {
    if (_acknowledged) return;
    setState(() {
      _acknowledged = true;
    });

    // Send wordAck to host so it knows this player is ready.
    final networkService = ref.read(networkServiceProvider);
    networkService.send({'type': 'wordAck'});

    // Navigate to the discussion screen.
    Navigator.of(context).pushReplacementNamed(MimicGame.discussionRoute);
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: _buildStage(),
      ),
    );
  }

  Widget _buildStage() {
    if (_role == null) {
      return _buildWaitingStage();
    }
    if (!_revealed) {
      return _buildReadyToRevealStage();
    }
    return _buildRevealedStage();
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 1 — Waiting (before roleAssigned message arrives)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWaitingStage() {
    return Center(
      child: FadeTransition(
        opacity: _pulseAnimation,
        child: Text(
          'Waiting for your role…',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            color: HorrorColors.fogWhite,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 2 — Ready to reveal (roleAssigned received, not yet tapped)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildReadyToRevealStage() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTapReveal,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title
            Text(
              'YOUR ROLE IS READY',
              textAlign: TextAlign.center,
              style: GoogleFonts.creepster(
                fontSize: 36,
                color: HorrorColors.crimson,
                letterSpacing: 2.0,
                shadows: [
                  Shadow(
                    color: HorrorColors.crimson.withValues(alpha: 0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Subtext
            Text(
              'Cover your screen from other players.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: HorrorColors.ashGray,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 48),
            // Eye icon with heartbeat
            HeartbeatPulse(
              child: Icon(
                Icons.visibility_outlined,
                size: 64,
                color: HorrorColors.crimson.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            // Tap hint
            FadeTransition(
              opacity: _pulseAnimation,
              child: Text(
                'TAP ANYWHERE TO REVEAL',
                style: GoogleFonts.creepster(
                  fontSize: 16,
                  color: HorrorColors.ashGray,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STAGE 3 — Revealed (player has tapped to see their role/word)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRevealedStage() {
    final isMimic = _role == 'mimic';

    return GlitchTransition(
      duration: const Duration(milliseconds: 250),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Crimson pulsing background tint for Mimic
          if (isMimic) _buildMimicBackgroundPulse(),

          // Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isMimic) ..._buildMimicContent(),
                  if (!isMimic) ..._buildVillagerContent(),
                  const SizedBox(height: 56),
                  // "I'M READY" button
                  _buildReadyButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Crimson pulsing background overlay for the Mimic reveal.
  Widget _buildMimicBackgroundPulse() {
    return HeartbeatPulse(
      duration: const Duration(milliseconds: 2000),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              HorrorColors.crimson.withValues(alpha: 0.12),
              HorrorColors.bloodRed.withValues(alpha: 0.05),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }

  /// Content widgets for the Mimic role reveal.
  List<Widget> _buildMimicContent() {
    return [
      FlickerWidget(
        child: Text(
          'YOU ARE\nTHE MIMIC',
          textAlign: TextAlign.center,
          style: GoogleFonts.creepster(
            fontSize: 52,
            color: HorrorColors.crimson,
            letterSpacing: 3.0,
            height: 1.1,
            shadows: [
              Shadow(
                color: HorrorColors.crimson.withValues(alpha: 0.6),
                blurRadius: 25,
              ),
              Shadow(
                color: HorrorColors.bloodRed.withValues(alpha: 0.3),
                blurRadius: 50,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'Blend in. Trust no one.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 18,
          color: HorrorColors.ashGray,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.5,
        ),
      ),
    ];
  }

  /// Content widgets for the Villager role reveal.
  List<Widget> _buildVillagerContent() {
    return [
      Text(
        'YOUR WORD IS',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 16,
          color: HorrorColors.ashGray,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.0,
        ),
      ),
      const SizedBox(height: 20),
      FlickerWidget(
        child: Text(
          (_word ?? '???').toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.creepster(
            fontSize: 56,
            color: HorrorColors.fogWhite,
            letterSpacing: 3.0,
            shadows: [
              Shadow(
                color: HorrorColors.crimson.withValues(alpha: 0.5),
                blurRadius: 15,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Remember your word.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 14,
          color: HorrorColors.ashGray,
          fontWeight: FontWeight.w300,
          letterSpacing: 0.5,
        ),
      ),
    ];
  }

  /// The "I'M READY" button that acknowledges and navigates forward.
  Widget _buildReadyButton() {
    return SizedBox(
      width: 220,
      height: 56,
      child: ElevatedButton(
        onPressed: _acknowledged ? null : _onAcknowledge,
        style: ElevatedButton.styleFrom(
          backgroundColor: HorrorColors.crimson,
          foregroundColor: HorrorColors.fogWhite,
          disabledBackgroundColor: HorrorColors.cardSurface,
          disabledForegroundColor: HorrorColors.ashGray,
          side: const BorderSide(color: HorrorColors.bloodRed, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 6,
          shadowColor: HorrorColors.crimson.withValues(alpha: 0.4),
        ),
        child: Text(
          "I'M READY",
          style: GoogleFonts.creepster(
            fontSize: 22,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
