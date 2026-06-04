// lib/game/screens/home_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/core/animations/horror_animations.dart';
import 'package:mimic/game/game.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fogController;
  late List<FogWisp> _wisps;

  @override
  void initState() {
    super.initState();
    // Continuous animation driving the fog horizontal movement
    _fogController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();

    // Define 4 distinct, organic-looking fog wisps drifting at different speeds/depths
    _wisps = [
      FogWisp(
        yPercent: 0.20,
        speed: 0.04,
        amplitude: 20.0,
        frequency: 0.004,
        strokeWidth: 35.0,
        opacity: 0.12,
        phaseOffset: 0.0,
      ),
      FogWisp(
        yPercent: 0.40,
        speed: 0.06,
        amplitude: 30.0,
        frequency: 0.007,
        strokeWidth: 50.0,
        opacity: 0.08,
        phaseOffset: math.pi / 2,
      ),
      FogWisp(
        yPercent: 0.65,
        speed: 0.03,
        amplitude: 25.0,
        frequency: 0.005,
        strokeWidth: 40.0,
        opacity: 0.14,
        phaseOffset: math.pi,
      ),
      FogWisp(
        yPercent: 0.85,
        speed: 0.05,
        amplitude: 35.0,
        frequency: 0.006,
        strokeWidth: 55.0,
        opacity: 0.10,
        phaseOffset: math.pi * 1.5,
      ),
    ];
  }

  @override
  void dispose() {
    _fogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HorrorColors.voidBlack,
      body: StaticOverlay(
        child: GlitchTransition(
          duration: const Duration(milliseconds: 750),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Fog Wisps Painter Background
              AnimatedBuilder(
                animation: _fogController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: FogPainter(
                      wisps: _wisps,
                      animationValue: _fogController.value,
                    ),
                  );
                },
              ),

              // 2. Main Title and Navigation Buttons
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          // Heartbeat Pulse Animated Blood-Red Title
                          HeartbeatPulse(
                            child: Text(
                              'MIMIC',
                              style: GoogleFonts.creepster(
                                fontSize: 96,
                                color: HorrorColors.bloodRed,
                                letterSpacing: 8.0,
                                shadows: [
                                  Shadow(
                                    blurRadius: 25,
                                    color: HorrorColors.crimson.withValues(alpha: 0.6),
                                    offset: const Offset(0, 0),
                                  ),
                                  Shadow(
                                    blurRadius: 10,
                                    color: Colors.black.withValues(alpha: 0.8),
                                    offset: const Offset(2, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Tagline
                          Text(
                            'Someone among you is not what they seem.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: HorrorColors.ashGray,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 80),

                          // Stacked Buttons
                          _buildButton(
                            label: 'BEGIN',
                            onPressed: () {
                              Navigator.of(context).pushNamed(MimicGame.modeSelectRoute);
                            },
                            isPrimary: true,
                          ),
                          const SizedBox(height: 16),
                          _buildButton(
                            label: 'HOW TO PLAY',
                            onPressed: () => _showHowToPlayDialog(context),
                            isPrimary: false,
                            borderColor: HorrorColors.crimson,
                            textColor: HorrorColors.crimson,
                          ),
                          const SizedBox(height: 16),
                          _buildButton(
                            label: 'SETTINGS',
                            onPressed: () => _showSettingsDialog(context),
                            isPrimary: false,
                            borderColor: HorrorColors.ashGray,
                            textColor: HorrorColors.ashGray,
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Version watermark
              Positioned(
                bottom: 16,
                right: 16,
                child: Text(
                  'v1.0.0',
                  style: GoogleFonts.inter(
                    color: HorrorColors.ashGray.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
    Color? borderColor,
    Color? textColor,
  }) {
    final ButtonStyle style = isPrimary
        ? ElevatedButton.styleFrom(
            backgroundColor: HorrorColors.crimson,
            foregroundColor: HorrorColors.fogWhite,
            elevation: 8,
            shadowColor: HorrorColors.crimson.withValues(alpha: 0.5),
            minimumSize: const Size(220, 50),
            side: const BorderSide(color: HorrorColors.bloodRed, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: textColor ?? HorrorColors.crimson,
            side: BorderSide(color: borderColor ?? HorrorColors.crimson, width: 1.5),
            minimumSize: const Size(220, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );

    final Widget buttonChild = Text(
      label.toUpperCase(),
      style: GoogleFonts.creepster(
        fontSize: 20,
        letterSpacing: 2.0,
        fontWeight: FontWeight.bold,
      ),
    );

    return SizedBox(
      width: 220,
      height: 52,
      child: isPrimary
          ? ElevatedButton(onPressed: onPressed, style: style, child: buttonChild)
          : OutlinedButton(onPressed: onPressed, style: style, child: buttonChild),
    );
  }

  void _showHowToPlayDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'HOW TO PLAY',
            style: GoogleFonts.creepster(
              letterSpacing: 1.5,
              fontSize: 24,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRuleItem('1. THE ASSIGNMENT', 'Every player receives a secret word. One player gets a fake word—they are the MIMIC.'),
                const SizedBox(height: 16),
                _buildRuleItem('2. THE DECEPTION', 'Players describe their words in turns. The Mimic must listen closely, adapt, and blend in.'),
                const SizedBox(height: 16),
                _buildRuleItem('3. THE ACCUSATION', 'After discussion, all players vote on who they believe is the Mimic. Trust no one.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'UNDERSTOOD',
                style: GoogleFonts.creepster(
                  color: HorrorColors.crimson,
                  fontSize: 18,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRuleItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.creepster(
            color: HorrorColors.crimson,
            fontSize: 18,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: GoogleFonts.inter(
            color: HorrorColors.fogWhite,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'SETTINGS',
            style: GoogleFonts.creepster(
              letterSpacing: 1.5,
              fontSize: 24,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSettingSwitch('SOUND EFFECTS', true),
              const SizedBox(height: 12),
              _buildSettingSwitch('TENSION MUSIC', true),
              const SizedBox(height: 12),
              _buildSettingSwitch('HAPTIC FEEDBACK', true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'CLOSE',
                style: GoogleFonts.creepster(
                  color: HorrorColors.ashGray,
                  fontSize: 18,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingSwitch(String label, bool initialValue) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: HorrorColors.fogWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Switch(
              value: initialValue,
              activeColor: HorrorColors.crimson,
              activeTrackColor: HorrorColors.bloodRed.withValues(alpha: 0.5),
              inactiveThumbColor: HorrorColors.ashGray,
              inactiveTrackColor: HorrorColors.cardSurface,
              onChanged: (val) {
                setState(() {
                  initialValue = val;
                });
              },
            ),
          ],
        );
      },
    );
  }
}

class FogWisp {
  final double yPercent;
  final double speed;
  final double amplitude;
  final double frequency;
  final double strokeWidth;
  final double opacity;
  final double phaseOffset;

  FogWisp({
    required this.yPercent,
    required this.speed,
    required this.amplitude,
    required this.frequency,
    required this.strokeWidth,
    required this.opacity,
    required this.phaseOffset,
  });
}

class FogPainter extends CustomPainter {
  final List<FogWisp> wisps;
  final double animationValue;

  FogPainter({
    required this.wisps,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final wisp in wisps) {
      final double phase = (animationValue * math.pi * 2) + wisp.phaseOffset;
      final path = Path();
      final double startY = size.height * wisp.yPercent;

      // Draw horizontal wavy line with slow drift
      for (double x = -50; x <= size.width + 50; x += 15) {
        // Drift is simulated by shifting the x coordinate evaluation using the phase variable
        final double y = startY + math.sin((x * wisp.frequency) - (phase * wisp.speed * 10)) * wisp.amplitude;
        if (x == -50) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      final paint = Paint()
        ..color = HorrorColors.fogWhite.withValues(alpha: wisp.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = wisp.strokeWidth
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28.0); // Soft fog blur effect

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FogPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
