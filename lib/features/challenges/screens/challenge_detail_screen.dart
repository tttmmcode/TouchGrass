import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_names.dart';
import '../../../models/completion_model.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/loading_widgets.dart';

class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({
    super.key,
    required this.challengeId,
    this.completion,
  });

  final String challengeId;
  final CompletionModel? completion;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.completion;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Challenge')),
        body: const Center(child: Text('No details available.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(c.completedAt);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(RouteNames.home),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: c.photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: c.photoUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      placeholder: (ctx, url) => const ShimmerBox(),
                      errorWidget: (ctx, url, err) => DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: AppColors.gradientForest,
                        ),
                        child: Center(
                          child: Text(
                            c.challengeEmoji,
                            style: const TextStyle(fontSize: 72),
                          ),
                        ),
                      ),
                    )
                  : DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: AppColors.gradientForest,
                      ),
                      child: Center(
                        child: Text(
                          c.challengeEmoji,
                          style: const TextStyle(fontSize: 72),
                        ),
                      ),
                    ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
            sliver: SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.challengeEmoji,
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.challengeTitle,
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? AppColors.onSurfaceDark
                                        : AppColors.onSurfaceLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.grassGreen.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusFull,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '${c.challengeCategory.emoji} '
                                      '${c.challengeCategory.displayName}',
                                      style: const TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.forestGreen,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _StatRow(
                        icon: Icons.calendar_today_rounded,
                        label: 'Completed',
                        value: dateStr,
                        isDark: isDark,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _StatRow(
                        icon: Icons.star_rounded,
                        label: 'XP Earned',
                        value: '+${c.xpAwarded} XP',
                        isDark: isDark,
                        valueColor: AppColors.achievementGold,
                      ),
                      if (c.verificationDisplayText.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _StatRow(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Completion',
                          value: c.verificationDisplayText,
                          isDark: isDark,
                          valueColor: AppColors.grassGreen,
                        ),
                      ],
                      if (c.caption != null && c.caption!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _StatRow(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Your Note',
                          value: c.caption!,
                          isDark: isDark,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxxxl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final mutedColor = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: mutedColor),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: mutedColor,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
