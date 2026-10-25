import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../companions/companion.dart';
import '../../../companions/companion_widget.dart';
import '../../../core/constants/route_names.dart';
import '../../../core/services/error_service.dart';
import '../../../models/achievement_definition.dart';
import '../../../models/achievement_model.dart';
import '../../../providers/achievement_providers.dart';
import '../../../providers/companion_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/error_retry_view.dart';

class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  // Single shared shine controller — earned cards use it so we only pay
  // for one ticker regardless of how many achievements are earned.
  late final AnimationController _shineCtrl;

  @override
  void initState() {
    super.initState();
    _shineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    // Purely decorative continuous loop — never starts under Reduce Motion.
    if (!ref.read(reducedMotionProvider)) _shineCtrl.repeat();
  }

  @override
  void dispose() {
    _shineCtrl.dispose();
    super.dispose();
  }

  void _showDetail(AchievementModel model) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AchievementDetailSheet(model: model),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final models = ref.watch(achievementModelsProvider);
    final companion = ref.watch(activeCompanionProvider);
    final reducedMotion = ref.watch(reducedMotionProvider);

    if (models.isEmpty) {
      if (userAsync.hasError) {
        return Scaffold(
          body: ErrorRetryView(
            message: ErrorService.friendlyMessage(userAsync.error!),
            onRetry: () => ref.invalidate(currentUserProvider),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final earned = models.where((m) => m.isUnlocked).toList();
    final locked = models.where((m) => !m.isUnlocked).toList();
    final total = models.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ── Companion banner ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _CompanionBanner(
              companion: companion,
              onChangeTap: () => context.go(RouteNames.companionSelect),
            ),
          ),

          // ── Progress header ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _ProgressHeader(
              earned: earned.length,
              total: total,
              reducedMotion: reducedMotion,
            ),
          ),

          // ── Earned section ───────────────────────────────────────────────
          if (earned.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                icon: Icons.emoji_events_rounded,
                title: 'Earned',
                count: earned.length,
                color: AppColors.achievementGold,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.xs,
                AppSpacing.screenHorizontal,
                AppSpacing.md,
              ),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.88,
                ),
                itemCount: earned.length,
                itemBuilder: (context, i) => RepaintBoundary(
                  child: _AchievementCard(
                    model: earned[i],
                    index: i,
                    shineAnimation: reducedMotion ? null : _shineCtrl,
                    reducedMotion: reducedMotion,
                    onTap: () => _showDetail(earned[i]),
                  ),
                ),
              ),
            ),
          ],

          // ── Upcoming section ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              icon: Icons.lock_open_rounded,
              title: 'Upcoming',
              count: locked.length,
              color: AppColors.grassGreen,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.xs,
              AppSpacing.screenHorizontal,
              AppSpacing.xxxl,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.78,
              ),
              itemCount: locked.length,
              itemBuilder: (context, i) => RepaintBoundary(
                child: _AchievementCard(
                  model: locked[i],
                  index: i,
                  shineAnimation: null,
                  reducedMotion: reducedMotion,
                  onTap: () => _showDetail(locked[i]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Companion banner ──────────────────────────────────────────────────────────

class _CompanionBanner extends StatelessWidget {
  const _CompanionBanner({required this.companion, required this.onChangeTap});

  final CompanionType companion;
  final VoidCallback onChangeTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.lg,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: companion.primaryColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CompanionView(
                type: companion,
                mood: CompanionMood.idle,
                size: AppSpacing.avatarLg,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Companion',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: textMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      companion.displayName,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: textStrong,
                      ),
                    ),
                    Text(
                      companion.tagline,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onChangeTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.grassGreen,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Progress header ───────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.earned,
    required this.total,
    required this.reducedMotion,
  });
  final int earned;
  final int total;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = total > 0 ? earned / total : 0.0;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final trackColor = isDark ? AppColors.outlineDark : AppColors.dividerLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.lg,
        AppSpacing.screenHorizontal,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$earned of $total earned',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textStrong,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.gradientGold,
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
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$earned',
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0)),
            duration: reducedMotion ? Duration.zero : AppMotion.reveal,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LayoutBuilder(
              builder: (_, constraints) {
                final fillWidth = constraints.maxWidth * value;
                return Stack(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: trackColor,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: SizedBox(height: 8, width: constraints.maxWidth),
                    ),
                    if (fillWidth > 0)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientGold,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: SizedBox(height: 8, width: fillWidth),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${(progress * 100).round()}% complete',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final mutedBg = isDark
        ? AppColors.onSurfaceVariantDark.withValues(alpha: 0.12)
        : AppColors.onSurfaceVariantLight.withValues(alpha: 0.12);
    final mutedText = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.lg,
        AppSpacing.screenHorizontal,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconTiny, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: textStrong,
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: mutedBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: mutedText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Achievement card ──────────────────────────────────────────────────────────

class _AchievementCard extends StatefulWidget {
  const _AchievementCard({
    required this.model,
    required this.index,
    required this.shineAnimation,
    required this.reducedMotion,
    required this.onTap,
  });

  final AchievementModel model;
  final int index;
  final Animation<double>? shineAnimation;
  final bool reducedMotion;
  final VoidCallback onTap;

  @override
  State<_AchievementCard> createState() => _AchievementCardState();
}

class _AchievementCardState extends State<_AchievementCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));

    if (widget.reducedMotion) {
      // Skip the staggered slide-in entirely — jump straight to final state.
      _entryCtrl.value = 1.0;
      return;
    }
    final delay = Duration(milliseconds: (widget.index * 50).clamp(0, 500));
    Future<void>.delayed(delay, () {
      if (mounted) _entryCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget card = Semantics(
      button: true,
      label: widget.model.isUnlocked
          ? '${widget.model.rarity.label} achievement, ${widget.model.title}, '
                'unlocked. ${widget.model.description}'
          : '${widget.model.rarity.label} achievement, ${widget.model.title}, '
                'locked. ${widget.model.progressLabel}, '
                '${widget.model.completionPercentage.round()} percent complete.',
      // Card content is emoji/title/description/progress Text widgets that
      // would each contribute their own semantics node otherwise — the
      // label above already composes everything a screen reader needs, so
      // exclude the children to avoid a garbled double announcement.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: _CardShell(
          model: widget.model,
          isDark: isDark,
          child: _CardContent(
            model: widget.model,
            isDark: isDark,
            reducedMotion: widget.reducedMotion,
          ),
        ),
      ),
    );

    // Locked: desaturated + slightly dimmed; no blur so badge artwork stays readable.
    if (!widget.model.isUnlocked) {
      card = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.6063,
          0.3576,
          0.0361,
          0,
          0,
          0.1063,
          0.6576,
          0.0361,
          0,
          0,
          0.1063,
          0.3576,
          0.5361,
          0,
          0,
          0,
          0,
          0,
          0.82,
          0,
        ]),
        child: card,
      );
    }

    // Earned: diagonal shine sweep driven by the shared parent controller.
    if (widget.model.isUnlocked && widget.shineAnimation != null) {
      card = AnimatedBuilder(
        animation: widget.shineAnimation!,
        builder: (_, child) {
          final t = widget.shineAnimation!.value;
          return ShaderMask(
            blendMode: BlendMode.screen,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-2.0 + t * 5.0, -0.6),
              end: Alignment(-1.6 + t * 5.0, 0.6),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.20),
                Colors.transparent,
              ],
            ).createShader(rect),
            child: child,
          );
        },
        child: card,
      );
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: card),
    );
  }
}

// ── Card shell ────────────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.model,
    required this.isDark,
    required this.child,
  });

  final AchievementModel model;
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isEarned = model.isUnlocked;
    final rarityColor = model.rarity.color;

    final bg = isEarned
        ? (isDark
              ? AppColors.surfaceVariantDark
              : AppColors.surfaceVariantLight)
        : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);

    final borderColor = isEarned
        ? rarityColor.withValues(alpha: 0.55)
        : (isDark ? AppColors.outlineDark : AppColors.outlineLight);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: isEarned
            ? [
                BoxShadow(
                  color: rarityColor.withValues(alpha: model.rarity.glowAlpha),
                  blurRadius: model.rarity.glowBlurRadius,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

// ── Card content ──────────────────────────────────────────────────────────────

class _CardContent extends ConsumerWidget {
  const _CardContent({
    required this.model,
    required this.isDark,
    required this.reducedMotion,
  });

  final AchievementModel model;
  final bool isDark;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleColor = model.isUnlocked
        ? (isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight)
        : (isDark
              ? AppColors.onSurfaceVariantDark
              : AppColors.onSurfaceVariantLight);
    final descColor = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final trackColor = isDark ? AppColors.outlineDark : AppColors.dividerLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: emoji + status/rarity indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.emoji, style: const TextStyle(fontSize: 36)),
            if (model.isUnlocked)
              _RarityBadge(rarity: model.rarity)
            else
              Icon(
                Icons.lock_outline_rounded,
                size: AppSpacing.iconTiny,
                color: isDark
                    ? AppColors.onSurfaceVariantDark
                    : AppColors.onSurfaceVariantLight,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          model.title,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: titleColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          model.description,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: descColor,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // Progress bar — only on locked cards
        if (!model.isUnlocked) ...[
          const SizedBox(height: AppSpacing.sm),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: model.progressFraction),
            duration: reducedMotion ? Duration.zero : AppMotion.reveal,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LayoutBuilder(
              builder: (_, constraints) {
                final fillWidth = constraints.maxWidth * value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: trackColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                          ),
                          child: SizedBox(
                            height: 5,
                            width: constraints.maxWidth,
                          ),
                        ),
                        if (fillWidth > 0)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.grassGreen.withValues(
                                alpha: 0.75,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: SizedBox(height: 5, width: fillWidth),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      model.progressLabel,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: descColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ── Rarity badge chip ─────────────────────────────────────────────────────────

class _RarityBadge extends StatelessWidget {
  const _RarityBadge({required this.rarity});
  final AchievementRarity rarity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: rarity.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: rarity.color.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          rarity.label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: rarity.color,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ── Achievement detail sheet ──────────────────────────────────────────────────

class _AchievementDetailSheet extends ConsumerWidget {
  const _AchievementDetailSheet({required this.model});
  final AchievementModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final divider = isDark ? AppColors.dividerDark : AppColors.dividerLight;
    final trackColor = isDark ? AppColors.outlineDark : AppColors.dividerLight;

    final user = ref.watch(currentUserProvider).valueOrNull;
    final reducedMotion = ref.watch(reducedMotionProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.45,
      maxChildSize: 0.88,
      expand: false,
      builder: (_, scrollCtrl) => DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusBottomSheet),
          ),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: textMuted.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: const SizedBox(width: 40, height: 4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Badge + rarity row ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Large emoji with rarity glow
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: model.rarity.color.withValues(
                              alpha: isDark ? 0.15 : 0.10,
                            ),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusLg,
                            ),
                            border: Border.all(
                              color: model.rarity.color.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              model.emoji,
                              style: const TextStyle(fontSize: 52),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: AppSpacing.xs),
                              // Rarity + category chips
                              Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  _RarityBadge(rarity: model.rarity),
                                  _CategoryChip(category: model.category),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                model.title,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textStrong,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                model.description,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xl),
                    Divider(color: divider, height: 1),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Progress / earned date ──
                    if (model.isUnlocked) ...[
                      Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.gradientGold,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(AppSpacing.sm),
                              child: Icon(
                                Icons.emoji_events_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Achievement Earned',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: textStrong,
                                ),
                              ),
                              if (model.unlockedAt != null)
                                Text(
                                  _formatDate(model.unlockedAt!),
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Animated progress bar
                      if (user != null)
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0,
                            end: model.progressFraction,
                          ),
                          duration: reducedMotion
                              ? Duration.zero
                              : AppMotion.reveal,
                          curve: Curves.easeOutCubic,
                          builder: (_, value, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LayoutBuilder(
                                builder: (_, constraints) {
                                  final fill = constraints.maxWidth * value;
                                  return Stack(
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: trackColor,
                                          borderRadius: BorderRadius.circular(
                                            AppSpacing.radiusFull,
                                          ),
                                        ),
                                        child: SizedBox(
                                          height: 8,
                                          width: constraints.maxWidth,
                                        ),
                                      ),
                                      if (fill > 0)
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: AppColors.grassGreen,
                                            borderRadius: BorderRadius.circular(
                                              AppSpacing.radiusFull,
                                            ),
                                          ),
                                          child: SizedBox(
                                            height: 8,
                                            width: fill,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    model.progressLabel,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textMuted,
                                    ),
                                  ),
                                  Text(
                                    '${model.completionPercentage.round()}%',
                                    style: const TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.grassGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    Divider(color: divider, height: 1),
                    const SizedBox(height: AppSpacing.lg),

                    // ── XP reward ──
                    Row(
                      children: [
                        const Text('⭐', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Awards +${model.xpReward} XP',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: textStrong,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

// ── Category chip ─────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});
  final AchievementCategory category;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final chipBg = isDark
        ? AppColors.onSurfaceVariantDark.withValues(alpha: 0.12)
        : AppColors.onSurfaceVariantLight.withValues(alpha: 0.12);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 3),
            Text(
              category.label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
