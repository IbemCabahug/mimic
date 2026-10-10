// lib/game/widgets/word_silhouette_widget.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mimic/core/theme/horror_theme.dart';
import 'package:mimic/game/services/word_silhouette_resolver.dart';

class WordSilhouetteWidget extends StatelessWidget {
  final WordSilhouetteType type;
  final double size;

  const WordSilhouetteWidget({
    super.key,
    required this.type,
    this.size = 76.0,
  });

  factory WordSilhouetteWidget.fromWord(
    String word, {
    String? category,
    double size = 76.0,
    Key? key,
  }) {
    final resolved = WordSilhouetteResolver.resolve(word, category: category);
    return WordSilhouetteWidget(
      key: key,
      type: resolved,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HorrorColors.voidBlack,
        border: Border.all(
          color: HorrorColors.crimson.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: HorrorColors.bloodRed.withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _SilhouettePainter(type),
        ),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  final WordSilhouetteType type;

  _SilhouettePainter(this.type);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background radial vignette
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          HorrorColors.darkRedTint.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    final fillPaint = Paint()
      ..color = HorrorColors.crimson
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = HorrorColors.fogWhite.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (type) {
      case WordSilhouetteType.dagger:
        _drawDagger(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.scythe:
        _drawScythe(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.skull:
        _drawSkull(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.coffin:
        _drawCoffin(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.mansion:
        _drawMansion(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.candle:
        _drawCandle(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.mirror:
        _drawMirror(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.poison:
        _drawPoison(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.noose:
        _drawNoose(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.chainsaw:
        _drawChainsaw(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.grimoire:
        _drawGrimoire(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.aswangWings:
        _drawWings(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.beastClaws:
        _drawClaws(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.specter:
        _drawSpecter(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.spider:
        _drawSpider(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.eye:
        _drawEye(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.forestTree:
        _drawTree(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.doll:
        _drawDoll(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.graveyard:
        _drawGraveyard(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.altar:
        _drawAltar(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.key:
        _drawKey(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.mask:
        _drawMask(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.moon:
        _drawMoon(canvas, w, h, fillPaint, strokePaint);
        break;
      case WordSilhouetteType.generalHorror:
        _drawGeneralHorror(canvas, w, h, fillPaint, strokePaint);
        break;
    }
  }

  void _drawDagger(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final path = Path();
    // Blade
    path.moveTo(w * 0.5, h * 0.16); // tip
    path.lineTo(w * 0.58, h * 0.55);
    path.lineTo(w * 0.42, h * 0.55);
    path.close();
    canvas.drawPath(path, fill);

    // Guard
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.5, h * 0.57), width: w * 0.36, height: h * 0.05),
        const Radius.circular(2),
      ),
      fill,
    );
    // Hilt
    canvas.drawRect(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.68), width: w * 0.08, height: h * 0.18),
      fill,
    );
    // Pommel
    canvas.drawCircle(Offset(w * 0.5, h * 0.80), w * 0.06, fill);
    // Highlight centerline
    canvas.drawLine(Offset(w * 0.5, h * 0.22), Offset(w * 0.5, h * 0.52), stroke);
  }

  void _drawScythe(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Shaft
    final shaft = Path()
      ..moveTo(w * 0.32, h * 0.82)
      ..lineTo(w * 0.68, h * 0.22)
      ..lineTo(w * 0.72, h * 0.25)
      ..lineTo(w * 0.36, h * 0.85)
      ..close();
    canvas.drawPath(shaft, fill);

    // Curved Blade
    final blade = Path()
      ..moveTo(w * 0.70, h * 0.22)
      ..quadraticBezierTo(w * 0.30, h * 0.18, w * 0.18, h * 0.42)
      ..quadraticBezierTo(w * 0.38, h * 0.30, w * 0.68, h * 0.28)
      ..close();
    canvas.drawPath(blade, fill);
  }

  void _drawSkull(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Cranium
    final path = Path();
    path.addOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.42), width: w * 0.50, height: h * 0.46));
    // Jaw
    path.addRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.68), width: w * 0.28, height: h * 0.20));
    canvas.drawPath(path, fill);

    // Eye sockets (cut out with black)
    final cutout = Paint()..color = HorrorColors.voidBlack;
    canvas.drawCircle(Offset(w * 0.40, h * 0.46), w * 0.08, cutout);
    canvas.drawCircle(Offset(w * 0.60, h * 0.46), w * 0.08, cutout);

    // Inverted heart nose
    final nose = Path()
      ..moveTo(w * 0.5, h * 0.55)
      ..lineTo(w * 0.46, h * 0.62)
      ..lineTo(w * 0.54, h * 0.62)
      ..close();
    canvas.drawPath(nose, cutout);

    // Teeth slits
    canvas.drawLine(Offset(w * 0.44, h * 0.70), Offset(w * 0.44, h * 0.76), stroke);
    canvas.drawLine(Offset(w * 0.50, h * 0.70), Offset(w * 0.50, h * 0.76), stroke);
    canvas.drawLine(Offset(w * 0.56, h * 0.70), Offset(w * 0.56, h * 0.76), stroke);
  }

  void _drawCoffin(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final path = Path()
      ..moveTo(w * 0.5, h * 0.18) // top center
      ..lineTo(w * 0.68, h * 0.38) // right shoulder
      ..lineTo(w * 0.60, h * 0.82) // right foot
      ..lineTo(w * 0.40, h * 0.82) // left foot
      ..lineTo(w * 0.32, h * 0.38) // left shoulder
      ..close();
    canvas.drawPath(path, fill);

    // Cross on lid
    final crossPaint = Paint()
      ..color = HorrorColors.voidBlack
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(w * 0.5, h * 0.32), Offset(w * 0.5, h * 0.66), crossPaint);
    canvas.drawLine(Offset(w * 0.40, h * 0.44), Offset(w * 0.60, h * 0.44), crossPaint);
  }

  void _drawMansion(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final path = Path();
    // Central tower
    path.moveTo(w * 0.5, h * 0.16);
    path.lineTo(w * 0.62, h * 0.35);
    path.lineTo(w * 0.62, h * 0.82);
    path.lineTo(w * 0.38, h * 0.82);
    path.lineTo(w * 0.38, h * 0.35);
    path.close();

    // Left wing
    path.moveTo(w * 0.38, h * 0.45);
    path.lineTo(w * 0.22, h * 0.55);
    path.lineTo(w * 0.22, h * 0.82);
    path.lineTo(w * 0.38, h * 0.82);
    path.close();

    // Right wing
    path.moveTo(w * 0.62, h * 0.45);
    path.lineTo(w * 0.78, h * 0.55);
    path.lineTo(w * 0.78, h * 0.82);
    path.lineTo(w * 0.62, h * 0.82);
    path.close();
    canvas.drawPath(path, fill);

    // Tower window
    final cutout = Paint()..color = HorrorColors.voidBlack;
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.45), width: w * 0.08, height: h * 0.12), cutout);
  }

  void _drawCandle(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.5, h * 0.60), width: w * 0.22, height: h * 0.40),
        const Radius.circular(3),
      ),
      fill,
    );
    // Wick
    canvas.drawLine(Offset(w * 0.5, h * 0.40), Offset(w * 0.5, h * 0.34), stroke);

    // Flame
    final flame = Path()
      ..moveTo(w * 0.5, h * 0.18)
      ..quadraticBezierTo(w * 0.62, h * 0.26, w * 0.5, h * 0.34)
      ..quadraticBezierTo(w * 0.38, h * 0.26, w * 0.5, h * 0.18)
      ..close();
    canvas.drawPath(flame, fill);
  }

  void _drawMirror(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Frame
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.48, height: h * 0.66),
      fill,
    );
    // Glass cutout
    final cutout = Paint()..color = HorrorColors.voidBlack;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.36, height: h * 0.52),
      cutout,
    );
    // Crack line
    final crack = Path()
      ..moveTo(w * 0.40, h * 0.32)
      ..lineTo(w * 0.52, h * 0.50)
      ..lineTo(w * 0.46, h * 0.68);
    canvas.drawPath(crack, stroke);
  }

  void _drawPoison(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final flask = Path()
      // Neck
      ..moveTo(w * 0.42, h * 0.22)
      ..lineTo(w * 0.58, h * 0.22)
      ..lineTo(w * 0.58, h * 0.40)
      // Bulb
      ..lineTo(w * 0.74, h * 0.72)
      ..quadraticBezierTo(w * 0.74, h * 0.82, w * 0.5, h * 0.82)
      ..quadraticBezierTo(w * 0.26, h * 0.82, w * 0.26, h * 0.72)
      ..lineTo(w * 0.42, h * 0.40)
      ..close();
    canvas.drawPath(flask, fill);

    // Cork
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.18), width: w * 0.20, height: h * 0.08), fill);
    // Bubbles
    canvas.drawCircle(Offset(w * 0.48, h * 0.62), w * 0.04, stroke);
    canvas.drawCircle(Offset(w * 0.56, h * 0.70), w * 0.05, stroke);
  }

  void _drawNoose(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final rope = Path()
      ..moveTo(w * 0.5, h * 0.15)
      ..lineTo(w * 0.5, h * 0.42);
    canvas.drawPath(rope, stroke);

    // Knot
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.46), width: w * 0.12, height: h * 0.10), fill);

    // Loop
    final loop = Path();
    loop.addOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.65), width: w * 0.30, height: h * 0.30));
    canvas.drawPath(loop, stroke);
  }

  void _drawChainsaw(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Motor body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.36, h * 0.52), width: w * 0.28, height: h * 0.26),
        const Radius.circular(4),
      ),
      fill,
    );
    // Guide bar
    final bar = Path()
      ..moveTo(w * 0.50, h * 0.44)
      ..lineTo(w * 0.80, h * 0.44)
      ..quadraticBezierTo(w * 0.86, h * 0.52, w * 0.80, h * 0.60)
      ..lineTo(w * 0.50, h * 0.60)
      ..close();
    canvas.drawPath(bar, fill);

    // Rear handle
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.20, h * 0.52), width: w * 0.16, height: h * 0.22),
      -math.pi / 2,
      math.pi,
      false,
      stroke,
    );
  }

  void _drawGrimoire(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Book cover
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.5, h * 0.52), width: w * 0.46, height: h * 0.56),
        const Radius.circular(4),
      ),
      fill,
    );
    // Spine band
    canvas.drawRect(
      Rect.fromLTWH(w * 0.27, h * 0.24, w * 0.08, h * 0.56),
      Paint()..color = HorrorColors.voidBlack,
    );
    // Occult star on cover
    final star = Path()
      ..moveTo(w * 0.54, h * 0.40)
      ..lineTo(w * 0.54, h * 0.64);
    canvas.drawPath(star, stroke);
    final horiz = Path()
      ..moveTo(w * 0.42, h * 0.52)
      ..lineTo(w * 0.66, h * 0.52);
    canvas.drawPath(horiz, stroke);
  }

  void _drawWings(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Aswang bat wings
    final wings = Path()
      ..moveTo(w * 0.5, h * 0.60)
      // Left wing
      ..quadraticBezierTo(w * 0.35, h * 0.25, w * 0.15, h * 0.28)
      ..quadraticBezierTo(w * 0.22, h * 0.48, w * 0.18, h * 0.65)
      ..quadraticBezierTo(w * 0.34, h * 0.58, w * 0.5, h * 0.60)
      // Right wing
      ..quadraticBezierTo(w * 0.65, h * 0.25, w * 0.85, h * 0.28)
      ..quadraticBezierTo(w * 0.78, h * 0.48, w * 0.82, h * 0.65)
      ..quadraticBezierTo(w * 0.66, h * 0.58, w * 0.5, h * 0.60)
      ..close();
    canvas.drawPath(wings, fill);
    // Body core
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.56), width: w * 0.12, height: h * 0.28), fill);
  }

  void _drawClaws(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    for (int i = 0; i < 3; i++) {
      final offsetX = w * (0.35 + i * 0.15);
      final claw = Path()
        ..moveTo(offsetX, h * 0.25)
        ..quadraticBezierTo(offsetX + w * 0.08, h * 0.50, offsetX - w * 0.04, h * 0.75)
        ..quadraticBezierTo(offsetX + w * 0.02, h * 0.52, offsetX + w * 0.04, h * 0.25)
        ..close();
      canvas.drawPath(claw, fill);
    }
  }

  void _drawSpecter(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    final ghost = Path()
      ..moveTo(w * 0.5, h * 0.22)
      ..quadraticBezierTo(w * 0.72, h * 0.26, w * 0.68, h * 0.58)
      ..lineTo(w * 0.74, h * 0.76)
      ..lineTo(w * 0.62, h * 0.70)
      ..lineTo(w * 0.50, h * 0.78)
      ..lineTo(w * 0.38, h * 0.70)
      ..lineTo(w * 0.26, h * 0.76)
      ..lineTo(w * 0.32, h * 0.58)
      ..quadraticBezierTo(w * 0.28, h * 0.26, w * 0.5, h * 0.22)
      ..close();
    canvas.drawPath(ghost, fill);

    // Eye sockets
    final cutout = Paint()..color = HorrorColors.voidBlack;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.44, h * 0.38), width: w * 0.06, height: h * 0.09), cutout);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.56, h * 0.38), width: w * 0.06, height: h * 0.09), cutout);
  }

  void _drawSpider(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Body & head
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.54), width: w * 0.22, height: h * 0.28), fill);
    canvas.drawCircle(Offset(w * 0.5, h * 0.38), w * 0.09, fill);

    // 8 Legs
    for (int i = 0; i < 4; i++) {
      final legY = h * (0.42 + i * 0.08);
      // Left leg
      final lLeg = Path()
        ..moveTo(w * 0.42, legY)
        ..lineTo(w * 0.24, legY - h * 0.08)
        ..lineTo(w * 0.16, legY + h * 0.06);
      canvas.drawPath(lLeg, stroke);
      // Right leg
      final rLeg = Path()
        ..moveTo(w * 0.58, legY)
        ..lineTo(w * 0.76, legY - h * 0.08)
        ..lineTo(w * 0.84, legY + h * 0.06);
      canvas.drawPath(rLeg, stroke);
    }
  }

  void _drawEye(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Almond Eye
    final eyePath = Path()
      ..moveTo(w * 0.18, h * 0.50)
      ..quadraticBezierTo(w * 0.5, h * 0.22, w * 0.82, h * 0.50)
      ..quadraticBezierTo(w * 0.5, h * 0.78, w * 0.18, h * 0.50)
      ..close();
    canvas.drawPath(eyePath, fill);

    // Pupil
    final pupil = Paint()..color = HorrorColors.voidBlack;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.12, height: h * 0.28), pupil);
  }

  void _drawTree(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Trunk
    final trunk = Path()
      ..moveTo(w * 0.44, h * 0.84)
      ..lineTo(w * 0.46, h * 0.52)
      ..lineTo(w * 0.54, h * 0.52)
      ..lineTo(w * 0.56, h * 0.84)
      ..close();
    canvas.drawPath(trunk, fill);

    // Branches
    final b1 = Path()
      ..moveTo(w * 0.50, h * 0.56)
      ..lineTo(w * 0.28, h * 0.32)
      ..lineTo(w * 0.22, h * 0.24);
    canvas.drawPath(b1, stroke);
    final b2 = Path()
      ..moveTo(w * 0.50, h * 0.56)
      ..lineTo(w * 0.72, h * 0.32)
      ..lineTo(w * 0.78, h * 0.24);
    canvas.drawPath(b2, stroke);
    final b3 = Path()
      ..moveTo(w * 0.50, h * 0.52)
      ..lineTo(w * 0.50, h * 0.22);
    canvas.drawPath(b3, stroke);
  }

  void _drawDoll(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Head
    canvas.drawCircle(Offset(w * 0.5, h * 0.35), w * 0.16, fill);
    // Body
    final body = Path()
      ..moveTo(w * 0.38, h * 0.50)
      ..lineTo(w * 0.62, h * 0.50)
      ..lineTo(w * 0.70, h * 0.80)
      ..lineTo(w * 0.30, h * 0.80)
      ..close();
    canvas.drawPath(body, fill);

    // Button eye
    canvas.drawCircle(Offset(w * 0.44, h * 0.34), w * 0.04, stroke);
    // X eye
    canvas.drawLine(Offset(w * 0.53, h * 0.31), Offset(w * 0.59, h * 0.37), stroke);
    canvas.drawLine(Offset(w * 0.59, h * 0.31), Offset(w * 0.53, h * 0.37), stroke);
  }

  void _drawGraveyard(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Headstone rounded arch
    final stone = Path()
      ..moveTo(w * 0.30, h * 0.82)
      ..lineTo(w * 0.30, h * 0.42)
      ..quadraticBezierTo(w * 0.50, h * 0.24, w * 0.70, h * 0.42)
      ..lineTo(w * 0.70, h * 0.82)
      ..close();
    canvas.drawPath(stone, fill);

    // Ground mound
    canvas.drawRect(Rect.fromLTWH(w * 0.18, h * 0.80, w * 0.64, h * 0.06), fill);

    // RIP Cross
    final cutout = Paint()
      ..color = HorrorColors.voidBlack
      ..strokeWidth = 3.0;
    canvas.drawLine(Offset(w * 0.5, h * 0.42), Offset(w * 0.5, h * 0.66), cutout);
    canvas.drawLine(Offset(w * 0.42, h * 0.50), Offset(w * 0.58, h * 0.50), cutout);
  }

  void _drawAltar(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Tiered plinth
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.78), width: w * 0.64, height: h * 0.08), fill);
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.70), width: w * 0.48, height: h * 0.08), fill);
    canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.58), width: w * 0.36, height: h * 0.16), fill);

    // Smoking bowl / chalice
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.48), width: w * 0.24, height: h * 0.16),
      0,
      math.pi,
      true,
      fill,
    );
    // Smoke wisps
    final smoke = Path()
      ..moveTo(w * 0.5, h * 0.40)
      ..quadraticBezierTo(w * 0.44, h * 0.32, w * 0.52, h * 0.22);
    canvas.drawPath(smoke, stroke);
  }

  void _drawKey(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Ring handle
    canvas.drawCircle(Offset(w * 0.36, h * 0.36), w * 0.14, fill);
    canvas.drawCircle(Offset(w * 0.36, h * 0.36), w * 0.06, Paint()..color = HorrorColors.voidBlack);

    // Shaft
    final shaft = Path()
      ..moveTo(w * 0.44, h * 0.44)
      ..lineTo(w * 0.72, h * 0.72)
      ..lineTo(w * 0.68, h * 0.76)
      ..lineTo(w * 0.40, h * 0.48)
      ..close();
    canvas.drawPath(shaft, fill);

    // Teeth
    final tooth = Path()
      ..moveTo(w * 0.68, h * 0.68)
      ..lineTo(w * 0.76, h * 0.60)
      ..lineTo(w * 0.80, h * 0.64)
      ..lineTo(w * 0.72, h * 0.72)
      ..close();
    canvas.drawPath(tooth, fill);
  }

  void _drawMask(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Half masquerade / phantom mask
    final mask = Path()
      ..moveTo(w * 0.22, h * 0.42)
      ..quadraticBezierTo(w * 0.50, h * 0.28, w * 0.78, h * 0.42)
      ..quadraticBezierTo(w * 0.74, h * 0.66, w * 0.50, h * 0.74)
      ..quadraticBezierTo(w * 0.26, h * 0.66, w * 0.22, h * 0.42)
      ..close();
    canvas.drawPath(mask, fill);

    // Eye cutouts
    final cutout = Paint()..color = HorrorColors.voidBlack;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.38, h * 0.48), width: w * 0.12, height: h * 0.08), cutout);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.62, h * 0.48), width: w * 0.12, height: h * 0.08), cutout);
  }

  void _drawMoon(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Crescent Moon
    final moon = Path()
      ..addOval(Rect.fromCenter(center: Offset(w * 0.50, h * 0.50), width: w * 0.50, height: h * 0.50));
    canvas.drawPath(moon, fill);

    // Shadow sphere carving the crescent
    final shadow = Paint()..color = HorrorColors.voidBlack;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.60, h * 0.44), width: w * 0.46, height: h * 0.46), shadow);
  }

  void _drawGeneralHorror(Canvas canvas, double w, double h, Paint fill, Paint stroke) {
    // Horned crest shield
    final crest = Path()
      ..moveTo(w * 0.26, h * 0.28) // left horn
      ..lineTo(w * 0.36, h * 0.38)
      ..lineTo(w * 0.50, h * 0.32) // center crest
      ..lineTo(w * 0.64, h * 0.38)
      ..lineTo(w * 0.74, h * 0.28) // right horn
      ..lineTo(w * 0.68, h * 0.56)
      ..lineTo(w * 0.50, h * 0.76) // bottom point
      ..lineTo(w * 0.32, h * 0.56)
      ..close();
    canvas.drawPath(crest, fill);

    // Glowing core eye
    canvas.drawCircle(Offset(w * 0.50, h * 0.50), w * 0.08, Paint()..color = HorrorColors.voidBlack);
    canvas.drawCircle(Offset(w * 0.50, h * 0.50), w * 0.04, stroke);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) {
    return oldDelegate.type != type;
  }
}
