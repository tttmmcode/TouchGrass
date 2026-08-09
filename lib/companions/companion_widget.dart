import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_spacing.dart';
import 'companion.dart';
import 'companion_painter.dart';

// ── Public surface ─────────────────────────────────────────────────────────────

/// An animated companion character that reacts to mood.
///
/// Drop this anywhere you want a companion to appear. The widget self-manages
/// all animation controllers — no external setup required.
class CompanionView extends ConsumerStatefulWidget {
  const CompanionView({
    super.key,
    required this.type,
    required this.mood,
    this.size = 80,
    this.message,
    this.messageDelay = const Duration(milliseconds: 600),
    this.onMessageDone,
  });

  final CompanionType type;
  final CompanionMood mood;

  /// Canvas size in logical pixels (square).
  final double size;

  /// If set, a speech bubble appears after [messageDelay].
  final String? message;
  final Duration messageDelay;
  final VoidCallback? onMessageDone;

  @override
  ConsumerState<CompanionView> createState() => _CompanionViewState();
}

class _CompanionViewState extends ConsumerState<CompanionView>
    with TickerProviderStateMixin {
  // Idle breathing bob — always running
  late final AnimationController _bobCtrl;

  // Eye-blink — fires every ~4 s
  late final AnimationController _blinkCtrl;
  Timer? _blinkTimer;

  // Mood-specific motion (wave / bounce / cheer)
  late final AnimationController _moodCtrl;

  // Derived animation values exposed to the painter
  double get _bobOffset => math.sin(_bobCtrl.value * 2 * math.pi);
  double get _eyeOpen => _blinkCtrl.status == AnimationStatus.forward ||
          _blinkCtrl.status == AnimationStatus.reverse
      ? (1.0 - _blinkCtrl.value)
      : 1.0;
  double get _armAngle => _armAnim.value;
  double get _jumpOffset => _jumpAnim.value;
  double get _smileAmount => _smileAnim.value;

  late Animation<double> _armAnim;
  late Animation<double> _jumpAnim;
  late Animation<double> _smileAnim;

  bool _showBubble = false;

  @override
  void initState() {
    super.initState();

    _bobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (!ref.read(reducedMotionProvider)) _bobCtrl.repeat();

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );

    _moodCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _buildMoodAnimations();
    _applyMood(widget.mood);
    _scheduleBlink();

    if (widget.message != null) {
      Future<void>.delayed(widget.messageDelay, () {
        if (mounted) setState(() => _showBubble = true);
      });
    }
  }

  void _scheduleBlink() {
    const baseDelay = Duration(milliseconds: 3200);
    _blinkTimer = Timer(
      baseDelay + Duration(milliseconds: (math.Random().nextDouble() * 2000).toInt()),
      () async {
        if (!mounted) return;
        await _blinkCtrl.forward(from: 0);
        if (mounted) await _blinkCtrl.reverse();
        if (mounted) _scheduleBlink();
      },
    );
  }

  /// Starts the mood loop unless Reduce Motion is on, in which case
  /// [_moodCtrl] stays at its reset (rest-pose) value instead of looping
  /// forever — mirrors the [_bobCtrl] gating above.
  void _startMoodLoop({required Duration duration, bool reverse = false}) {
    _moodCtrl.duration = duration;
    if (ref.read(reducedMotionProvider)) return;
    _moodCtrl.repeat(reverse: reverse);
  }

  void _buildMoodAnimations() {
    _armAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
    _jumpAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
    _smileAnim = Tween<double>(begin: 0.5, end: 0.5).animate(_moodCtrl);
  }

  void _applyMood(CompanionMood mood) {
    _moodCtrl.stop();
    _moodCtrl.reset();

    switch (mood) {
      case CompanionMood.idle:
        _armAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
        _jumpAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
        _smileAnim = Tween<double>(begin: 0.5, end: 0.5).animate(_moodCtrl);

      case CompanionMood.wave:
        // Arm oscillates back and forth
        _armAnim = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 0.9), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: -0.4), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -0.4, end: 0.9), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 0.9, end: 0), weight: 1),
        ]).animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeInOut));
        _jumpAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
        _smileAnim = Tween<double>(begin: 0.55, end: 0.75)
            .animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeOut));
        _startMoodLoop(duration: const Duration(milliseconds: 1400));

      case CompanionMood.bounce:
        _armAnim = Tween<double>(begin: 0, end: 0.3).animate(
            CurvedAnimation(parent: _moodCtrl, curve: Curves.easeInOut));
        _jumpAnim = TweenSequence<double>([
          TweenSequenceItem(
              tween: Tween<double>(begin: 0, end: 1)
                  .chain(CurveTween(curve: Curves.easeOut)),
              weight: 1),
          TweenSequenceItem(
              tween: Tween<double>(begin: 1, end: 0)
                  .chain(CurveTween(curve: Curves.bounceOut)),
              weight: 1),
        ]).animate(_moodCtrl);
        _smileAnim = Tween<double>(begin: 0.6, end: 0.9)
            .animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeOut));
        _startMoodLoop(duration: const Duration(milliseconds: 700));

      case CompanionMood.cheer:
        // Arms shoot up, body jumps, big grin
        _armAnim = TweenSequence<double>([
          TweenSequenceItem(
              tween: Tween<double>(begin: 0, end: 1.5)
                  .chain(CurveTween(curve: Curves.easeOut)),
              weight: 1),
          TweenSequenceItem(tween: ConstantTween(1.5), weight: 3),
          TweenSequenceItem(
              tween: Tween(begin: 1.5, end: 1.1)
                  .chain(CurveTween(curve: Curves.easeInOut)),
              weight: 1),
          TweenSequenceItem(
              tween: Tween(begin: 1.1, end: 1.5)
                  .chain(CurveTween(curve: Curves.easeInOut)),
              weight: 1),
        ]).animate(_moodCtrl);
        _jumpAnim = TweenSequence<double>([
          TweenSequenceItem(
              tween: Tween<double>(begin: 0, end: 0.9)
                  .chain(CurveTween(curve: Curves.easeOut)),
              weight: 2),
          TweenSequenceItem(
              tween: Tween<double>(begin: 0.9, end: 0)
                  .chain(CurveTween(curve: Curves.bounceOut)),
              weight: 3),
        ]).animate(_moodCtrl);
        _smileAnim = Tween<double>(begin: 0.7, end: 1.0)
            .animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeOut));
        _startMoodLoop(duration: const Duration(milliseconds: 1000));

      case CompanionMood.encourage:
        // Gentle lean and warm expression
        _armAnim = Tween<double>(begin: 0, end: 0.25)
            .animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeInOut));
        _jumpAnim = Tween<double>(begin: 0, end: 0).animate(_moodCtrl);
        _smileAnim = Tween<double>(begin: 0.55, end: 0.72)
            .animate(CurvedAnimation(parent: _moodCtrl, curve: Curves.easeInOut));
        _startMoodLoop(
            duration: const Duration(milliseconds: 2400), reverse: true);
    }
  }

  @override
  void didUpdateWidget(CompanionView old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _applyMood(widget.mood);
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _bobCtrl.dispose();
    _blinkCtrl.dispose();
    _moodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = ref.watch(reducedMotionProvider);
    if (reduceMotion) {
      if (_bobCtrl.isAnimating) _bobCtrl.stop();
      if (_moodCtrl.isAnimating) _moodCtrl.stop();
    } else {
      if (!_bobCtrl.isAnimating) _bobCtrl.repeat();
      // Re-apply the current mood so its loop restarts with the right
      // duration/curve/reverse — Reduce Motion was toggled off mid-loop.
      // Idle has no loop to restart, so skip it to avoid a pointless
      // stop()/reset() on every build while idle.
      if (!_moodCtrl.isAnimating && widget.mood != CompanionMood.idle) {
        _applyMood(widget.mood);
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Speech bubble appears above the companion
        if (_showBubble && widget.message != null)
          _SpeechBubble(
            key: ValueKey(widget.message),
            text: widget.message!,
            accentColor: widget.type.primaryColor,
            onDone: () {
              if (mounted) setState(() => _showBubble = false);
              widget.onMessageDone?.call();
            },
          ),
        AnimatedBuilder(
          animation: Listenable.merge([_bobCtrl, _blinkCtrl, _moodCtrl]),
          builder: (_, _) => RepaintBoundary(
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: CompanionPainter.forType(
                widget.type,
                bobOffset: _bobOffset,
                eyeOpenness: _eyeOpen,
                armAngle: _armAngle,
                jumpOffset: _jumpOffset,
                smileAmount: _smileAmount,
                isDark: isDark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Speech bubble ─────────────────────────────────────────────────────────────

class _SpeechBubble extends StatefulWidget {
  const _SpeechBubble({
    super.key,
    required this.text,
    required this.accentColor,
    this.onDone,
  });

  final String text;
  final Color accentColor;
  final VoidCallback? onDone;

  @override
  State<_SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<_SpeechBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _timer;
  bool _fadingOut = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    if (_fadingOut || !mounted) return;
    _fadingOut = true;
    _ctrl.reverse().then((_) => widget.onDone?.call());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceVariantDark : Colors.white;
    final textColor =
        isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;

    return GestureDetector(
      onTap: _dismiss,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bubble body
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: AppElevation.low,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 2,
                    ),
                    child: Text(
                      widget.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                // Tail pointing down toward the companion
                CustomPaint(
                  size: const Size(14, 7),
                  painter: _TailPainter(
                    color: bg,
                    borderColor: widget.accentColor.withValues(alpha: 0.35),
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

// Tiny downward triangle that forms the speech bubble tail.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.color, required this.borderColor});
  final Color color;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = borderColor);
    // Inner fill slightly smaller
    final inner = Path()
      ..moveTo(1.5, 0)
      ..lineTo(s.width - 1.5, 0)
      ..lineTo(s.width / 2, s.height - 1.5)
      ..close();
    canvas.drawPath(inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) =>
      old.color != color || old.borderColor != borderColor;
}
