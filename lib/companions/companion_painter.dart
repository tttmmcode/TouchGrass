import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'companion.dart';

// ── Abstract base ─────────────────────────────────────────────────────────────

/// Stateless drawing parameters shared by all four companion painters.
/// Subclasses implement [paint] to render each character's unique shape.
abstract class CompanionPainter extends CustomPainter {
  const CompanionPainter({
    required this.bobOffset,
    required this.eyeOpenness,
    required this.armAngle,
    required this.jumpOffset,
    required this.smileAmount,
    required this.isDark,
  });

  /// -1.0 → +1.0  idle breathing bob (Y translation)
  final double bobOffset;

  /// 0.0 (closed) → 1.0 (open)  blink
  final double eyeOpenness;

  /// −π .. +π  wave / cheer arm rotation
  final double armAngle;

  /// 0.0 (ground) → 1.0 (peak)  jump height
  final double jumpOffset;

  /// 0.0 (neutral) → 1.0 (huge grin)  mouth curve
  final double smileAmount;

  final bool isDark;

  /// Factory: returns the correct painter for [type].
  factory CompanionPainter.forType(
    CompanionType type, {
    required double bobOffset,
    required double eyeOpenness,
    required double armAngle,
    required double jumpOffset,
    required double smileAmount,
    required bool isDark,
  }) => switch (type) {
    CompanionType.leafy => _LeafyPainter(
      bobOffset: bobOffset,
      eyeOpenness: eyeOpenness,
      armAngle: armAngle,
      jumpOffset: jumpOffset,
      smileAmount: smileAmount,
      isDark: isDark,
    ),
    CompanionType.pebble => _PebblePainter(
      bobOffset: bobOffset,
      eyeOpenness: eyeOpenness,
      armAngle: armAngle,
      jumpOffset: jumpOffset,
      smileAmount: smileAmount,
      isDark: isDark,
    ),
    CompanionType.sunny => _SunnyPainter(
      bobOffset: bobOffset,
      eyeOpenness: eyeOpenness,
      armAngle: armAngle,
      jumpOffset: jumpOffset,
      smileAmount: smileAmount,
      isDark: isDark,
    ),
    CompanionType.sprout => _SproutPainter(
      bobOffset: bobOffset,
      eyeOpenness: eyeOpenness,
      armAngle: armAngle,
      jumpOffset: jumpOffset,
      smileAmount: smileAmount,
      isDark: isDark,
    ),
  };

  @override
  bool shouldRepaint(covariant CompanionPainter old) =>
      old.bobOffset != bobOffset ||
      old.eyeOpenness != eyeOpenness ||
      old.armAngle != armAngle ||
      old.jumpOffset != jumpOffset ||
      old.smileAmount != smileAmount ||
      old.isDark != isDark;

  // ── Shared helpers ────────────────────────────────────────────────────────

  void _drawEye(Canvas canvas, Offset center, double rx, double ry) {
    final clampedOpen = eyeOpenness.clamp(0.05, 1.0);
    // White
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: rx * 2,
        height: ry * 2 * clampedOpen,
      ),
      Paint()..color = Colors.white,
    );
    if (clampedOpen < 0.15) return;
    // Pupil
    final pupilR = rx * 0.58 * clampedOpen;
    canvas.drawCircle(
      Offset(center.dx + rx * 0.06, center.dy),
      pupilR,
      Paint()..color = const Color(0xFF1A2B22),
    );
    // Highlight dot
    canvas.drawCircle(
      Offset(center.dx + rx * 0.22, center.dy - ry * 0.28),
      pupilR * 0.32,
      Paint()..color = Colors.white,
    );
  }

  void _drawCheek(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r,
      Paint()..color = const Color(0xFFFF9896).withValues(alpha: 0.42),
    );
  }

  void _drawSmile(Canvas canvas, Offset left, Offset right, double size) {
    final depth = smileAmount * size * 0.08;
    final mid = Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
    final path = Path()
      ..moveTo(left.dx, left.dy)
      ..quadraticBezierTo(mid.dx, mid.dy + depth, right.dx, right.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1A2B22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.038
        ..strokeCap = StrokeCap.round,
    );
  }

  // Apply bob and jump offsets, execute [draw], then restore.
  void _withTransform(Canvas canvas, Size size, void Function() draw) {
    canvas.save();
    final dy =
        bobOffset * size.height * 0.028 - jumpOffset * size.height * 0.14;
    canvas.translate(0, dy);
    draw();
    canvas.restore();
  }
}

// ── Leafy ─────────────────────────────────────────────────────────────────────
// A small green leaf creature with arms that wave and a big friendly smile.

class _LeafyPainter extends CompanionPainter {
  const _LeafyPainter({
    required super.bobOffset,
    required super.eyeOpenness,
    required super.armAngle,
    required super.jumpOffset,
    required super.smileAmount,
    required super.isDark,
  });

  @override
  void paint(Canvas canvas, Size s) {
    _withTransform(canvas, s, () {
      _body(canvas, s);
      _arms(canvas, s);
      _cheeks(canvas, s);
      _eyes(canvas, s);
      _smile(canvas, s);
    });
  }

  void _body(Canvas canvas, Size s) {
    final cx = s.width / 2;
    // Leaf: pointed top, rounded bottom, wide mid-section.
    final top = s.height * 0.06;
    final mid = s.height * 0.46;
    final bot = s.height * 0.84;
    final rx = s.width * 0.30;

    final path = Path()
      ..moveTo(cx, top)
      ..cubicTo(
        cx + rx * 0.65,
        top,
        cx + rx,
        mid - s.height * 0.20,
        cx + rx,
        mid,
      )
      ..cubicTo(cx + rx, mid + s.height * 0.22, cx + rx * 0.52, bot, cx, bot)
      ..cubicTo(
        cx - rx * 0.52,
        bot,
        cx - rx,
        mid + s.height * 0.22,
        cx - rx,
        mid,
      )
      ..cubicTo(cx - rx, mid - s.height * 0.20, cx - rx * 0.65, top, cx, top)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.grassGreenLight, AppColors.forestGreenDark],
        ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
    );
    // Subtle leaf vein
    canvas.drawLine(
      Offset(cx, s.height * 0.14),
      Offset(cx, s.height * 0.80),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = s.width * 0.03
        ..strokeCap = StrokeCap.round,
    );
    // Rim
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.forestGreenDark.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _arms(Canvas canvas, Size s) {
    final armPaint = Paint()
      ..color = AppColors.forestGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.07
      ..strokeCap = StrokeCap.round;

    // Right arm — waves with armAngle
    canvas.save();
    canvas.translate(s.width * 0.76, s.height * 0.50);
    canvas.rotate(-armAngle);
    canvas.drawLine(
      Offset.zero,
      Offset(s.width * 0.15, -s.height * 0.17),
      armPaint,
    );
    canvas.restore();

    // Left arm — subtle counter-wave
    canvas.save();
    canvas.translate(s.width * 0.24, s.height * 0.50);
    canvas.rotate(armAngle * 0.38);
    canvas.drawLine(
      Offset.zero,
      Offset(-s.width * 0.15, -s.height * 0.17),
      armPaint,
    );
    canvas.restore();
  }

  void _cheeks(Canvas canvas, Size s) {
    _drawCheek(canvas, Offset(s.width * 0.29, s.height * 0.54), s.width * 0.10);
    _drawCheek(canvas, Offset(s.width * 0.71, s.height * 0.54), s.width * 0.10);
  }

  void _eyes(Canvas canvas, Size s) {
    final eyeRx = s.width * 0.09;
    final eyeRy = s.width * 0.105;
    _drawEye(canvas, Offset(s.width * 0.37, s.height * 0.42), eyeRx, eyeRy);
    _drawEye(canvas, Offset(s.width * 0.63, s.height * 0.42), eyeRx, eyeRy);
  }

  void _smile(Canvas canvas, Size s) {
    _drawSmile(
      canvas,
      Offset(s.width * 0.36, s.height * 0.60),
      Offset(s.width * 0.64, s.height * 0.60),
      s.width,
    );
  }
}

// ── Pebble ────────────────────────────────────────────────────────────────────
// A calm, rounded rock companion. No arms — the whole body sways gently.

class _PebblePainter extends CompanionPainter {
  const _PebblePainter({
    required super.bobOffset,
    required super.eyeOpenness,
    required super.armAngle,
    required super.jumpOffset,
    required super.smileAmount,
    required super.isDark,
  });

  @override
  void paint(Canvas canvas, Size s) {
    _withTransform(canvas, s, () {
      // Whole-body sway (Pebble has no arms)
      canvas.save();
      canvas.translate(s.width / 2, s.height * 0.62);
      canvas.rotate(armAngle * 0.20);
      canvas.translate(-s.width / 2, -s.height * 0.62);
      _body(canvas, s);
      _spots(canvas, s);
      _cheeks(canvas, s);
      _eyes(canvas, s);
      _smile(canvas, s);
      canvas.restore();
    });
  }

  void _body(Canvas canvas, Size s) {
    // Wide, squat pebble shape.
    final rect = Rect.fromCenter(
      center: Offset(s.width / 2, s.height * 0.60),
      width: s.width * 0.80,
      height: s.height * 0.64,
    );
    // Slightly irregular using different corner radii
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(s.width * 0.38),
      topRight: Radius.circular(s.width * 0.44),
      bottomLeft: Radius.circular(s.width * 0.42),
      bottomRight: Radius.circular(s.width * 0.36),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFBEC8C3), Color(0xFF6E7D77)],
        ).createShader(rect),
    );
    // Highlight sheen
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          s.width * 0.22,
          s.height * 0.30,
          s.width * 0.25,
          s.height * 0.14,
        ),
        Radius.circular(s.width * 0.15),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );
    // Rim
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF4D5A55).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _spots(Canvas canvas, Size s) {
    // Subtle texture dots
    final spotPaint = Paint()..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(
      Offset(s.width * 0.32, s.height * 0.72),
      s.width * 0.06,
      spotPaint,
    );
    canvas.drawCircle(
      Offset(s.width * 0.60, s.height * 0.78),
      s.width * 0.04,
      spotPaint,
    );
    canvas.drawCircle(
      Offset(s.width * 0.72, s.height * 0.64),
      s.width * 0.035,
      spotPaint,
    );
  }

  void _cheeks(Canvas canvas, Size s) {
    _drawCheek(canvas, Offset(s.width * 0.27, s.height * 0.62), s.width * 0.10);
    _drawCheek(canvas, Offset(s.width * 0.73, s.height * 0.62), s.width * 0.10);
  }

  void _eyes(Canvas canvas, Size s) {
    final rx = s.width * 0.085;
    final ry = s.width * 0.10;
    _drawEye(canvas, Offset(s.width * 0.37, s.height * 0.50), rx, ry);
    _drawEye(canvas, Offset(s.width * 0.63, s.height * 0.50), rx, ry);
  }

  void _smile(Canvas canvas, Size s) {
    _drawSmile(
      canvas,
      Offset(s.width * 0.37, s.height * 0.68),
      Offset(s.width * 0.63, s.height * 0.68),
      s.width,
    );
  }
}

// ── Sunny ─────────────────────────────────────────────────────────────────────
// A bright little sun companion whose rays spin and expand when excited.

class _SunnyPainter extends CompanionPainter {
  const _SunnyPainter({
    required super.bobOffset,
    required super.eyeOpenness,
    required super.armAngle,
    required super.jumpOffset,
    required super.smileAmount,
    required super.isDark,
  });

  @override
  void paint(Canvas canvas, Size s) {
    _withTransform(canvas, s, () {
      _rays(canvas, s);
      _disc(canvas, s);
      _cheeks(canvas, s);
      _eyes(canvas, s);
      _smile(canvas, s);
    });
  }

  void _rays(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    final innerR = s.width * 0.32;
    // Rays expand slightly when excited (armAngle > 0)
    final rayLen = s.width * (0.13 + armAngle.abs() * 0.04);
    final rayW = s.width * 0.07;

    final rayPaint = Paint()
      ..color = const Color(0xFFFFD60A)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = rayW
      ..style = PaintingStyle.stroke;

    // 8 rays, slowly rotate with armAngle
    final baseAngle = armAngle * 0.15;
    for (var i = 0; i < 8; i++) {
      final angle = baseAngle + i * math.pi / 4;
      final start = Offset(
        cx + innerR * math.cos(angle),
        cy + innerR * math.sin(angle),
      );
      final end = Offset(
        cx + (innerR + rayLen) * math.cos(angle),
        cy + (innerR + rayLen) * math.sin(angle),
      );
      canvas.drawLine(start, end, rayPaint);
    }
  }

  void _disc(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final r = s.width * 0.32;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [Color(0xFFFFF176), Color(0xFFFFB703)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Rim
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = const Color(0xFFE07B00).withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _cheeks(Canvas canvas, Size s) {
    _drawCheek(canvas, Offset(s.width * 0.29, s.height * 0.57), s.width * 0.08);
    _drawCheek(canvas, Offset(s.width * 0.71, s.height * 0.57), s.width * 0.08);
  }

  void _eyes(Canvas canvas, Size s) {
    // Sunny has happy-squint eyes (always slightly narrowed upward).
    final clampedOpen = (eyeOpenness * 0.7 + 0.3).clamp(0.1, 1.0);
    final rx = s.width * 0.082;
    final ry = rx * 0.8;
    // White base
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * 0.37, s.height * 0.44),
        width: rx * 2,
        height: ry * 2 * clampedOpen,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s.width * 0.63, s.height * 0.44),
        width: rx * 2,
        height: ry * 2 * clampedOpen,
      ),
      Paint()..color = Colors.white,
    );
    // Pupils
    final pupilR = rx * 0.52 * clampedOpen;
    final pupilPaint = Paint()..color = const Color(0xFF7B3F00);
    canvas.drawCircle(
      Offset(s.width * 0.38, s.height * 0.44),
      pupilR,
      pupilPaint,
    );
    canvas.drawCircle(
      Offset(s.width * 0.64, s.height * 0.44),
      pupilR,
      pupilPaint,
    );
    // Highlights
    final hlPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(s.width * 0.40, s.height * 0.425),
      pupilR * 0.32,
      hlPaint,
    );
    canvas.drawCircle(
      Offset(s.width * 0.66, s.height * 0.425),
      pupilR * 0.32,
      hlPaint,
    );
  }

  void _smile(Canvas canvas, Size s) {
    _drawSmile(
      canvas,
      Offset(s.width * 0.34, s.height * 0.60),
      Offset(s.width * 0.66, s.height * 0.60),
      s.width,
    );
  }
}

// ── Sprout ────────────────────────────────────────────────────────────────────
// A tiny nature spirit with leaf ears and wide, curious eyes.

class _SproutPainter extends CompanionPainter {
  const _SproutPainter({
    required super.bobOffset,
    required super.eyeOpenness,
    required super.armAngle,
    required super.jumpOffset,
    required super.smileAmount,
    required super.isDark,
  });

  @override
  void paint(Canvas canvas, Size s) {
    _withTransform(canvas, s, () {
      _stem(canvas, s);
      _leafEars(canvas, s);
      _head(canvas, s);
      _cheeks(canvas, s);
      _eyes(canvas, s);
      _smile(canvas, s);
    });
  }

  void _stem(Canvas canvas, Size s) {
    final stemRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        s.width * 0.42,
        s.height * 0.66,
        s.width * 0.16,
        s.height * 0.24,
      ),
      Radius.circular(s.width * 0.06),
    );
    canvas.drawRRect(
      stemRect,
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.grassGreenLight, AppColors.forestGreen],
            ).createShader(
              Rect.fromLTWH(0, s.height * 0.60, s.width, s.height * 0.34),
            ),
    );
  }

  void _leafEars(Canvas canvas, Size s) {
    // Left ear — rotates with armAngle (wiggling)
    canvas.save();
    canvas.translate(s.width * 0.24, s.height * 0.30);
    canvas.rotate(-math.pi / 5 + armAngle * 0.25);
    _drawLeafEar(canvas, s, false);
    canvas.restore();

    // Right ear — mirror wiggle
    canvas.save();
    canvas.translate(s.width * 0.76, s.height * 0.30);
    canvas.rotate(math.pi / 5 - armAngle * 0.25);
    _drawLeafEar(canvas, s, true);
    canvas.restore();
  }

  void _drawLeafEar(Canvas canvas, Size s, bool mirrored) {
    final rx = s.width * 0.14;
    final ry = s.width * 0.20;
    final path = Path()
      ..addOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      );
    canvas.drawPath(
      path,
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.grassGreenLight, AppColors.forestGreen],
            ).createShader(
              Rect.fromCenter(
                center: Offset.zero,
                width: rx * 2,
                height: ry * 2,
              ),
            ),
    );
    // Vein
    canvas.drawLine(
      Offset(0, -ry * 0.7),
      Offset(0, ry * 0.7),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = s.width * 0.025
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.forestGreenDark.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _head(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height * 0.46);
    final r = s.width * 0.34;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.25),
          colors: [AppColors.grassGreenLight, AppColors.forestGreen],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    // Highlight
    canvas.drawCircle(
      Offset(s.width * 0.36, s.height * 0.34),
      r * 0.24,
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    // Rim
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = AppColors.forestGreenDark.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _cheeks(Canvas canvas, Size s) {
    _drawCheek(canvas, Offset(s.width * 0.27, s.height * 0.52), s.width * 0.09);
    _drawCheek(canvas, Offset(s.width * 0.73, s.height * 0.52), s.width * 0.09);
  }

  void _eyes(Canvas canvas, Size s) {
    // Sprout has large, wide, innocent eyes.
    final rx = s.width * 0.105;
    final ry = s.width * 0.118;
    _drawEye(canvas, Offset(s.width * 0.37, s.height * 0.43), rx, ry);
    _drawEye(canvas, Offset(s.width * 0.63, s.height * 0.43), rx, ry);
  }

  void _smile(Canvas canvas, Size s) {
    _drawSmile(
      canvas,
      Offset(s.width * 0.37, s.height * 0.60),
      Offset(s.width * 0.63, s.height * 0.60),
      s.width,
    );
  }
}
