import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/challenge_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/pressable_scale.dart';

// Smooth winding trail — two overlapping low-frequency sine waves rather
// than a fixed-cycle zigzag, so consecutive nodes shift gradually (no sharp
// jumps) and the pattern doesn't visibly repeat every few nodes.
double _xOffset(int index, double available) {
  final t = index.toDouble();
  final wave = math.sin(t * 0.55) * 0.34 + math.sin(t * 0.19 + 1.3) * 0.18;
  final fraction = wave.clamp(-0.55, 0.55);
  return fraction * (available - _kNodeSize) / 2;
}

const double _kNodeSize = 78.0;
const double _kActiveNodeSize = 108.0;
const double _kSegmentH = 284.0;
const double _kNodeTopPad = 20.0;

// Stone palette
const Color _stoneBase = Color(0xFFB8AD9E);
const Color _stoneShadow = Color(0xFF6E6259);
const Color _stoneHighlight = Color(0xFFD9D3CA);
const Color _stoneGlow = Color(0xFFFFF8C0);

// Lily pad palette
const Color _lilyActive = Color(0xFF28BE68);
const Color _lilyActiveLight = Color(0xFF4DD882);
const Color _lilyActiveDark = Color(0xFF185F36);
const Color _lilyGold = Color(0xFFFFCE2C);
const Color _lilyCompleted = Color(0xFF237A44);
const Color _lilyCompletedLight = Color(0xFF40C26A);
const Color _lilyLocked = Color(0xFF4E8862);
const Color _lilyLockedLight = Color(0xFF78AC8A);

// ── Organic lily pad path ─────────────────────────────────────────────────────

Path _buildLilyPadPath(double cx, double cy, double r, double seed) {
  const steps = 80;
  final path = Path();
  for (var i = 0; i <= steps; i++) {
    final angle = (i / steps) * 2 * math.pi - math.pi / 2;
    final rr =
        r *
        (1.0 +
            0.048 * math.sin(angle * 3.0 + seed) +
            0.030 * math.sin(angle * 5.0 + seed * 1.7) +
            0.016 * math.sin(angle * 8.0 + seed * 2.5));
    final x = cx + rr * math.cos(angle);
    final y = cy + rr * math.sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

// ── Segment ───────────────────────────────────────────────────────────────────

class ChallengePathSegment extends ConsumerStatefulWidget {
  const ChallengePathSegment({
    super.key,
    required this.node,
    required this.index,
    required this.isLast,
    required this.onTap,
  });

  final PathNode node;
  final int index;
  final bool isLast;
  final VoidCallback onTap;

  @override
  ConsumerState<ChallengePathSegment> createState() =>
      _ChallengePathSegmentState();
}

class _ChallengePathSegmentState extends ConsumerState<ChallengePathSegment>
    with TickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _particleCtrl;
  Timer? _rippleTimer;

  bool get _isCompleted => widget.node is CompletedPathNode;
  bool get _isActive => widget.node is ActivePathNode;

  // Deterministic seed per node — drives organic shape variation.
  double get _seed => widget.index * 1.618;

  String get _semanticLabel {
    final day = widget.node.dayNumber;
    return switch (widget.node) {
      ActivePathNode() => "Day $day, today's challenge. Double tap to open.",
      CompletedPathNode() =>
        'Day $day, challenge completed. Double tap to view.',
      MissedPathNode() => 'Day $day, challenge missed.',
      LockedPathNode() => 'Day $day, locked.',
    };
  }

  @override
  void initState() {
    super.initState();

    // Phase-offset by index so every completed node's stone-trail glow dot
    // isn't pulsing in lockstep with every other one on screen at once.
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..value = (widget.index % 5) / 5.0;

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..value = (widget.index % 7) / 7.0;

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    );

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _applyMotionPreference(ref.read(reducedMotionProvider));
  }

  /// Starts/stops the continuous ambient loops (glow, particles, float,
  /// periodic ripple) based on the Reduce Motion setting. Safe to call
  /// repeatedly — each start/stop is a no-op if already in that state.
  void _applyMotionPreference(bool reduceMotion) {
    if (reduceMotion) {
      _glowCtrl.stop();
      _particleCtrl.stop();
      _floatCtrl.stop();
      _rippleTimer?.cancel();
      _rippleTimer = null;
    } else {
      if (!_glowCtrl.isAnimating) _glowCtrl.repeat();
      if (!_particleCtrl.isAnimating) _particleCtrl.repeat();
      if (!_floatCtrl.isAnimating) _floatCtrl.repeat(reverse: true);
      if (_isActive && _rippleTimer == null) _scheduleRipple();
    }
  }

  void _scheduleRipple() {
    _rippleTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        _rippleCtrl.forward(from: 0).then((_) {
          if (mounted && !ref.read(reducedMotionProvider)) _scheduleRipple();
        });
      }
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _particleCtrl.dispose();
    _floatCtrl.dispose();
    _rippleCtrl.dispose();
    _rippleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _applyMotionPreference(ref.watch(reducedMotionProvider));
    return LayoutBuilder(
      builder: (context, constraints) {
        final avail = constraints.maxWidth;
        final xOff = _xOffset(widget.index, avail);
        final nextXOff = widget.isLast
            ? xOff
            : _xOffset(widget.index + 1, avail);
        final nodeSize = _isActive ? _kActiveNodeSize : _kNodeSize;
        final centerX = avail / 2 + xOff;
        final nextCenterX = avail / 2 + nextXOff;

        // Isolates this segment's continuous animations (glow, particles,
        // ripple, pulse) to their own compositing layer so an actively
        // animating node never forces neighboring trail segments — which
        // are otherwise static — to repaint alongside it.
        return RepaintBoundary(
          child: SizedBox(
            height: _kSegmentH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Rising particles (completed only)
                if (_isCompleted)
                  AnimatedBuilder(
                    animation: _particleCtrl,
                    builder: (_, _) => Stack(
                      children: [
                        _buildParticle(centerX, _particleCtrl.value, 0.00),
                        _buildParticle(centerX, _particleCtrl.value, 0.38),
                        _buildParticle(centerX, _particleCtrl.value, 0.67),
                      ],
                    ),
                  ),

                // Stone trail connector
                if (!widget.isLast)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _glowCtrl,
                      builder: (_, _) => CustomPaint(
                        painter: _StoneTrailPainter(
                          startX: centerX,
                          endX: nextCenterX,
                          nodeSize: nodeSize,
                          segmentHeight: _kSegmentH,
                          nodeTopPad: _kNodeTopPad,
                          isCompleted: _isCompleted,
                          glowProgress: _isCompleted ? _glowCtrl.value : -1,
                          seed: _seed,
                        ),
                      ),
                    ),
                  ),

                // Water ripple burst — expands from active pad periodically
                if (_isActive)
                  AnimatedBuilder(
                    animation: Listenable.merge([_rippleCtrl, _floatCtrl]),
                    builder: (_, _) {
                      final floatY = math.sin(_floatCtrl.value * math.pi) * 5.0;
                      const rippleSize = _kActiveNodeSize + 44.0;
                      return Positioned(
                        top: _kNodeTopPad - 22 + floatY,
                        left: centerX - rippleSize / 2,
                        child: _WaterRipple(
                          progress: _rippleCtrl.value,
                          size: rippleSize,
                        ),
                      );
                    },
                  ),

                // Gentle pulse halo (active, floats with node)
                if (_isActive)
                  AnimatedBuilder(
                    animation: _floatCtrl,
                    builder: (_, _) {
                      const pulseSize = _kActiveNodeSize + 48.0;
                      final floatY = math.sin(_floatCtrl.value * math.pi) * 5.0;
                      return Positioned(
                        top: _kNodeTopPad - 24 + floatY,
                        left: centerX - pulseSize / 2,
                        child: const _MultiPulse(size: pulseSize),
                      );
                    },
                  ),

                // Active lily pad — floats
                if (_isActive)
                  AnimatedBuilder(
                    animation: _floatCtrl,
                    builder: (_, child) {
                      final floatY = math.sin(_floatCtrl.value * math.pi) * 5.0;
                      return Positioned(
                        top: _kNodeTopPad + floatY,
                        left: centerX - _kActiveNodeSize / 2,
                        child: child!,
                      );
                    },
                    child: Semantics(
                      button: true,
                      label: _semanticLabel,
                      // The pad's emoji/badges are Text/Icon children that
                      // would otherwise leak their own raw content ("🎯",
                      // "+25") into the announcement alongside this label —
                      // exclude them so only the one composed label reads.
                      excludeSemantics: true,
                      child: PressableScale(
                        scale: 0.96,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onTap();
                          },
                          child: _ActiveLilyPad(
                            node: widget.node as ActivePathNode,
                            size: _kActiveNodeSize,
                            seed: _seed,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Past lily pad (completed / missed / locked) — always
                // tappable: completed opens details, missed/locked show a
                // friendly explanatory dialog (handled by widget.onTap).
                if (!_isActive)
                  Positioned(
                    top: _kNodeTopPad,
                    left: centerX - _kNodeSize / 2,
                    child: Semantics(
                      button: true,
                      label: _semanticLabel,
                      // Same reasoning as the active pad above — the emoji,
                      // "+XP" badge, and check-mark icon inside are decorative
                      // to a screen reader once the label already says
                      // "completed"/"missed"/"locked".
                      excludeSemantics: true,
                      child: PressableScale(
                        scale: 0.96,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap();
                            },
                            customBorder: const CircleBorder(),
                            child: _PastLilyPad(
                              node: widget.node,
                              size: _kNodeSize,
                              seed: _seed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Date label
                Positioned(
                  top: _kNodeTopPad + nodeSize + 8,
                  left: centerX - 54,
                  width: 108,
                  child: _NodeLabel(node: widget.node),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticle(double centerX, double t, double phase) {
    final p = ((t + phase) % 1.0);
    final fadeIn = p < 0.18 ? p / 0.18 : 1.0;
    final fadeOut = p > 0.70 ? (1.0 - p) / 0.30 : 1.0;
    final opacity = (fadeIn * fadeOut * 0.50).clamp(0.0, 1.0);
    final topY = _kSegmentH * 0.82 - p * _kSegmentH * 0.72;
    final xJitter = math.sin(p * math.pi * 2.8 + phase * 9) * 12;

    return Positioned(
      top: topY,
      left: centerX + xJitter - 3,
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _lilyActiveLight,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _lilyActive.withValues(alpha: 0.6),
                blurRadius: 5,
              ),
            ],
          ),
          child: const SizedBox(width: 5, height: 5),
        ),
      ),
    );
  }
}

// ── Active lily pad ───────────────────────────────────────────────────────────

class _ActiveLilyPad extends StatelessWidget {
  const _ActiveLilyPad({
    required this.node,
    required this.size,
    required this.seed,
  });
  final ActivePathNode node;
  final double size;
  final double seed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _LilyPadPainter(state: _PadState.active, seed: seed),
          ),
          Text(
            node.challenge?.emoji ?? '🎯',
            style: TextStyle(fontSize: size * 0.27),
          ),
        ],
      ),
    );
  }
}

// ── Past lily pad (completed / missed) ───────────────────────────────────────

class _PastLilyPad extends ConsumerStatefulWidget {
  const _PastLilyPad({
    required this.node,
    required this.size,
    required this.seed,
  });
  final PathNode node;
  final double size;
  final double seed;

  @override
  ConsumerState<_PastLilyPad> createState() => _PastLilyPadState();
}

class _PastLilyPadState extends ConsumerState<_PastLilyPad>
    with TickerProviderStateMixin {
  late final AnimationController _bounceCtrl;
  late final AnimationController _bloomCtrl;
  late final Animation<double> _scale;

  bool get _isCompleted => widget.node is CompletedPathNode;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 580),
    );
    _bloomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = CurvedAnimation(parent: _bounceCtrl, curve: Curves.elasticOut);

    if (ref.read(reducedMotionProvider)) {
      // Jump straight to the resting state instead of tweening in.
      _bounceCtrl.value = 1.0;
      if (_isCompleted) _bloomCtrl.value = 1.0;
    } else {
      _bounceCtrl.forward();
      if (_isCompleted) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (mounted) _bloomCtrl.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _bloomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Bloom burst (completed only)
          if (_isCompleted)
            AnimatedBuilder(
              animation: _bloomCtrl,
              builder: (_, _) => CustomPaint(
                size: Size(size, size),
                painter: _BloomPainter(progress: _bloomCtrl.value),
              ),
            ),
          ScaleTransition(
            scale: _scale,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(size, size),
                    painter: _LilyPadPainter(
                      state: _isCompleted
                          ? _PadState.completed
                          : _PadState.locked,
                      seed: widget.seed,
                    ),
                  ),
                  if (_isCompleted) ...[
                    Text(
                      (widget.node as CompletedPathNode)
                          .completion
                          .challengeEmoji,
                      style: TextStyle(fontSize: size * 0.26),
                    ),
                    Positioned(
                      bottom: size * 0.06,
                      left: size * 0.04,
                      child: _XpBadge(
                        xp: (widget.node as CompletedPathNode)
                            .completion
                            .xpAwarded,
                      ),
                    ),
                    Positioned(
                      bottom: size * 0.06,
                      right: size * 0.04,
                      child: const _CheckBadge(),
                    ),
                  ] else
                    Text('🔒', style: TextStyle(fontSize: size * 0.30)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lily pad state enum ───────────────────────────────────────────────────────

enum _PadState { active, completed, locked }

// ── Lily pad painter — organic layered circle ─────────────────────────────────

class _LilyPadPainter extends CustomPainter {
  const _LilyPadPainter({required this.state, required this.seed});

  final _PadState state;
  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final cx = size.width / 2;
    final cy = size.height / 2;
    switch (state) {
      case _PadState.active:
        _paintActive(canvas, cx, cy, r);
      case _PadState.completed:
        _paintCompleted(canvas, cx, cy, r);
      case _PadState.locked:
        _paintLocked(canvas, cx, cy, r);
    }
  }

  void _paintActive(Canvas canvas, double cx, double cy, double r) {
    // Drop shadow
    canvas.drawPath(
      _buildLilyPadPath(cx, cy + 7, r * 0.92, seed),
      Paint()
        ..color = _lilyActiveDark.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Ambient glow — kept subtle (12-18% spec range) so it reads as a soft
    // halo rather than competing with the pad's own saturated fill color.
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.97, seed),
      Paint()
        ..color = _lilyActive.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    // Outer dark rim
    final outer = _buildLilyPadPath(cx, cy, r * 0.92, seed);
    canvas.drawPath(outer, Paint()..color = _lilyActiveDark);
    // Mid bright ring
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.79, seed * 0.88),
      Paint()..color = _lilyActive,
    );
    // Inner light pool
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.52,
      Paint()..color = _lilyActiveLight,
    );
    // Radial veins
    _paintVeins(
      canvas,
      cx,
      cy,
      r * 0.88,
      _lilyActiveDark.withValues(alpha: 0.38),
    );
    // Characteristic V-notch
    _paintNotch(canvas, cx, cy, r * 0.92, seed);
    // Specular highlight
    canvas.drawCircle(
      Offset(cx - r * 0.10, cy - r * 0.14),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  void _paintCompleted(Canvas canvas, double cx, double cy, double r) {
    // Shadow
    canvas.drawPath(
      _buildLilyPadPath(cx, cy + 5, r * 0.90, seed),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Gold glow — subdued; the crisp stroke outline below does the primary
    // "completed" signaling, so this stays a faint lift rather than a glow.
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.95, seed),
      Paint()
        ..color = _lilyGold.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final outer = _buildLilyPadPath(cx, cy, r * 0.90, seed);
    canvas.drawPath(outer, Paint()..color = _lilyCompleted);
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.76, seed * 0.88),
      Paint()..color = _lilyCompletedLight.withValues(alpha: 0.78),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.50,
      Paint()..color = _lilyCompletedLight,
    );
    _paintVeins(
      canvas,
      cx,
      cy,
      r * 0.86,
      _lilyCompleted.withValues(alpha: 0.40),
    );
    _paintNotch(canvas, cx, cy, r * 0.90, seed);
    // Gold outline
    canvas.drawPath(
      outer,
      Paint()
        ..color = _lilyGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
    // Secondary inner gold ring
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.76, seed * 0.88),
      Paint()
        ..color = _lilyGold.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintLocked(Canvas canvas, double cx, double cy, double r) {
    // Shadow
    canvas.drawPath(
      _buildLilyPadPath(cx, cy + 4, r * 0.86, seed),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final outer = _buildLilyPadPath(cx, cy, r * 0.86, seed);
    canvas.drawPath(outer, Paint()..color = _lilyLocked);
    canvas.drawPath(
      _buildLilyPadPath(cx, cy, r * 0.68, seed * 0.88),
      Paint()..color = _lilyLockedLight.withValues(alpha: 0.55),
    );
    _paintVeins(canvas, cx, cy, r * 0.82, Colors.white.withValues(alpha: 0.12));
  }

  void _paintVeins(Canvas canvas, double cx, double cy, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const count = 7;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2 + seed * 0.08;
      final midX = cx + r * 0.50 * math.cos(angle + 0.14);
      final midY = cy + r * 0.50 * math.sin(angle + 0.14);
      final endX = cx + r * math.cos(angle);
      final endY = cy + r * math.sin(angle);
      canvas.drawPath(
        Path()
          ..moveTo(cx, cy)
          ..quadraticBezierTo(midX, midY, endX, endY),
        paint,
      );
    }
  }

  void _paintNotch(Canvas canvas, double cx, double cy, double r, double seed) {
    final angle = -math.pi / 2 + seed * 0.04;
    canvas.drawPath(
      Path()
        ..moveTo(
          cx + r * 0.13 * math.cos(angle + 0.20),
          cy + r * 0.13 * math.sin(angle + 0.20),
        )
        ..lineTo(cx, cy)
        ..lineTo(
          cx + r * 0.13 * math.cos(angle - 0.20),
          cy + r * 0.13 * math.sin(angle - 0.20),
        ),
      Paint()
        ..color = _lilyActiveDark.withValues(alpha: 0.55)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LilyPadPainter old) =>
      old.state != state || old.seed != seed;
}

// ── Water ripple — elliptical expanding rings ─────────────────────────────────

class _WaterRipple extends StatelessWidget {
  const _WaterRipple({required this.progress, required this.size});
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) {
      return SizedBox(width: size, height: size);
    }
    return CustomPaint(
      size: Size(size, size),
      painter: _WaterRipplePainter(progress: progress),
      child: SizedBox(width: size, height: size),
    );
  }
}

class _WaterRipplePainter extends CustomPainter {
  const _WaterRipplePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final phase = i * 0.22;
      final t = ((progress + phase) % 1.0).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final eased = Curves.easeOut.transform(t);
      final r = maxR * 0.25 + eased * maxR * 0.75;
      final opacity = (1.0 - eased) * 0.55;
      // Elliptical — real water ripples are wider than tall
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: r * 2.0,
          height: r * 1.25,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaterRipplePainter old) =>
      old.progress != progress;
}

// ── Bloom burst — petal-like sparkle for completed nodes ─────────────────────

class _BloomPainter extends CustomPainter {
  const _BloomPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    final eased = Curves.easeOut.transform(progress);
    final opacity = (1.0 - eased).clamp(0.0, 1.0);

    // Gold petals
    const petalCount = 8;
    final goldPaint = Paint()
      ..color = _lilyGold.withValues(alpha: opacity * 0.88);
    for (var i = 0; i < petalCount; i++) {
      final angle = (i / petalCount) * 2 * math.pi - math.pi / 2;
      final dist = maxR * 0.28 + eased * maxR * 0.95;
      final pos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );
      canvas.drawCircle(pos, (1 - eased) * 5.5 + 1.5, goldPaint);
    }
    // White inner sparkles
    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.72);
    for (var i = 0; i < petalCount; i++) {
      final angle = (i / petalCount) * 2 * math.pi;
      final dist = maxR * 0.18 + eased * maxR * 0.55;
      final pos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );
      canvas.drawCircle(pos, (1 - eased) * 3.5 + 0.5, whitePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BloomPainter old) => old.progress != progress;
}

// ── Multi-pulse — gentle glow rings around active pad ────────────────────────

class _MultiPulse extends ConsumerStatefulWidget {
  const _MultiPulse({required this.size});
  final double size;

  @override
  ConsumerState<_MultiPulse> createState() => _MultiPulseState();
}

class _MultiPulseState extends ConsumerState<_MultiPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      // Soft breathing pace — one full pulse every ~3s, within the 2.8-3.2s
      // spec range (not the snappier ~2s of a generic loading pulse).
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (!ref.read(reducedMotionProvider)) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ref.watch(reducedMotionProvider);
    if (reduceMotion) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          children: [
            _ring(_ctrl.value, 0.00),
            _ring(_ctrl.value, 0.34),
            _ring(_ctrl.value, 0.68),
          ],
        ),
      ),
    );
  }

  Widget _ring(double t, double phase) {
    final phasedT = Curves.easeOut.transform(((t + phase) % 1.0));
    final scale = 1.0 + phasedT * 0.62;
    // Glow opacity spec: 12-18% peak, decaying to 0 as the ring expands.
    final opacity = (1.0 - phasedT) * 0.18;
    return Transform.scale(
      scale: scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _lilyActive.withValues(alpha: opacity),
            width: 2.2,
          ),
        ),
        child: SizedBox(width: widget.size, height: widget.size),
      ),
    );
  }
}

// ── Stone trail painter — stepping stones along bezier curve ─────────────────

class _StoneTrailPainter extends CustomPainter {
  const _StoneTrailPainter({
    required this.startX,
    required this.endX,
    required this.nodeSize,
    required this.segmentHeight,
    required this.nodeTopPad,
    required this.isCompleted,
    required this.seed,
    this.glowProgress = -1,
  });

  final double startX, endX, nodeSize, segmentHeight, nodeTopPad, seed;
  final bool isCompleted;
  final double glowProgress;

  // 3 stones equally spaced along the arc.
  static const _stoneFracs = [0.25, 0.50, 0.75];

  @override
  void paint(Canvas canvas, Size size) {
    final startY = nodeTopPad + nodeSize + 18;
    final endY = segmentHeight - 24;

    final p0 = Offset(startX, startY);
    final p3 = Offset(endX, endY);
    final dy = endY - startY;
    final p1 = Offset(startX, startY + dy * 0.40);
    final p2 = Offset(endX, startY + dy * 0.60);

    final tValues = _arcLengthTs(p0, p1, p2, p3, _stoneFracs);

    for (var i = 0; i < tValues.length; i++) {
      final pos = _cubicBezier(p0, p1, p2, p3, tValues[i]);
      const r = 20.0; // uniform size, larger than before
      _drawStone(canvas, pos, r);
    }

    if (glowProgress >= 0 && isCompleted) {
      _drawGlowDot(canvas, _cubicBezier(p0, p1, p2, p3, glowProgress));
    }
  }

  // Places stones at explicit arc-length fractions (0.0–1.0) so they can be
  // biased toward either end of the connector.
  List<double> _arcLengthTs(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    List<double> fracs,
  ) {
    const samples = 64;
    final cumLen = <double>[0.0];
    var prev = p0;
    for (var i = 1; i <= samples; i++) {
      final cur = _cubicBezier(p0, p1, p2, p3, i / samples);
      cumLen.add(cumLen.last + (cur - prev).distance);
      prev = cur;
    }
    final total = cumLen.last;

    final result = <double>[];
    for (final frac in fracs) {
      final target = total * frac;
      var lo = 0;
      var hi = samples;
      while (lo < hi - 1) {
        final mid = (lo + hi) ~/ 2;
        if (cumLen[mid] < target) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final span = cumLen[hi] - cumLen[lo];
      final f = span > 0 ? (target - cumLen[lo]) / span : 0.0;
      result.add((lo + f) / samples);
    }
    return result;
  }

  Offset _cubicBezier(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1 - t;
    return Offset(
      u * u * u * p0.dx +
          3 * u * u * t * p1.dx +
          3 * u * t * t * p2.dx +
          t * t * t * p3.dx,
      u * u * u * p0.dy +
          3 * u * u * t * p1.dy +
          3 * u * t * t * p2.dy +
          t * t * t * p3.dy,
    );
  }

  void _drawStone(Canvas canvas, Offset center, double r) {
    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, r * 0.55),
        width: r * 2.0,
        height: r * 0.60,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Stone body — circular, per design spec.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = isCompleted
            ? _stoneBase
            : _stoneShadow.withValues(alpha: 0.50),
    );
    // Top highlight
    canvas.drawCircle(
      Offset(center.dx - r * 0.16, center.dy - r * 0.20),
      r * 0.55,
      Paint()
        ..color = isCompleted
            ? _stoneHighlight
            : _stoneHighlight.withValues(alpha: 0.28),
    );
    // Bottom shadow crescent — thin inner arc, stays within the stone's edge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.78),
      0.35,
      math.pi - 0.70,
      false,
      Paint()
        ..color = _stoneShadow.withValues(alpha: isCompleted ? 0.35 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.30
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawGlowDot(Canvas canvas, Offset center) {
    canvas.drawCircle(
      center,
      13,
      Paint()
        ..color = _stoneGlow.withValues(alpha: 0.38)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      5.5,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );
    canvas.drawCircle(center, 2.5, Paint()..color = _stoneGlow);
  }

  @override
  bool shouldRepaint(covariant _StoneTrailPainter old) =>
      old.startX != startX ||
      old.endX != endX ||
      old.isCompleted != isCompleted ||
      old.glowProgress != glowProgress;
}

// ── Badge widgets ─────────────────────────────────────────────────────────────

class _XpBadge extends StatelessWidget {
  const _XpBadge({required this.xp});
  final int xp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.gradientGold,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          '+$xp',
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _lilyActive,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Padding(
        padding: EdgeInsets.all(2.5),
        child: Icon(Icons.check_rounded, size: 11, color: Colors.white),
      ),
    );
  }
}

// ── Day label — shows "Day N" only, never calendar dates ─────────────────────

class _NodeLabel extends StatelessWidget {
  const _NodeLabel({required this.node});
  final PathNode node;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    final isActive = node is ActivePathNode;
    final isCompleted = node is CompletedPathNode;
    final dayLabel = 'Day ${node.dayNumber}';

    if (isActive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: _lilyActive.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                'TODAY',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _lilyActive,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            dayLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _lilyActive,
            ),
          ),
        ],
      );
    }

    return Text(
      dayLabel,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: isCompleted ? _lilyCompletedLight : muted,
      ),
    );
  }
}
