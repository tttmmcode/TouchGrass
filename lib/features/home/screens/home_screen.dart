import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../companions/companion.dart';
import '../../../companions/companion_widget.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_names.dart';
import '../../../core/services/error_service.dart';
import '../../../models/user_model.dart';
import '../../../models/weather_model.dart';
import '../../../providers/assignment_providers.dart';
import '../../../providers/challenge_providers.dart';
import '../../../providers/companion_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../providers/weather_providers.dart';
import '../../../services/analytics_service.dart';
import '../../../services/perf_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_elevation.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/loading_widgets.dart';
import '../../../widgets/pressable_scale.dart';
import '../widgets/challenge_node.dart';
import '../widgets/todays_challenge_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Trace? _loadTrace;
  bool _traceCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadTrace = PerfService.startTrace(PerfService.traceChallengeLoad);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(assignmentInitProvider);
    final pathAsync = ref.watch(homePathNodesProvider);

    if (!_traceCompleted && pathAsync.hasValue) {
      _traceCompleted = true;
      _loadTrace?.stop().ignore();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: pathAsync.when(
        data: (nodes) => _AdventureTrail(nodes: nodes),
        loading: () => const _TrailLoading(),
        error: (e, _) => _TrailError(
          message: ErrorService.friendlyMessage(e),
          onRetry: () {
            ref.invalidate(todaysChallengeProvider);
            ref.invalidate(recentCompletionsProvider);
          },
        ),
      ),
    );
  }
}

// ── Adventure trail — full-screen experience ──────────────────────────────────

class _AdventureTrail extends StatefulWidget {
  const _AdventureTrail({required this.nodes});
  final List<PathNode> nodes;

  @override
  State<_AdventureTrail> createState() => _AdventureTrailState();
}

class _AdventureTrailState extends State<_AdventureTrail> {
  final _scrollCtrl = ScrollController();
  bool _challengeViewLogged = false;

  // Guards the active node's camera-entry tap against a rapid double-tap
  // pushing two camera routes onto the stack. Resets once the pushed route
  // is popped.
  bool _navigatingToCamera = false;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _maybLogChallengeViewed() {
    if (_challengeViewLogged) return;
    final today = widget.nodes.isNotEmpty ? widget.nodes.first : null;
    if (today is! ActivePathNode) return;
    final challenge = today.challenge;
    if (challenge == null) return;
    _challengeViewLogged = true;
    AnalyticsService.logChallengeViewed(
      challengeId: challenge.challengeId,
      category: challenge.challengeCategory.displayName,
    );
  }

  void _onNodeTap(BuildContext context, PathNode node) {
    if (node is CompletedPathNode) {
      context.pushNamed(
        'challengeDetail',
        pathParameters: {'id': node.completion.challengeId},
        extra: node.completion,
      );
    } else if (node is ActivePathNode) {
      if (_navigatingToCamera) return;
      _navigatingToCamera = true;
      context.pushNamed('camera').then((_) {
        if (mounted) setState(() => _navigatingToCamera = false);
      });
    } else if (node is LockedPathNode) {
      final todayDayNumber = widget.nodes.first.dayNumber;
      final daysAway = node.dayNumber - todayDayNumber;
      _showTrailInfoDialog(
        context,
        emoji: '🔒',
        title: 'Day ${node.dayNumber} is locked',
        message: daysAway == 1
            ? "This adventure unlocks tomorrow — come back after you've "
                "finished today's challenge!"
            : "This adventure unlocks in $daysAway days. Keep completing "
                'daily challenges to reach it!',
      );
    } else if (node is MissedPathNode) {
      _showTrailInfoDialog(
        context,
        emoji: '🌱',
        title: 'Day ${node.dayNumber} was missed',
        message: 'Every explorer has an off day — it happens. Focus on '
            "today's challenge and keep your adventure moving forward!",
      );
    }
  }

  void _showTrailInfoDialog(
    BuildContext context, {
    required String emoji,
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: AppSpacing.emojiSm)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) return const _EmptyState();
    _maybLogChallengeViewed();

    final todayNode = widget.nodes.first;
    final completedCount =
        widget.nodes.whereType<CompletedPathNode>().length;

    return Stack(
      children: [
        // Parallax background — layers drift at different scroll speeds.
        AnimatedBuilder(
          animation: _scrollCtrl,
          builder: (_, _) {
            final offset =
                _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
            return Positioned.fill(
              child: _LandscapeBackground(scrollOffset: offset),
            );
          },
        ),
        const Positioned.fill(
          child: IgnorePointer(child: _AmbientLeaves()),
        ),
        const Positioned.fill(
          child: IgnorePointer(child: _PollenSystem()),
        ),
        CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: AppSpacing.sm),
                    _TrailHeader(),
                  ],
                ),
              ),
            ),
            if (todayNode is ActivePathNode)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.sm,
                  AppSpacing.screenHorizontal,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _FadeSlideIn(
                    delay: Duration(milliseconds: 30),
                    child: RepaintBoundary(child: _TrailCompanion()),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.lg,
                AppSpacing.screenHorizontal,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: TodaysChallengeCard(todayNode: todayNode),
                ),
              ),
            ),
            if (widget.nodes.length > 1)
              SliverToBoxAdapter(
                child: _TrailJunction(completedCount: completedCount),
              ),
            if (widget.nodes.length > 1)
              SliverList.builder(
                itemCount: widget.nodes.length - 1,
                itemBuilder: (context, listIndex) {
                  final nodeIndex = listIndex + 1;
                  final node = widget.nodes[nodeIndex];
                  return _FadeSlideIn(
                    delay: Duration(milliseconds: listIndex * 50),
                    child: RepaintBoundary(
                      child: ChallengePathSegment(
                        key: ValueKey(node.date),
                        node: node,
                        index: nodeIndex,
                        isLast: nodeIndex == widget.nodes.length - 1,
                        onTap: () => _onNodeTap(context, node),
                      ),
                    ),
                  );
                },
              ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: AppSpacing.xxxxl),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Landscape background — layered painted scene ──────────────────────────────

class _LandscapeBackground extends ConsumerStatefulWidget {
  const _LandscapeBackground({this.scrollOffset = 0});
  final double scrollOffset;

  @override
  ConsumerState<_LandscapeBackground> createState() =>
      _LandscapeBackgroundState();
}

class _LandscapeBackgroundState extends ConsumerState<_LandscapeBackground>
    with TickerProviderStateMixin {
  late final AnimationController _cloudCtrl;
  late final AnimationController _ambientCtrl;
  // Persists across the many ephemeral _LandscapePainter instances created
  // each animation frame, so the expensive static-layer Picture it records
  // survives from one frame to the next instead of being rebuilt every time.
  final _staticLayerCache = _StaticLayerCache();

  @override
  void initState() {
    super.initState();
    _cloudCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    );
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 80),
    );
    if (!ref.read(reducedMotionProvider)) {
      _cloudCtrl.repeat();
      _ambientCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _cloudCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = ref.watch(reducedMotionProvider);
    if (reduceMotion) {
      if (_cloudCtrl.isAnimating) _cloudCtrl.stop();
      if (_ambientCtrl.isAnimating) _ambientCtrl.stop();
    } else {
      if (!_cloudCtrl.isAnimating) _cloudCtrl.repeat();
      if (!_ambientCtrl.isAnimating) _ambientCtrl.repeat();
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_cloudCtrl, _ambientCtrl]),
      builder: (_, _) => RepaintBoundary(
        child: CustomPaint(
          painter: _LandscapePainter(
            cloudProgress: _cloudCtrl.value,
            ambientProgress: _ambientCtrl.value,
            scrollOffset: widget.scrollOffset,
            isDark: isDark,
            staticCache: _staticLayerCache,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Caches the recorded [ui.Picture] for _LandscapePainter's static layers
/// (mountains/forest/hills/foreground — everything that depends only on
/// size/isDark/scrollOffset, never on the animated cloud/ambient progress),
/// keyed on the inputs it was built from. Lives on _LandscapeBackgroundState
/// so it survives across the many ephemeral painter instances created each
/// animation frame.
class _StaticLayerCache {
  ui.Picture? picture;
  Size? size;
  bool? isDark;
  double? scrollOffset;
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter({
    required this.cloudProgress,
    required this.ambientProgress,
    required this.scrollOffset,
    required this.isDark,
    required this.staticCache,
  });

  final double cloudProgress;
  final double ambientProgress;
  final double scrollOffset;
  final bool isDark;
  final _StaticLayerCache staticCache;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    if (!isDark) _paintSunRays(canvas, size);

    // Far mountains → mid mountains → mid forest → near hills → foreground:
    // none of these depend on cloudProgress/ambientProgress, only on
    // (size, isDark, scrollOffset) — reconstructing their trig-heavy Paths
    // on every animation frame is pure waste, so they're recorded once into
    // a cached Picture and replayed instead. Grass/flowers/clouds/birds/haze
    // stay live below, unchanged, preserving the exact original z-order.
    canvas.drawPicture(_staticLayersPicture(size));

    _withShift(canvas, scrollOffset * 0.22, () => _paintGrassBlades(canvas, size));
    _withShift(canvas, scrollOffset * 0.22, () => _paintFlowers(canvas, size));

    if (!isDark) _paintClouds(canvas, size);
    _paintBirds(canvas, size);
    if (!isDark) _paintAtmosphericHaze(canvas, size);
  }

  ui.Picture _staticLayersPicture(Size size) {
    final cache = staticCache;
    if (cache.picture != null &&
        cache.size == size &&
        cache.isDark == isDark &&
        cache.scrollOffset == scrollOffset) {
      return cache.picture!;
    }

    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);
    _withShift(recordCanvas, scrollOffset * 0.03, () => _paintFarMountains(recordCanvas, size));
    _withShift(recordCanvas, scrollOffset * 0.07, () => _paintMidMountains(recordCanvas, size));
    _withShift(recordCanvas, scrollOffset * 0.11, () => _paintMidForest(recordCanvas, size));
    _withShift(recordCanvas, scrollOffset * 0.16, () => _paintNearHills(recordCanvas, size));
    _withShift(recordCanvas, scrollOffset * 0.22, () => _paintForeground(recordCanvas, size));
    final picture = recorder.endRecording();

    cache
      ..picture = picture
      ..size = size
      ..isDark = isDark
      ..scrollOffset = scrollOffset;
    return picture;
  }

  void _withShift(Canvas canvas, double dy, VoidCallback paint) {
    canvas.save();
    canvas.translate(0, -dy.clamp(0.0, 130.0));
    paint();
    canvas.restore();
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = (isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF04091C),
                    Color(0xFF07102E),
                    Color(0xFF0C1A42),
                    Color(0xFF112248),
                  ],
                  stops: [0.0, 0.3, 0.65, 1.0],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF5BB5D8),
                    Color(0xFF84CCEB),
                    Color(0xFFB0E5D5),
                    Color(0xFFC8ECD4),
                  ],
                  stops: [0.0, 0.32, 0.68, 1.0],
                ))
          .createShader(rect);
    canvas.drawRect(rect, paint);

    if (isDark) _paintMoonAndStars(canvas, size);
  }

  void _paintMoonAndStars(Canvas canvas, Size size) {
    // Moon — crescent at upper-left
    final moonX = size.width * 0.22;
    final moonY = size.height * 0.09;
    const moonR = 18.0;

    // Soft glow halo
    canvas.drawCircle(
      Offset(moonX, moonY),
      moonR * 2.2,
      Paint()
        ..color = const Color(0xFFE8F0FF).withValues(alpha: 0.07)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Full disc
    canvas.drawCircle(
      Offset(moonX, moonY),
      moonR,
      Paint()..color = const Color(0xFFECF0FF),
    );
    // Crescent mask — slightly offset disc removes part of moon
    canvas.drawCircle(
      Offset(moonX + moonR * 0.55, moonY - moonR * 0.12),
      moonR * 0.88,
      Paint()..color = const Color(0xFF07102E),
    );

    // Stars — scattered across upper sky
    const starSpecs = [
      (0.06, 0.035, 1.4), (0.15, 0.055, 1.0), (0.34, 0.02,  1.6),
      (0.44, 0.06,  1.1), (0.58, 0.03,  1.3), (0.68, 0.075, 0.9),
      (0.78, 0.025, 1.5), (0.88, 0.055, 1.2), (0.95, 0.04,  1.0),
      (0.10, 0.14,  0.8), (0.28, 0.12,  1.1), (0.50, 0.16,  0.9),
      (0.72, 0.13,  1.3), (0.90, 0.17,  1.0), (0.38, 0.22,  0.8),
      (0.62, 0.20,  1.2), (0.82, 0.24,  0.7),
    ];

    final twinkle = math.sin(ambientProgress * 2 * math.pi * 3.0);
    final starPaint = Paint()..color = Colors.white;
    for (final (xFrac, yFrac, sz) in starSpecs) {
      final x = size.width * xFrac;
      final y = size.height * yFrac;
      final pulse = 1.0 + twinkle * 0.22 * math.sin(xFrac * 17 + yFrac * 31);
      final r = sz * pulse.abs().clamp(0.7, 1.5);
      final alpha = (0.55 + 0.40 * pulse.abs()).clamp(0.4, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        r,
        starPaint..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  void _paintSunRays(Canvas canvas, Size size) {
    // Soft diagonal rays emanating from upper-right
    final sunX = size.width * 0.78;
    final sunY = size.height * 0.08;
    const rayCount = 7;
    final rayPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(sunX, sunY),
        radius: size.width * 0.9,
      ));

    for (var i = 0; i < rayCount; i++) {
      final baseAngle = math.pi * 0.55 + (i / rayCount) * math.pi * 0.90;
      // Rays slowly sweep
      final sweep = ambientProgress * math.pi * 0.08;
      final angle = baseAngle + sweep;
      final halfWidth = 0.04 + (i % 3) * 0.018;
      final path = Path()
        ..moveTo(sunX, sunY)
        ..lineTo(
          sunX + math.cos(angle - halfWidth) * size.width * 1.4,
          sunY + math.sin(angle - halfWidth) * size.width * 1.4,
        )
        ..lineTo(
          sunX + math.cos(angle + halfWidth) * size.width * 1.4,
          sunY + math.sin(angle + halfWidth) * size.width * 1.4,
        )
        ..close();
      canvas.drawPath(path, rayPaint);
    }

    // Sun disc glow
    canvas.drawCircle(
      Offset(sunX, sunY),
      size.width * 0.11,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
  }

  void _paintFarMountains(Canvas canvas, Size size) {
    // Distant hazy range — blue-grey
    _drawSilhouette(
      canvas, size,
      baselineFrac: 0.40,
      ampFrac: 0.10,
      freq1: 1.8,
      freq2: 0.9,
      phase1: 0.4,
      phase2: 1.4,
      color: isDark ? const Color(0xFF0E1E38) : const Color(0xFF9DC4CE),
    );
  }

  void _paintMidMountains(Canvas canvas, Size size) {
    // Second mountain layer — slightly darker, more defined peaks
    _drawSilhouette(
      canvas, size,
      baselineFrac: 0.50,
      ampFrac: 0.115,
      freq1: 2.6,
      freq2: 1.3,
      phase1: 0.0,
      phase2: 0.8,
      color: isDark ? const Color(0xFF101C32) : const Color(0xFF7AA8B8),
    );
  }

  void _paintMidForest(Canvas canvas, Size size) {
    // Main treeline: abs(sin) for rounded tree-top silhouette
    final color = isDark ? const Color(0xFF0A1B10) : const Color(0xFF28604A);
    final paint = Paint()..color = color;
    final path = Path()..moveTo(0, size.height);
    final baseline = size.height * 0.615;
    final amp = size.height * 0.060;
    const steps = 320;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final t = x / size.width;
      final y = baseline
          - math.sin(t * math.pi * 8.0 + 0.3).abs() * amp
          - math.sin(t * math.pi * 4.0 + 1.1).abs() * amp * 0.45
          - math.sin(t * math.pi * 14.0 + 2.2).abs() * amp * 0.20;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);

    // Lighter canopy edge highlight
    if (!isDark) {
      final edgePaint = Paint()
        ..color = const Color(0xFF3A7A5C).withValues(alpha: 0.55)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      final edgePath = Path()..moveTo(0, baseline);
      for (var i = 0; i <= steps; i++) {
        final x = size.width * i / steps;
        final t = x / size.width;
        final y = baseline
            - math.sin(t * math.pi * 8.0 + 0.3).abs() * amp
            - math.sin(t * math.pi * 4.0 + 1.1).abs() * amp * 0.45
            - math.sin(t * math.pi * 14.0 + 2.2).abs() * amp * 0.20;
        edgePath.lineTo(x, y);
      }
      canvas.drawPath(edgePath, edgePaint);
    }
  }

  void _paintNearHills(Canvas canvas, Size size) {
    // Rolling foreground hills
    _drawSilhouette(
      canvas, size,
      baselineFrac: 0.725,
      ampFrac: 0.042,
      freq1: 3.8,
      freq2: 1.9,
      phase1: 1.2,
      phase2: 0.2,
      color: isDark ? const Color(0xFF0F2518) : const Color(0xFF3A8A62),
    );

    // Rock/stone accents along hills
    if (!isDark) {
      final stonePaint = Paint()..color = const Color(0xFF2D6A4A).withValues(alpha: 0.55);
      const stoneCount = 6;
      for (var i = 0; i < stoneCount; i++) {
        final xFrac = 0.05 + i * 0.16 + math.sin(i * 2.1) * 0.04;
        final x = size.width * xFrac;
        final hillY = size.height * 0.725
            - math.sin(xFrac * math.pi * 3.8 + 1.2) * size.height * 0.042
            - math.sin(xFrac * math.pi * 1.9 + 0.2) * size.height * 0.042 * 0.45;
        final rw = 6.0 + math.sin(i * 1.7) * 3.0;
        final rh = 4.0 + math.sin(i * 2.3) * 2.0;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, hillY + 2), width: rw * 2, height: rh),
          stonePaint,
        );
      }
    }
  }

  void _paintForeground(Canvas canvas, Size size) {
    // Main grass band
    _drawSilhouette(
      canvas, size,
      baselineFrac: 0.848,
      ampFrac: 0.016,
      freq1: 5.5,
      freq2: 2.8,
      phase1: 0.5,
      phase2: 1.7,
      color: isDark ? const Color(0xFF122C1D) : const Color(0xFF48AC7C),
    );
    // Rich dark strip at bottom
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.925, size.width, size.height * 0.075),
      Paint()..color = isDark
          ? const Color(0xFF0D201A)
          : const Color(0xFF2A6347),
    );
  }

  void _paintGrassBlades(Canvas canvas, Size size) {
    if (isDark) return;
    final bladeColor = const Color(0xFF3A9E68).withValues(alpha: 0.80);
    final darkBlade = const Color(0xFF236040).withValues(alpha: 0.70);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const count = 38;
    for (var i = 0; i < count; i++) {
      final xFrac = i / count + math.sin(i * 1.37) * 0.012;
      final x = size.width * xFrac;
      // Base on foreground top edge
      final baseY = size.height * 0.848
          - math.sin(xFrac * math.pi * 5.5 + 0.5) * size.height * 0.016
          - math.sin(xFrac * math.pi * 2.8 + 1.7) * size.height * 0.016 * 0.45;
      final h = 10.0 + math.sin(i * 2.11) * 6.0;
      // Gentle ambient sway
      final sway = math.sin(ambientProgress * 2 * math.pi * 2.0 + i * 0.42) * 2.5;
      paint.color = (i % 3 == 0) ? darkBlade : bladeColor;
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x + sway, baseY - h),
        paint,
      );
    }
  }

  void _paintFlowers(Canvas canvas, Size size) {
    if (isDark) return;
    // Small flower dots scattered along the foreground
    const flowers = [
      (0.06, 0.865, 0xFFFF8FAB), // pink
      (0.18, 0.858, 0xFFFFD166), // yellow
      (0.32, 0.862, 0xFFFF8FAB),
      (0.47, 0.860, 0xFFFFFFFF), // white
      (0.61, 0.856, 0xFFFFD166),
      (0.74, 0.864, 0xFFFF8FAB),
      (0.88, 0.859, 0xFFFFFFFF),
    ];

    for (final (xFrac, yFrac, colorHex) in flowers) {
      final x = size.width * xFrac;
      final y = size.height * yFrac;
      final color = Color(colorHex);
      // Petals
      const petalCount = 5;
      for (var p = 0; p < petalCount; p++) {
        final angle = (p / petalCount) * 2 * math.pi;
        canvas.drawCircle(
          Offset(x + math.cos(angle) * 3.5, y + math.sin(angle) * 3.5),
          2.0,
          Paint()..color = color.withValues(alpha: 0.88),
        );
      }
      // Center
      canvas.drawCircle(Offset(x, y), 2.2,
          Paint()..color = const Color(0xFFFFEA6A));
      // Stem
      canvas.drawLine(
        Offset(x, y + 2.5),
        Offset(x, y + 9),
        Paint()
          ..color = const Color(0xFF3A9E68).withValues(alpha: 0.75)
          ..strokeWidth = 1.0,
      );
    }
  }

  void _paintBirds(Canvas canvas, Size size) {
    // 3 small V-shaped silhouettes drift slowly across the sky
    const birdSpecs = [
      (0.10, 0.12, 0.55, 1.00), // (yFrac, startXFrac, speedMul, scaleMul)
      (0.07, 0.45, 0.38, 0.70),
      (0.15, 0.72, 0.65, 0.85),
    ];

    final birdColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.20);

    for (final (yFrac, startX, speed, scale) in birdSpecs) {
      final xFrac = (startX + ambientProgress * speed) % 1.1 - 0.05;
      final x = size.width * xFrac;
      final y = size.height * yFrac;
      final w = 8.0 * scale;
      final h = 4.0 * scale;
      // V-shape: two arcs meeting at center
      final path = Path()
        ..moveTo(x - w, y - h * 0.5)
        ..quadraticBezierTo(x - w * 0.5, y + h * 0.3, x, y)
        ..quadraticBezierTo(x + w * 0.5, y + h * 0.3, x + w, y - h * 0.5);
      canvas.drawPath(
        path,
        Paint()
          ..color = birdColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * scale
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintAtmosphericHaze(Canvas canvas, Size size) {
    // Subtle depth haze between mountain layers
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.38, size.width, size.height * 0.15),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFB8DDE8).withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(
          0,
          size.height * 0.38,
          size.width,
          size.height * 0.15,
        )),
    );
  }

  // Reusable helper — sine-wave silhouette filled to bottom edge.
  void _drawSilhouette(
    Canvas canvas,
    Size size, {
    required double baselineFrac,
    required double ampFrac,
    required double freq1,
    required double freq2,
    required double phase1,
    required double phase2,
    required Color color,
  }) {
    final paint = Paint()..color = color;
    final path = Path()..moveTo(0, size.height);
    final baseline = size.height * baselineFrac;
    final amp = size.height * ampFrac;
    const steps = 240;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final t = x / size.width;
      final y = baseline
          - math.sin(t * math.pi * freq1 + phase1) * amp
          - math.sin(t * math.pi * freq2 + phase2) * amp * 0.45;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintClouds(Canvas canvas, Size size) {
    // (yFrac, scale, speedMul, startXFrac, opacity)
    const clouds = [
      (0.06, 1.00, 1.00, 0.12, 0.86),
      (0.12, 0.58, 0.55, 0.55, 0.72),
      (0.04, 0.74, 0.75, 0.80, 0.80),
      (0.09, 0.44, 0.40, 0.30, 0.60),
    ];

    for (final (yFrac, scale, speed, startX, opacity) in clouds) {
      final xFrac = 1.1 - ((startX + cloudProgress * speed) % 1.2);
      final x = size.width * xFrac;
      final y = size.height * yFrac;
      _drawCloud(canvas, Offset(x, y), size.width * 0.12 * scale, opacity);
    }
  }

  void _drawCloud(Canvas canvas, Offset center, double r, double opacity) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    final puffs = [
      (Offset(-r * 0.50, r * 0.16), r * 0.28),
      (Offset(-r * 0.22, r * 0.02), r * 0.40),
      (Offset(r * 0.12, -r * 0.10), r * 0.44),
      (Offset(r * 0.46, r * 0.04), r * 0.32),
      (Offset(r * 0.70, r * 0.18), r * 0.20),
    ];
    for (final (offset, radius) in puffs) {
      canvas.drawCircle(center + offset, radius, paint);
    }
    // Soft shadow under cloud
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, r * 0.55),
        width: r * 1.8,
        height: r * 0.22,
      ),
      Paint()..color = Colors.black.withValues(alpha: opacity * 0.08),
    );
  }

  @override
  bool shouldRepaint(covariant _LandscapePainter old) =>
      old.cloudProgress != cloudProgress ||
      old.ambientProgress != ambientProgress ||
      old.scrollOffset != scrollOffset ||
      old.isDark != isDark;
}

// ── Ambient falling leaves — painted teardrop shapes ─────────────────────────

class _AmbientLeaves extends ConsumerStatefulWidget {
  const _AmbientLeaves();

  @override
  ConsumerState<_AmbientLeaves> createState() => _AmbientLeavesState();
}

class _AmbientLeavesState extends ConsumerState<_AmbientLeaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = ref.watch(reducedMotionProvider);
    if (reduceMotion) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => RepaintBoundary(
        child: CustomPaint(
          painter: _LeafPainter(progress: _ctrl.value, isDark: isDark),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// (phase, xStartFrac, xSwingPx, speedMul, halfSizePx, rotationCycles)
const _leafSpecs = [
  (0.00, 0.18, 28.0, 0.70, 7.0, 1.2),
  (0.22, 0.72, 22.0, 1.00, 5.5, -0.9),
  (0.45, 0.40, 36.0, 0.85, 6.5, 1.5),
  (0.67, 0.85, 18.0, 0.65, 5.0, -1.1),
  (0.83, 0.28, 26.0, 0.92, 6.0, 0.8),
];

class _LeafPainter extends CustomPainter {
  const _LeafPainter({required this.progress, required this.isDark});

  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark
        ? const Color(0xFF52B788).withValues(alpha: 0.35)
        : const Color(0xFF2D6A4F).withValues(alpha: 0.50);

    for (final (phase, xFrac, xSwing, speed, half, rotCycles) in _leafSpecs) {
      final t = (progress * speed + phase) % 1.0;

      // Fade in at top, fade out before loop reset
      final fadeIn = (t / 0.10).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - t) / 0.14).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut;
      if (opacity <= 0.01) continue;

      final x = size.width * xFrac + math.sin(t * 2 * math.pi * 1.6) * xSwing;
      final y = t * size.height * 1.08 - size.height * 0.04;
      final angle = t * 2 * math.pi * rotCycles;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      final paint = Paint()
        ..color = baseColor.withValues(alpha: baseColor.a * opacity)
        ..style = PaintingStyle.fill;

      // Teardrop leaf: two cubic bezier arcs meeting at tip and base
      final path = Path()
        ..moveTo(0, -half)
        ..cubicTo(half * 0.72, -half * 0.35, half * 0.72, half * 0.42, 0, half * 0.85)
        ..cubicTo(-half * 0.72, half * 0.42, -half * 0.72, -half * 0.35, 0, -half);

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) =>
      old.progress != progress || old.isDark != isDark;
}

// ── Floating pollen particles ─────────────────────────────────────────────────

class _PollenSystem extends ConsumerStatefulWidget {
  const _PollenSystem();

  @override
  ConsumerState<_PollenSystem> createState() => _PollenSystemState();
}

class _PollenSystemState extends ConsumerState<_PollenSystem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = ref.watch(reducedMotionProvider);
    if (reduceMotion) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => RepaintBoundary(
        child: CustomPaint(
          painter: _PollenPainter(progress: _ctrl.value, isDark: isDark),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// (phase, xStartFrac, xSwingPx, speedMul, radius)
const _pollenSpecs = [
  (0.00, 0.12, 14.0, 0.60, 1.8),
  (0.14, 0.38, 10.0, 0.80, 1.4),
  (0.28, 0.62, 18.0, 0.55, 2.0),
  (0.42, 0.82, 12.0, 0.70, 1.6),
  (0.56, 0.22, 16.0, 0.90, 1.5),
  (0.70, 0.52, 8.0,  0.65, 1.9),
  (0.84, 0.90, 14.0, 0.75, 1.7),
];

class _PollenPainter extends CustomPainter {
  const _PollenPainter({required this.progress, required this.isDark});
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark
        ? const Color(0xFFD4F0C0).withValues(alpha: 0.22)
        : const Color(0xFFFFF8DC).withValues(alpha: 0.70);

    for (final (phase, xFrac, xSwing, speed, r) in _pollenSpecs) {
      final t = (progress * speed + phase) % 1.0;
      final fadeIn = (t / 0.12).clamp(0.0, 1.0);
      final fadeOut = ((1.0 - t) / 0.12).clamp(0.0, 1.0);
      final opacity = fadeIn * fadeOut;
      if (opacity <= 0.01) continue;

      final x = size.width * xFrac + math.sin(t * 2 * math.pi * 1.2) * xSwing;
      // Float upward through ~70% of screen
      final y = size.height * 0.95 - t * size.height * 0.80;

      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = baseColor.withValues(alpha: baseColor.a * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PollenPainter old) =>
      old.progress != progress || old.isDark != isDark;
}

// ── Trail header ──────────────────────────────────────────────────────────────

class _TrailHeader extends ConsumerWidget {
  const _TrailHeader();

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static IconData _greetingIcon() {
    final h = DateTime.now().hour;
    if (h < 12) return Icons.wb_sunny_rounded;
    if (h < 17) return Icons.wb_cloudy_rounded;
    return Icons.nightlight_round;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final firstName =
        userAsync.valueOrNull?.displayName.split(' ').first ?? 'Explorer';

    final nameColor = isDark ? Colors.white : AppColors.forestGreenDark;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : AppColors.forestGreenDark.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _HeaderAvatar(),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(_greetingIcon(), size: 13, color: labelColor),
                        const SizedBox(width: 4),
                        Text(
                          _greeting(),
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      firstName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: nameColor,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const _HeaderWeather(),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Stats pills get their own row rather than sharing the header row
          // with the avatar/greeting/weather — on narrow phones, four
          // elements competing for one row left too little width for the
          // greeting text and risked truncation.
          userAsync.maybeWhen(
            data: (user) => user != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _CompactStatsPills(user: user),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          userAsync.maybeWhen(
            data: (user) => user != null
                ? _TrailXpBar(user: user, isDark: isDark)
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CompactStatsPills extends ConsumerWidget {
  const _CompactStatsPills({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppColors.gradientForest,
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: Text(
                '${user.level}',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Semantics(
          button: true,
          label: '${user.streak} day streak. Tap to view streak calendar.',
          excludeSemantics: true,
          child: PressableScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.pushNamed('streakCalendar'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Center(
                  child: DecoratedBox(
          decoration: BoxDecoration(
              gradient: AppColors.gradientStreak,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${user.streak}',
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

}


class _TrailXpBar extends ConsumerWidget {
  const _TrailXpBar({required this.user, required this.isDark});
  final UserModel user;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reducedMotion = ref.watch(reducedMotionProvider);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : AppColors.forestGreen.withValues(alpha: 0.12);
    final labelColor = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.forestGreenDark.withValues(alpha: 0.55);
    final target = user.levelProgress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${user.xpInCurrentLevel} / ${AppConstants.xpPerLevel} XP · Level ${user.level}',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration:
              reducedMotion ? Duration.zero : const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (_, progress, _) => LayoutBuilder(
            builder: (_, constraints) {
              final fillWidth = constraints.maxWidth * progress;
              return Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: SizedBox(height: 7, width: constraints.maxWidth),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientForest,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: SizedBox(height: 7, width: fillWidth),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Header avatar — leading profile photo, opens Profile tab ─────────────────

class _HeaderAvatar extends ConsumerWidget {
  const _HeaderAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final initials = (user?.displayName.isNotEmpty ?? false)
        ? user!.displayName[0].toUpperCase()
        : '?';

    return Semantics(
      button: true,
      label: 'Open profile',
      excludeSemantics: true,
      child: PressableScale(
        child: GestureDetector(
          onTap: () => context.go(RouteNames.profile),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: AppElevation.low,
            ),
            child: SizedBox(
              width: AppSpacing.avatarMd,
              height: AppSpacing.avatarMd,
              child: ClipOval(
                child: user?.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: user!.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => const ShimmerBox(),
                        errorWidget: (ctx, url, err) => InitialsAvatar(
                          initials: initials,
                          backgroundColor: AppColors.forestGreen,
                        ),
                      )
                    : InitialsAvatar(
                        initials: initials,
                        backgroundColor: AppColors.forestGreen,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header weather — compact icon + temperature only ─────────────────────────

class _HeaderWeather extends ConsumerWidget {
  const _HeaderWeather();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(weatherProvider).valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.forestGreen;

    return Semantics(
      button: true,
      label: weather != null
          ? 'Weather: ${weather.condition}, '
              '${weather.tempFahrenheitRounded} degrees. Tap for details.'
          : 'Weather unavailable',
      excludeSemantics: true,
      child: PressableScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showWeatherDetail(context, weather),
          child: ConstrainedBox(
            // Minimum 48x48 touch target even though the visible chip is
            // more compact.
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : AppColors.grassGreen.withValues(alpha: 0.28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: weather != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(weather.emoji,
                            style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 4),
                        Text(
                          '${weather.tempFahrenheitRounded}°',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      Icons.cloud_outlined,
                      size: AppSpacing.iconSm,
                      color: textColor.withValues(alpha: 0.55),
                    ),
            ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showWeatherDetail(BuildContext context, WeatherModel? weather) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(weather?.emoji ?? '🌥️',
                style: const TextStyle(fontSize: AppSpacing.emojiSm)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(weather?.condition ?? 'Weather unavailable'),
            ),
          ],
        ),
        content: Text(
          weather != null
              ? '${weather.tempFahrenheitRounded}°F · ${weather.outdoorAdvice}'
              : "We couldn't get your local weather. Check location "
                  'permission in Settings to enable it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ── Trail junction — section divider ─────────────────────────────────────────

class _TrailJunction extends StatelessWidget {
  const _TrailJunction({required this.completedCount});
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.grassGreenLight.withValues(alpha: 0.14)
        : AppColors.grassGreen.withValues(alpha: 0.12);
    final textColor = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.forestGreenDark.withValues(alpha: 0.7);

    // Section separation via spacing alone — no divider lines.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.xxl,
        AppSpacing.screenHorizontal,
        AppSpacing.md,
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  completedCount == 0
                      ? Icons.route_rounded
                      : Icons.check_circle_outline_rounded,
                  size: AppSpacing.iconTiny,
                  color: textColor,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  completedCount == 0
                      ? 'YOUR TRAIL'
                      : '$completedCount DONE',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Trail companion — a small guide beside today's challenge ─────────────────
//
// Only shown while today's challenge is still active (not yet completed),
// so it reads as "come on, let's go" rather than a stale leftover greeting.
// Message is chosen deterministically per day (not random) so it doesn't
// flicker between rebuilds, and only one companion is ever on screen.

class _TrailCompanion extends ConsumerWidget {
  const _TrailCompanion();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companionType = ref.watch(activeCompanionProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year))
        .inDays;
    final messages = user.streak >= 3
        ? companionType.streakMessages
        : companionType.encouragementMessages;
    final message = messages[dayOfYear % messages.length];

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: '${companionType.displayName} says: $message',
        excludeSemantics: true,
        child: CompanionView(
          type: companionType,
          mood: CompanionMood.encourage,
          size: AppSpacing.avatarLg,
          message: message,
        ),
      ),
    );
  }
}

// ── Staggered fade + slide entry ──────────────────────────────────────────────

class _FadeSlideIn extends StatefulWidget {
  const _FadeSlideIn({required this.child, required this.delay});
  final Widget child;
  final Duration delay;

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

// ── Loading ───────────────────────────────────────────────────────────────────

class _TrailLoading extends StatelessWidget {
  const _TrailLoading();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boneColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.5);

    return Stack(
      children: [
        const Positioned.fill(child: _LandscapeBackground()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: boneColor,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const SizedBox(height: 64, width: double.infinity),
                ),
                const SizedBox(height: AppSpacing.lg),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: boneColor,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: const SizedBox(height: 180, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error ─────────────────────────────────────────────────────────────────────

class _TrailError extends StatelessWidget {
  const _TrailError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _LandscapeBackground()),
        ErrorRetryView(message: message, onRetry: onRetry),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.forestGreenDark;
    return Stack(
      children: [
        const Positioned.fill(child: _LandscapeBackground()),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hiking_rounded,
                size: 64,
                color: AppColors.grassGreen,
              ),
              const SizedBox(height: 16),
              Text(
                'Your adventure begins soon!',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
