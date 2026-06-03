// lib/core/animations/glitch_transition.dart
import 'dart:math';
import 'package:flutter/material.dart';

class GlitchTransition {
  /// Triggers a 300ms glitch transition to a destination screen.
  static void trigger(BuildContext context, Widget destination) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        opaque: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return GlitchTransitionWidget(
            animation: animation,
            child: child,
          );
        },
      ),
    );
  }
}

class GlitchTransitionWidget extends AnimatedWidget {
  final Widget child;

  const GlitchTransitionWidget({
    super.key,
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final t = animation.value;
    final random = Random((t * 100).floor());

    if (t < 0.7) {
      final progress = t / 0.7;
      
      // Generate 6 horizontal slices of the entering screen
      final slices = <Widget>[];
      const int numSlices = 6;
      for (int i = 0; i < numSlices; i++) {
        final top = i / numSlices;
        final bottom = (i + 1) / numSlices;
        
        // Random horizontal displacement
        final shift = (random.nextDouble() - 0.5) * 40.0;
        final rgbSplit = random.nextDouble() > 0.5;
        
        Widget slice = ClipRect(
          clipper: _SliceClipper(top: top, bottom: bottom),
          child: Transform.translate(
            offset: Offset(shift, 0),
            child: child,
          ),
        );
        
        if (rgbSplit) {
          slice = Stack(
            children: [
              slice,
              ClipRect(
                clipper: _SliceClipper(top: top, bottom: bottom),
                child: Transform.translate(
                  offset: Offset(shift - 6, 0),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.red.withValues(alpha: 0.4),
                      BlendMode.srcATop,
                    ),
                    child: child,
                  ),
                ),
              ),
              ClipRect(
                clipper: _SliceClipper(top: top, bottom: bottom),
                child: Transform.translate(
                  offset: Offset(shift + 6, 0),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.blue.withValues(alpha: 0.4),
                      BlendMode.srcATop,
                    ),
                    child: child,
                  ),
                ),
              ),
            ],
          );
        }
        slices.add(slice);
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          // Render the sliced and displaced destination screen
          ...slices,
          // Custom painter for scanlines and digital noise blocks
          CustomPaint(
            painter: _GlitchPainter(progress: progress, random: random),
          ),
          // Flash to white container
          Container(
            color: Colors.white.withValues(alpha: progress),
          ),
        ],
      );
    } else {
      final progress = (t - 0.7) / 0.3;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Fade from solid white to clean child
          Container(
            color: Colors.white.withValues(alpha: 1.0 - progress),
          ),
        ],
      );
    }
  }
}

class _SliceClipper extends CustomClipper<Rect> {
  final double top;
  final double bottom;

  _SliceClipper({required this.top, required this.bottom});

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, size.height * top, size.width, size.height * bottom);
  }

  @override
  bool shouldReclip(covariant _SliceClipper oldClipper) {
    return oldClipper.top != top || oldClipper.bottom != bottom;
  }
}

class _GlitchPainter extends CustomPainter {
  final double progress;
  final Random random;

  _GlitchPainter({required this.progress, required this.random});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    // Draw fine scanlines
    paint.color = Colors.black.withValues(alpha: 0.15);
    paint.strokeWidth = 1.0;
    const double scanlineSpacing = 5.0;
    for (double y = 0; y < size.height; y += scanlineSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw horizontal RGB color split bars
    final numBlocks = (6 * (1.0 - progress)).toInt() + 1;
    for (int i = 0; i < numBlocks; i++) {
      final w = random.nextDouble() * size.width * 0.5;
      final h = random.nextDouble() * 25 + 5;
      final x = random.nextDouble() * (size.width - w);
      final y = random.nextDouble() * (size.height - h);
      
      final colors = [
        Colors.red.withValues(alpha: 0.35),
        Colors.blue.withValues(alpha: 0.35),
        Colors.green.withValues(alpha: 0.25),
        Colors.white.withValues(alpha: 0.45),
      ];
      paint.color = colors[random.nextInt(colors.length)];
      paint.style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GlitchPainter oldDelegate) => true;
}
