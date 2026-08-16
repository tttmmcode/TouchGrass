import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/league_definition.dart';

/// Static, low-opacity atmospheric backdrop behind a league's content,
/// abstracting the league's own color/theme into a painted motif rather
/// than rendering its emoji glyph enlarged (see [LeagueBackgroundMotif]'s
/// doc comment for why). Three reusable, parameterized painter families
/// cover all 8 leagues rather than eight independent implementations —
/// [LeagueDef.backgroundIntensity] is what differentiates leagues that
/// share a family.
///
/// Deliberately static (no [AnimationController], unlike the home screen's
/// landscape) — this sits directly behind readable league name/XP/row text,
/// so it stays fixed, low-opacity, and non-repainting once drawn.
class LeagueBackground extends StatelessWidget {
  const LeagueBackground({super.key, required this.league});

  final LeagueDef league;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LeagueBackgroundPainter(
            motif: league.backgroundMotif,
            color: league.color,
            intensity: league.backgroundIntensity,
            isDark: isDark,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _LeagueBackgroundPainter extends CustomPainter {
  const _LeagueBackgroundPainter({
    required this.motif,
    required this.color,
    required this.intensity,
    required this.isDark,
  });

  final LeagueBackgroundMotif motif;
  final Color color;
  final double intensity;
  final bool isDark;

  // Kept deliberately subtle — never meant to compete with the league
  // name, XP badge, or leaderboard row text painted on top of it. Dark
  // mode gets a touch more alpha since the same low value reads fainter
  // against the app's dark surface tokens.
  double get _maxOpacity => isDark ? 0.16 : 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    switch (motif) {
      case LeagueBackgroundMotif.botanical:
        _paintBotanical(canvas, size);
      case LeagueBackgroundMotif.peaks:
        _paintPeaks(canvas, size);
      case LeagueBackgroundMotif.sky:
        _paintSky(canvas, size);
    }
  }

  // ── Seedling / Sprout / Wildflower ──────────────────────────────────────
  // A soft radial glow near the top plus a loose cluster of rounded
  // leaf/petal silhouettes along the lower band — denser and taller as
  // intensity climbs.
  void _paintBotanical(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              color.withValues(alpha: _maxOpacity),
              color.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.12),
              radius: size.width * (0.45 + intensity * 0.25),
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);

    final leafCount = 5 + (intensity * 9).round();
    final leafPaint = Paint()..color = color.withValues(alpha: _maxOpacity);
    for (var i = 0; i < leafCount; i++) {
      final t = i / leafCount;
      final x = size.width * (0.05 + t * 0.90 + math.sin(i * 2.3) * 0.03);
      final baseY = size.height * (0.68 + math.sin(i * 1.7) * 0.09);
      final h =
          size.height *
          (0.09 + intensity * 0.14) *
          (0.7 + math.sin(i * 3.1).abs() * 0.5);
      final w = h * 0.55;
      canvas.save();
      canvas.translate(x, baseY - h / 2);
      canvas.rotate(math.sin(i * 1.3) * 0.5);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        leafPaint,
      );
      canvas.restore();
    }
  }

  // ── Forest / Mountain / Summit ──────────────────────────────────────────
  // Layered triangular silhouettes. Low intensity (Forest) reads as many
  // small, dense "trees"; high intensity (Summit) reads as fewer, taller,
  // sharper peaks with more atmospheric layering.
  void _paintPeaks(Canvas canvas, Size size) {
    final layerCount = 2 + (intensity * 2).round(); // 2..4
    for (var layer = 0; layer < layerCount; layer++) {
      final depth = layerCount <= 1 ? 0.0 : layer / (layerCount - 1);
      final alpha = _maxOpacity * (1.0 - depth * 0.5);
      final paint = Paint()..color = color.withValues(alpha: alpha);
      final baseline = size.height * (0.55 + depth * 0.14);
      final peakHeight =
          size.height * (0.09 + intensity * 0.20) * (1.0 - depth * 0.3);
      // Low intensity → many small peaks (dense treeline); high intensity
      // → few, tall peaks (sparse alpine silhouette).
      final peakCount = (9 - (intensity * 6).round() - layer).clamp(3, 12);

      final path = Path()..moveTo(0, size.height);
      for (var i = 0; i <= peakCount; i++) {
        final x = size.width * i / peakCount;
        final isPeak = i.isOdd;
        final y = isPeak
            ? baseline -
                  peakHeight * (0.55 + math.sin(i * 1.9 + layer).abs() * 0.45)
            : baseline;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  // ── Sky Trail / Aurora ───────────────────────────────────────────────────
  // Soft drifting cloud blobs at low intensity (Sky Trail); sweeping
  // abstract aurora ribbons at high intensity (Aurora).
  void _paintSky(Canvas canvas, Size size) {
    if (intensity < 0.7) {
      final paint = Paint()..color = color.withValues(alpha: _maxOpacity);
      const clouds = [
        (0.18, 0.18, 1.0),
        (0.58, 0.10, 0.7),
        (0.40, 0.28, 0.55),
        (0.82, 0.20, 0.8),
      ];
      for (final (xFrac, yFrac, scale) in clouds) {
        final center = Offset(size.width * xFrac, size.height * yFrac);
        final r = size.width * 0.10 * scale;
        for (final dx in [-r * 0.5, 0.0, r * 0.5]) {
          canvas.drawCircle(center + Offset(dx, 0), r * 0.6, paint);
        }
      }
      return;
    }

    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = color.withValues(alpha: _maxOpacity * (1 - i * 0.25))
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.05
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      final startY = size.height * (0.12 + i * 0.13);
      final path = Path()..moveTo(-size.width * 0.1, startY);
      path.quadraticBezierTo(
        size.width * 0.5,
        size.height * (0.0 + i * 0.13),
        size.width * 1.1,
        size.height * (0.20 + i * 0.13),
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LeagueBackgroundPainter old) =>
      old.motif != motif ||
      old.color != color ||
      old.intensity != intensity ||
      old.isDark != isDark;
}
