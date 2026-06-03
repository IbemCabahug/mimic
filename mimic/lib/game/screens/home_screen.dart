// lib/game/screens/home_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mimic/game/game.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late AnimationController _glowController;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _particles = List.generate(50, (_) => Particle.random());
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            color: const Color(0xFF7F77DD),
            onPressed: () {
              // TODO: Navigate to settings screen
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: ParticlePainter(
                  particles: _particles,
                  animationValue: _backgroundController.value,
                ),
              );
            },
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glow = _glowController.value;
                    return Text(
                      'MIMIC',
                      style: TextStyle(
                        fontSize: 48,
                        color: const Color(0xFF7F77DD),
                        shadows: [
                          Shadow(
                            blurRadius: 12 * glow,
                            color: const Color(0xFF7F77DD).withValues(alpha: 0.5 * glow),
                            offset: const Offset(0, 0),
                          ),
                          Shadow(
                            blurRadius: 20 * glow,
                            color: const Color(0xFF7F77DD).withValues(alpha: 0.3 * glow),
                            offset: const Offset(0, 0),
                          ),
                        ],
                        letterSpacing: 2.0,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(MimicGame.playerSetupRoute);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F77DD),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Play',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Particle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double directionX;
  final double directionY;
  final double opacity;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.directionX,
    required this.directionY,
    required this.opacity,
  });

  factory Particle.random() {
    return Particle(
      x: math.Random().nextDouble(),
      y: math.Random().nextDouble(),
      size: math.Random().nextDouble() * 3 + 1,
      speed: math.Random().nextDouble() * 0.5 + 0.2,
      directionX: (math.Random().nextDouble() - 0.5) * 2,
      directionY: -(math.Random().nextDouble() * 0.5 + 0.3),
      opacity: 0.15 + math.Random().nextDouble() * 0.15,
    );
  }

  Particle update(double animationValue, Size screenSize) {
    final deltaX = directionX * speed * animationValue * 0.01;
    final deltaY = directionY * speed * animationValue * 0.01;

    double newX = x + deltaX;
    double newY = y + deltaY;

    if (newX < 0) newX = 1 + (newX % 1);
    if (newX > 1) newX = newX % 1;
    if (newY < 0) newY = 1 + (newY % 1);
    if (newY > 1) newY = newY % 1;

    return Particle(
      x: newX,
      y: newY,
      size: size,
      speed: speed,
      directionX: directionX,
      directionY: directionY,
      opacity: opacity,
    );
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;

  ParticlePainter({
    required this.particles,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final updated = particle.update(animationValue, size);
      final position = Offset(
        updated.x * size.width,
        updated.y * size.height,
      );
      canvas.drawCircle(
        position,
        updated.size,
        Paint()
          ..color = Colors.white.withValues(alpha: updated.opacity)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter old) {
    return old.animationValue != animationValue;
  }
}
