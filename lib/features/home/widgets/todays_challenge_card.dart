import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../models/challenge_model.dart';
import '../../../models/completion_model.dart';
import '../../../providers/assignment_providers.dart';
import '../../../providers/challenge_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_elevation.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/pressable_scale.dart';

class TodaysChallengeCard extends StatelessWidget {
  const TodaysChallengeCard({super.key, required this.todayNode});
  final PathNode todayNode;

  @override
  Widget build(BuildContext context) {
    if (todayNode is CompletedPathNode) {
      return _DoneCard(completion: (todayNode as CompletedPathNode).completion);
    }
    if (todayNode is ActivePathNode) {
      final challenge = (todayNode as ActivePathNode).challenge;
      return challenge != null
          ? AnimatedSwitcher(
              duration: AppMotion.long,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.09),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _ChallengeCard(
                key: ValueKey(challenge.challengeId),
                challenge: challenge,
              ),
            )
          : const _PendingCard();
    }
    return const SizedBox.shrink();
  }
}

// ── Active challenge card ─────────────────────────────────────────────────────

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard({super.key, required this.challenge});
  final ChallengeModel challenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayLabel = 'Day ${challenge.dayNumber}';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.gradientForest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        boxShadow: AppElevation.glow(AppColors.forestGreen, opacity: 0.38),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.betweenCards),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Day counter + category row
            Row(
              children: [
                Text(
                  dayLabel,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                _XpBadge(xp: challenge.xpReward),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Header row
            Row(
              children: [
                Text(challenge.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  "TODAY'S CHALLENGE",
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Title
            Text(
              challenge.title,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            if (challenge.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                challenge.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
            ],
            if (challenge.objective.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          challenge.objective,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // Meta row: category + difficulty + estimated time.
            // Wrap (not Row) so a long category/challenge name on a narrow
            // phone drops the time pill to a second line instead of
            // overflowing.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetaPill(
                  label: '${challenge.challengeCategory.emoji} '
                      '${challenge.challengeCategory.displayName}',
                ),
                _MetaPill(
                  label: '${challenge.difficulty.emoji} '
                      '${challenge.difficulty.displayName}',
                ),
                _MetaPill(
                  icon: Icons.timer_outlined,
                  label: '${challenge.estimatedMinutes} min',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _DiceButton(challenge: challenge),
            const SizedBox(height: AppSpacing.md),
            const _StartButton(),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _XpBadge extends StatelessWidget {
  const _XpBadge({required this.xp});
  final int xp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              '$xp XP',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dice reroll button — unlimited rerolls, shows count ──────────────────────

class _DiceButton extends ConsumerStatefulWidget {
  const _DiceButton({required this.challenge});
  final ChallengeModel challenge;

  @override
  ConsumerState<_DiceButton> createState() => _DiceButtonState();
}

class _DiceButtonState extends ConsumerState<_DiceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _spin;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _spin = Tween<double>(begin: 0, end: 3 * 2 * pi).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rerollProvider, (_, next) {
      next.whenOrNull(
        error: (e, _) {
          final msg =
              e is AppException ? e.message : 'Could not reload challenge.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg,
                  style: const TextStyle(
                      fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
              margin: const EdgeInsets.all(AppSpacing.md),
            ),
          );
        },
      );
    });

    final isLoading = ref.watch(rerollProvider).isLoading;
    final rerollCount = widget.challenge.rerollCount;

    return GestureDetector(
      onTap: isLoading ? null : _onTap,
      child: AnimatedOpacity(
        opacity: isLoading ? 0.65 : 1.0,
        duration: AppMotion.fast,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, child) => Transform.rotate(
                    angle: _spin.value,
                    child: child,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(
                          Icons.casino_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feeling adventurous?',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        'Roll for another challenge',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (rerollCount > 0)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      child: Text(
                        '×$rerollCount',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap() async {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_ctrl.forward(from: 0));
    await ref.read(rerollProvider.notifier).reroll();
  }
}

// ── Start button — arrow bounces right ───────────────────────────────────────

class _StartButton extends ConsumerStatefulWidget {
  const _StartButton();

  @override
  ConsumerState<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends ConsumerState<_StartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _arrow;

  // Guards against a rapid double-tap pushing two camera routes onto the
  // stack. Resets automatically once the pushed route is popped, so the
  // button works normally again on return from the camera flow.
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    // Continuous ambient loop — never runs when Reduce Motion is on.
    if (!ref.read(reducedMotionProvider)) _ctrl.repeat(reverse: true);
    _arrow = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.32, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Start today's challenge",
      excludeSemantics: true,
      child: PressableScale(
      child: SizedBox(
        height: AppSpacing.buttonHeight,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          elevation: 4,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: () async {
              if (_navigating) return;
              _navigating = true;
              unawaited(HapticFeedback.lightImpact());
              await context.pushNamed('camera');
              if (mounted) setState(() => _navigating = false);
            },
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
            splashColor: AppColors.grassGreen.withValues(alpha: 0.2),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Start Challenge',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.forestGreen,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SlideTransition(
                    position: _arrow,
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: AppSpacing.iconSm,
                      color: AppColors.forestGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ── Completed today ───────────────────────────────────────────────────────────

class _DoneCard extends StatefulWidget {
  const _DoneCard({required this.completion});
  final CompletionModel completion;

  @override
  State<_DoneCard> createState() => _DoneCardState();
}

class _DoneCardState extends State<_DoneCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _check;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _check = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.nodeCompleted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        boxShadow: [
          BoxShadow(
            color: AppColors.grassGreen.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            ScaleTransition(
              scale: _check,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: AppSpacing.iconLg),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TODAY COMPLETE!',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You crushed it! New adventure tomorrow.',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Text(widget.completion.challengeEmoji,
                style: const TextStyle(fontSize: 28)),
          ],
        ),
      ),
    );
  }
}

// ── Pending ───────────────────────────────────────────────────────────────────

class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard();

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _showRetry = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Generation normally resolves in a few seconds (the card is replaced
    // automatically once it does). If it's still showing after this long,
    // generation likely failed silently — offer a way to retry rather than
    // leaving the user staring at "check back in a moment" forever.
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showRetry = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;
    final border = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final textColor = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, size: AppSpacing.iconLg, color: textColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREPARING YOUR ADVENTURE…',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your daily challenge is on its way. '
                    'Check back in a moment!',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                  AnimatedSize(
                    duration: AppMotion.standard,
                    alignment: Alignment.topLeft,
                    child: _showRetry
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: TextButton.icon(
                              onPressed: () =>
                                  ref.invalidate(assignmentInitProvider),
                              style: TextButton.styleFrom(
                                foregroundColor: textColor,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.refresh_rounded,
                                  size: AppSpacing.iconTiny),
                              label: const Text(
                                'Taking a while — Try Again',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
