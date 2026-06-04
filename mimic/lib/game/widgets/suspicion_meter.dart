// lib/game/widgets/suspicion_meter.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';

class SuspicionMeter extends StatelessWidget {
  final double value; // range 0.0 to 1.0 (representing 0% to 100%)
  final double height;

  const SuspicionMeter({super.key, required this.value, this.height = 20.0});

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: clampedValue),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, child) {
        final isMax = animValue >= 0.99;

        return Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: HorrorColors.deepSurface,
                    border: Border.all(
                      color: HorrorColors.darkRedTint,
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Blood-red horizontal progress bar
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: animValue,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                HorrorColors.bloodRed,
                                HorrorColors.crimson,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Text overlay showing the percentage
                      Center(
                        child: Text(
                          '${(animValue * 100).toInt()}% SUSPICIOUS',
                          style: GoogleFonts.creepster(
                            color: HorrorColors.fogWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                offset: const Offset(1, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // The skull icon that changes state and glows red at 100%
            Icon(
              isMax ? Icons.dangerous : Icons.dangerous_outlined,
              color: isMax ? HorrorColors.crimson : HorrorColors.ashGray,
              size: height + 4,
            ),
          ],
        );
      },
    );
  }
}
