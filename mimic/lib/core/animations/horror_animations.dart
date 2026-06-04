// lib/core/animations/horror_animations.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Custom Tween that generates a random opacity value between 0.85 and 1.0 on every tick.
/// Using a custom Tween + FadeTransition is significantly more performant than calling
/// setState() inside an AnimationController listener, as it avoids rebuilding the child widget tree.
class FlickerTween extends Tween<double> {
  final math.Random _random = math.Random();

  FlickerTween() : super(begin: 0.85, end: 1.0);

  @override
  double transform(double t) {
    // Generate a random value between 0.85 and 1.0 on each lookup
    return 0.85 + _random.nextDouble() * 0.15;
  }
}

/// A widget that wraps its child in a subtle random opacity flicker (0.85 to 1.0),
/// mimicking the look of an old CRT monitor or an unstable light source.
class FlickerWidget extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const FlickerWidget({super.key, required this.child, this.enabled = true});

  @override
  State<FlickerWidget> createState() => _FlickerWidgetState();
}

class _FlickerWidgetState extends State<FlickerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Continuous loop to drive flicker
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _animation = FlickerTween().animate(_controller);

    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(FlickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}

/// A widget that applies a scaling pulse effect (1.0 -> 1.04 -> 1.0) resembling a heartbeat,
/// designed to raise tension and focus on critical user interfaces or tense moments.
class HeartbeatPulse extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration duration;

  const HeartbeatPulse({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<HeartbeatPulse> createState() => _HeartbeatPulseState();
}

class _HeartbeatPulseState extends State<HeartbeatPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    // Creates a double-beat heartbeat cycle: peak, decay, peak, base, pause
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.04,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.04,
          end: 1.01,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.01,
          end: 1.04,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.04,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_controller);

    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(HeartbeatPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}

/// A screen or component transition widget that applies horizontal displacement offsets
/// combined with dramatic opacity drops to create a digital glitch/interference aesthetic.
class GlitchTransition extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final bool animateOnStart;

  const GlitchTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.animateOnStart = true,
  });

  /// Helper route builder that leverages this glitch style on navigation transitions.
  static Route<T> pageRoute<T>(
    Widget destination, {
    Duration duration = const Duration(milliseconds: 400),
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      opaque: true,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return GlitchTransition(
          duration: duration,
          animateOnStart: false,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, builderChild) {
              // Connect navigation animation value (0.0 -> 1.0) into the transition
              return _GlitchTransitionLayout(
                progress: animation.value,
                child: builderChild!,
              );
            },
          ),
        );
      },
    );
  }

  @override
  State<GlitchTransition> createState() => _GlitchTransitionState();
}

class _GlitchTransitionState extends State<GlitchTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    if (widget.animateOnStart) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animateOnStart) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return _GlitchTransitionLayout(
          progress: _controller.value,
          child: child!,
        );
      },
    );
  }
}

class _GlitchTransitionLayout extends StatelessWidget {
  final Widget child;
  final double progress;
  final math.Random _random = math.Random();

  _GlitchTransitionLayout({required this.child, required this.progress});

  @override
  Widget build(BuildContext context) {
    // If progress is completed, display the child natively
    if (progress >= 1.0) {
      return child;
    }

    double dx = 0.0;
    double opacity = 1.0;

    // Based on the progress curve, introduce random shifts and opacity variations
    if (progress > 0.05 && progress < 0.20) {
      dx = _random.nextBool() ? -12.0 : 12.0;
      opacity = 0.65;
    } else if (progress > 0.30 && progress < 0.45) {
      dx = _random.nextBool() ? 18.0 : -18.0;
      opacity = 0.45;
    } else if (progress > 0.60 && progress < 0.75) {
      dx = _random.nextBool() ? -25.0 : 25.0;
      opacity = 0.35;
    } else if (progress > 0.80 && progress < 0.95) {
      dx = _random.nextBool() ? 8.0 : -8.0;
      opacity = 0.80;
    }

    return Transform.translate(
      offset: Offset(dx, 0),
      child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
    );
  }
}

/// A persistent overlay that renders low-opacity (0.03) noise static on top of dark screen layouts,
/// enhancing the spooky atmosphere.
class StaticOverlay extends StatefulWidget {
  final Widget? child;
  final double opacity;

  const StaticOverlay({super.key, this.child, this.opacity = 0.03});

  @override
  State<StaticOverlay> createState() => _StaticOverlayState();
}

class _StaticOverlayState extends State<StaticOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Continuous fast repetition loops to keep the noise active
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.child != null) widget.child!,
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _StaticNoisePainter(
                  opacity: widget.opacity,
                  animationValue: _controller.value,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StaticNoisePainter extends CustomPainter {
  final double opacity;
  final double animationValue;
  final math.Random _random = math.Random();

  Size? _lastSize;
  List<Offset>? _cachedPoints;

  _StaticNoisePainter({required this.opacity, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 1.0;

    // Cache the points when size is initialized or updated.
    // This avoids list and Offset object allocations inside paint() on every frame,
    // solving GC thrashing and frame drops.
    if (_cachedPoints == null || _lastSize != size) {
      _lastSize = size;
      // Pre-generate slightly larger noise region to support dynamic translation offset
      final int pointCount = ((size.width + 100) * (size.height + 100) / 1000)
          .clamp(500, 3000)
          .toInt();
      _cachedPoints = List.generate(pointCount, (index) {
        return Offset(
          _random.nextDouble() * (size.width + 100),
          _random.nextDouble() * (size.height + 100),
        );
      });
    }

    // Shift the viewport by minor random offset values on each frame to simulate movie static.
    // This provides dynamic movement without needing list re-allocations.
    canvas.save();
    final double dx = (_random.nextDouble() - 0.5) * 50.0;
    final double dy = (_random.nextDouble() - 0.5) * 50.0;
    canvas.translate(dx - 25, dy - 25);
    canvas.drawPoints(ui.PointMode.points, _cachedPoints!, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StaticNoisePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.opacity != opacity;
}
