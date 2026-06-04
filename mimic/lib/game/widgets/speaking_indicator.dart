// lib/game/widgets/speaking_indicator.dart
//
// Pulsing red dot indicator shown next to a player's name
// when they are actively speaking via push-to-talk.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class SpeakingIndicator extends StatefulWidget {
  /// Whether the indicator is currently active (player is speaking).
  final bool isActive;

  /// Optional player name to display alongside the indicator.
  final String? playerName;

  /// Size of the dot.
  final double dotSize;

  const SpeakingIndicator({
    super.key,
    required this.isActive,
    this.playerName,
    this.dotSize = 10.0,
  });

  @override
  State<SpeakingIndicator> createState() => _SpeakingIndicatorState();
}

class _SpeakingIndicatorState extends State<SpeakingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    if (widget.isActive) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(SpeakingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pulsing dot with expanding ring
        SizedBox(
          width: widget.dotSize * 2.5,
          height: widget.dotSize * 2.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ring
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    width: widget.dotSize * _pulseAnimation.value,
                    height: widget.dotSize * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HorrorColors.crimson
                            .withValues(alpha: _opacityAnimation.value),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
              // Solid dot
              Container(
                width: widget.dotSize,
                height: widget.dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HorrorColors.crimson,
                  boxShadow: [
                    BoxShadow(
                      color: HorrorColors.crimson.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Optional player name
        if (widget.playerName != null) ...[
          const SizedBox(width: 6),
          Text(
            widget.playerName!,
            style: GoogleFonts.inter(
              color: HorrorColors.crimson,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// A compact version of the speaking indicator for use in player lists.
/// Shows just the red dot next to the player's row.
class CompactSpeakingIndicator extends StatefulWidget {
  final bool isActive;

  const CompactSpeakingIndicator({
    super.key,
    required this.isActive,
  });

  @override
  State<CompactSpeakingIndicator> createState() =>
      _CompactSpeakingIndicatorState();
}

class _CompactSpeakingIndicatorState extends State<CompactSpeakingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _blinkAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CompactSpeakingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _blinkController.stop();
      _blinkController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox(width: 8, height: 8);

    return AnimatedBuilder(
      animation: _blinkAnimation,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HorrorColors.crimson.withValues(alpha: _blinkAnimation.value),
            boxShadow: [
              BoxShadow(
                color: HorrorColors.crimson
                    .withValues(alpha: _blinkAnimation.value * 0.5),
                blurRadius: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}
