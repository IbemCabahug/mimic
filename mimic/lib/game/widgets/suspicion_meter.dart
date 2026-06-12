// lib/game/widgets/suspicion_meter.dart
import 'package:flutter/material.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class SuspicionMeter extends StatefulWidget {
  final double value; // range 0.0 to 1.0
  final double height;

  const SuspicionMeter({super.key, required this.value, this.height = 12.0});

  @override
  State<SuspicionMeter> createState() => _SuspicionMeterState();
}

class _SuspicionMeterState extends State<SuspicionMeter> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.value >= 0.75) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(SuspicionMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value >= 0.75 && oldWidget.value < 0.75) {
      _pulseController.repeat(reverse: true);
    } else if (widget.value < 0.75 && oldWidget.value >= 0.75) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _getMeterColor(double value) {
    if (value < 0.4) {
      // low = dim/desaturated red
      return const Color(0xFF8B4545); // Desaturated dim red
    } else if (value < 0.75) {
      // mid = orange-red
      return const Color(0xFFFF4500); // Orange-red
    } else {
      // high = bright crimson
      return HorrorColors.crimson;
    }
  }

  List<BoxShadow> _getGlow(double value) {
    if (value >= 0.75) {
      return [
        BoxShadow(
          color: HorrorColors.crimson.withValues(alpha: 0.6 * _pulseAnimation.value),
          blurRadius: 8.0 * _pulseAnimation.value,
          spreadRadius: 2.0 * _pulseAnimation.value,
        )
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final clampedValue = widget.value.clamp(0.0, 1.0);
    final isMax = clampedValue >= 0.99;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: clampedValue),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, animValue, child) {
            final currentColor = _getMeterColor(animValue);
            final currentGlow = _getGlow(animValue);

            return Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.height / 2),
                    child: Container(
                      height: widget.height,
                      decoration: BoxDecoration(
                        color: HorrorColors.voidBlack,
                        border: Border.all(
                          color: HorrorColors.darkRedTint,
                          width: 1,
                        ),
                        boxShadow: currentGlow.isEmpty
                            ? []
                            : [
                                BoxShadow(
                                  color: currentGlow.first.color,
                                  blurRadius: currentGlow.first.blurRadius,
                                  spreadRadius: currentGlow.first.spreadRadius,
                                )
                              ],
                      ),
                      child: Stack(
                        children: [
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: animValue,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(widget.height / 2),
                                gradient: LinearGradient(
                                  colors: [
                                    currentColor.withValues(alpha: 0.6),
                                    currentColor,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isMax ? Icons.dangerous : Icons.dangerous_outlined,
                  color: isMax ? HorrorColors.crimson : HorrorColors.ashGray,
                  size: widget.height + 4,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
