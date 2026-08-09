import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/user_model.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class StatsBar extends ConsumerWidget {
  const StatsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      data: (user) =>
          user != null ? _StatsContent(user: user) : const SizedBox.shrink(),
      loading: () => const _StatsSkeleton(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ── Content ───────────────────────────────────────────────────────────────────

class _StatsContent extends ConsumerWidget {
  const _StatsContent({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = ref.watch(reducedMotionProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _LevelBadge(level: user.level),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                child: _XpBar(user: user, reducedMotion: reducedMotion)),
            const SizedBox(width: AppSpacing.md),
            _StreakPill(streak: user.streak, reducedMotion: reducedMotion),
          ],
        ),
      ),
    );
  }
}

// ── Level badge ───────────────────────────────────────────────────────────────

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Level $level',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: AppColors.gradientForest,
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              '$level',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── XP bar — animates from 0 → actual fill on each build ─────────────────────

class _XpBar extends StatelessWidget {
  const _XpBar({required this.user, required this.reducedMotion});
  final UserModel user;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? AppColors.outlineDark : AppColors.dividerLight;
    final target = user.levelProgress.clamp(0.0, 1.0);

    return Semantics(
      label: '${user.xpInCurrentLevel} of ${AppConstants.xpPerLevel} '
          'XP to next level',
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${user.xpInCurrentLevel} / ${AppConstants.xpPerLevel} XP',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.onSurfaceVariantDark
                : AppColors.onSurfaceVariantLight,
          ),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: target),
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 1000),
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
                    child: SizedBox(
                        height: 8, width: constraints.maxWidth),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientForest,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: SizedBox(height: 8, width: fillWidth),
                  ),
                ],
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

// ── Streak pill — gentle breathing pulse ─────────────────────────────────────

class _StreakPill extends StatefulWidget {
  const _StreakPill({required this.streak, required this.reducedMotion});
  final int streak;
  final bool reducedMotion;

  @override
  State<_StreakPill> createState() => _StreakPillState();
}

class _StreakPillState extends State<_StreakPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    // Continuous ambient loop — never runs when Reduce Motion is on.
    if (!widget.reducedMotion) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.streak} day streak',
      child: ScaleTransition(
      scale: _scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.gradientStreak,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          boxShadow: [
            BoxShadow(
              color: AppColors.streakOrange.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '${widget.streak}',
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
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? AppColors.surfaceVariantDark : AppColors.dividerLight;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _Bone(width: 40, height: 40, color: c, circle: true),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Bone(width: 60, height: 10, color: c),
                const SizedBox(height: 4),
                _Bone(width: double.infinity, height: 8, color: c),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _Bone(width: 56, height: 28, color: c),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    required this.color,
    this.circle = false,
  });

  final double width;
  final double height;
  final Color color;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            circle ? null : BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}
