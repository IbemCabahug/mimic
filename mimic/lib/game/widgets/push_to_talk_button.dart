// lib/game/widgets/push_to_talk_button.dart
//
// Hold-to-speak button for push-to-talk voice communication.
// Shows a pulsing red indicator while actively speaking.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class PushToTalkButton extends StatefulWidget {
  /// Called when the user starts holding the button (begins speaking).
  final VoidCallback? onTalkStart;

  /// Called when the user releases the button (stops speaking).
  final VoidCallback? onTalkEnd;

  /// Whether the button is enabled (false during voting/reveal phases).
  final bool enabled;

  /// Whether the mic is currently active (for visual feedback).
  final bool isActive;

  const PushToTalkButton({
    super.key,
    this.onTalkStart,
    this.onTalkEnd,
    this.enabled = true,
    this.isActive = false,
  });

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startTalking() {
    if (!widget.enabled) return;
    setState(() => _isHolding = true);
    _pulseController.repeat(reverse: true);
    widget.onTalkStart?.call();
  }

  void _stopTalking() {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    _pulseController.stop();
    _pulseController.value = 0.0;
    widget.onTalkEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isActiveVisual = _isHolding || widget.isActive;

    return GestureDetector(
      onLongPressStart: (_) => _startTalking(),
      onLongPressEnd: (_) => _stopTalking(),
      onLongPressCancel: _stopTalking,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing ring (only when active)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isActiveVisual
                      ? [
                          BoxShadow(
                            color: HorrorColors.crimson
                                .withValues(alpha: 0.4 * _pulseAnimation.value),
                            blurRadius: 20 * _pulseAnimation.value,
                            spreadRadius: 4 * _pulseAnimation.value,
                          ),
                        ]
                      : null,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActiveVisual
                        ? HorrorColors.crimson
                        : widget.enabled
                            ? HorrorColors.cardSurface
                            : HorrorColors.cardSurface
                                .withValues(alpha: 0.5),
                    border: Border.all(
                      color: isActiveVisual
                          ? HorrorColors.bloodRed
                          : widget.enabled
                              ? HorrorColors.crimson.withValues(alpha: 0.5)
                              : HorrorColors.ashGray.withValues(alpha: 0.3),
                      width: isActiveVisual ? 3 : 2,
                    ),
                  ),
                  child: Icon(
                    isActiveVisual ? Icons.mic : Icons.mic_none,
                    size: 32,
                    color: isActiveVisual
                        ? HorrorColors.fogWhite
                        : widget.enabled
                            ? HorrorColors.crimson
                            : HorrorColors.ashGray.withValues(alpha: 0.5),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Label
          Text(
            isActiveVisual
                ? 'SPEAKING...'
                : widget.enabled
                    ? 'HOLD TO TALK'
                    : 'MUTED',
            style: GoogleFonts.inter(
              color: isActiveVisual
                  ? HorrorColors.crimson
                  : HorrorColors.ashGray.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
