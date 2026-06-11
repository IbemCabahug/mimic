import 'package:flutter/material.dart';

class BloodSplatterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8B0000).withValues(alpha: 0.85) // deep dark red
      ..style = PaintingStyle.fill;

    // Center splat
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    canvas.drawCircle(Offset(centerX, centerY), 60, paint);

    // Draw some drips/droplets
    // Splash 1
    canvas.drawCircle(Offset(centerX - 40, centerY - 30), 25, paint);
    canvas.drawCircle(Offset(centerX - 60, centerY - 50), 10, paint);
    // Splash 2
    canvas.drawCircle(Offset(centerX + 50, centerY + 20), 30, paint);
    canvas.drawCircle(Offset(centerX + 80, centerY + 40), 15, paint);
    canvas.drawCircle(Offset(centerX + 100, centerY + 50), 8, paint);
    // Splash 3
    canvas.drawCircle(Offset(centerX - 30, centerY + 60), 20, paint);
    // Splash 4
    canvas.drawCircle(Offset(centerX + 20, centerY - 60), 22, paint);
    canvas.drawCircle(Offset(centerX + 35, centerY - 90), 12, paint);

    // Draw some irregular runs
    final path = Path()
      ..moveTo(centerX - 10, centerY)
      ..quadraticBezierTo(centerX - 20, centerY + 80, centerX - 15, centerY + 100)
      ..lineTo(centerX - 5, centerY + 100)
      ..quadraticBezierTo(centerX, centerY + 80, centerX + 10, centerY)
      ..close();
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(centerX + 15, centerY - 10)
      ..quadraticBezierTo(centerX + 50, centerY - 80, centerX + 60, centerY - 100)
      ..lineTo(centerX + 70, centerY - 95)
      ..quadraticBezierTo(centerX + 55, centerY - 70, centerX + 25, centerY - 10)
      ..close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class BloodSplatterOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const BloodSplatterOverlay({super.key, required this.onDismiss});

  @override
  State<BloodSplatterOverlay> createState() => _BloodSplatterOverlayState();
}

class _BloodSplatterOverlayState extends State<BloodSplatterOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15, // rapid fade in
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50, // hold full opacity
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 35, // fade out
      ),
    ]).animate(_controller);

    _controller.forward().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, child) {
          return Opacity(
            opacity: _opacity.value,
            child: child,
          );
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.transparent,
          child: CustomPaint(
            painter: BloodSplatterPainter(),
          ),
        ),
      ),
    );
  }
}

void showBloodSplatter(OverlayState overlay) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (context) => BloodSplatterOverlay(
      onDismiss: () {
        entry?.remove();
      },
    ),
  );
  overlay.insert(entry);
}
