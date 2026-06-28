import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_names.dart';
import '../../../models/challenge_model.dart';
import '../../../models/completion_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/achievement_providers.dart';
import '../../../providers/challenge_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

// ── Design tokens for this screen ─────────────────────────────────────────────
const double _kPad = 24;
const double _kCardPad = 20;
const double _kSectionGap = 32;
const double _kGap = 16;
const double _kBreak = 48;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shineCtrl;

  @override
  void initState() {
    super.initState();
    _shineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go(RouteNames.settings),
          ),
        ],
      ),
      body: userAsync.when(
        data: (user) => user != null
            ? _ProfileBody(user: user, shineCtrl: _shineCtrl)
            : const Center(child: Text('Not signed in')),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Error loading profile')),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user, required this.shineCtrl});

  final UserModel user;
  final AnimationController shineCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementStatusProvider);
    final completionsAsync = ref.watch(recentCompletionsProvider);
    final completions = completionsAsync.valueOrNull ?? const [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _kGap)),

        // ── Hero card ──────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _HeroCard(user: user),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kGap)),

        // ── Stats banner ───────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _StatsBanner(user: user),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kBreak)),

        // ── Exploration Stats ──────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _SectionLabel(
              title: 'Exploration Stats',
              icon: Icons.explore_rounded,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kGap)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _ExplorationStats(user: user, completions: completions),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kSectionGap)),

        // ── Achievements ───────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _SectionLabel(
              title: 'Achievements',
              icon: Icons.emoji_events_rounded,
              trailing: _AchievementCount(
                earned: achievements.where((a) => a.earned).length,
                total: achievements.length,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kGap)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: _kGap,
              mainAxisSpacing: _kGap,
              childAspectRatio: 0.82,
            ),
            itemCount: achievements.length,
            itemBuilder: (context, i) => RepaintBoundary(
              child: _AchievementBadge(
                status: achievements[i],
                user: user,
                shineCtrl: shineCtrl,
                index: i,
                isDark: isDark,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kBreak)),

        // ── Challenge History ──────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: _kPad),
          sliver: SliverToBoxAdapter(
            child: _SectionLabel(
              title: 'Challenge History',
              icon: Icons.history_rounded,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: _kGap)),

        if (completionsAsync.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(_kPad),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (completions.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: _kPad),
            sliver: SliverToBoxAdapter(child: _EmptyHistory()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _kPad),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  for (var i = 0; i < completions.length; i++) ...[
                    if (i > 0) const SizedBox(height: _kGap),
                    _HistoryCard(completion: completions[i]),
                  ],
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: _kBreak)),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textStrong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.grassGreen),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: textStrong,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _AchievementCount extends StatelessWidget {
  const _AchievementCount({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.gradientGold,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded,
                size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              '$earned / $total',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.user});
  final UserModel user;

  String _rankTitle(int level) {
    if (level >= 20) return 'Master Explorer';
    if (level >= 10) return 'Trailblazer';
    if (level >= 5) return 'Explorer';
    return 'Seedling';
  }

  @override
  Widget build(BuildContext context) {
    final xpToNext = AppConstants.xpPerLevel - user.xpInCurrentLevel;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.gradientForest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kCardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name + rank
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(user: user),
                const SizedBox(width: _kGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Pill(
                            label: 'Level ${user.level}',
                            bg: Colors.white.withValues(alpha: 0.22),
                          ),
                          const SizedBox(width: 8),
                          _Pill(
                            label: _rankTitle(user.level),
                            bg: AppColors.achievementGold.withValues(alpha: 0.28),
                            textColor: AppColors.achievementGold,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: _kCardPad),

            // XP bar header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${user.xpInCurrentLevel} / ${AppConstants.xpPerLevel} XP',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  '$xpToNext XP to Lv ${user.level + 1}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: user.levelProgress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LayoutBuilder(
                builder: (_, constraints) {
                  final fillWidth = constraints.maxWidth * value;
                  return Stack(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: SizedBox(
                            height: 10, width: constraints.maxWidth),
                      ),
                      if (fillWidth > 0)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                          ),
                          child: SizedBox(height: 10, width: fillWidth),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
            Text(
              '${(user.levelProgress * 100).round()}% through Level ${user.level}',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final initials = user.displayName.isNotEmpty
        ? user.displayName[0].toUpperCase()
        : '?';

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.25),
            blurRadius: 12,
          ),
        ],
      ),
      child: SizedBox(
        width: AppSpacing.avatarLg,
        height: AppSpacing.avatarLg,
        child: ClipOval(
          child: user.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: user.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: const ColoredBox(color: Colors.white),
                  ),
                  errorWidget: (ctx, url, err) => _Initials(initials: initials),
                )
              : _Initials(initials: initials),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.forestGreenDark,
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.bg,
    this.textColor = Colors.white,
  });

  final String label;
  final Color bg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

// ── Stats banner ──────────────────────────────────────────────────────────────

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatChip(
                icon: Icons.local_fire_department_rounded,
                value: user.streak,
                label: 'Day Streak',
                gradient: AppColors.gradientStreak,
                onTap: () => context.go(RouteNames.streakCalendar),
                trailingHint: 'tap for calendar',
              ),
            ),
            const SizedBox(width: _kGap),
            Expanded(
              child: _StatChip(
                icon: Icons.check_circle_rounded,
                value: user.totalCompletions,
                label: 'Completed',
                gradient: AppColors.gradientForest,
              ),
            ),
            const SizedBox(width: _kGap),
            Expanded(
              child: _StatChip(
                icon: Icons.star_rounded,
                value: user.xp,
                label: 'Total XP',
                gradient: AppColors.gradientGold,
              ),
            ),
          ],
        ),
        const SizedBox(height: _kGap),
        _RainyDaysRow(user: user),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
    this.onTap,
    this.trailingHint,
  });

  final IconData icon;
  final int value;
  final String label;
  final LinearGradient gradient;
  final VoidCallback? onTap;
  final String? trailingHint;

  @override
  Widget build(BuildContext context) {
    Widget chip = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _kGap, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value),
              duration: const Duration(milliseconds: 1300),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(
                '$v',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
            if (trailingHint != null) ...[
              const SizedBox(height: 2),
              Text(
                trailingHint!,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      chip = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: chip,
        ),
      );
    }

    return chip;
  }
}

// ── Rainy Days row ────────────────────────────────────────────────────────────

class _RainyDaysRow extends StatelessWidget {
  const _RainyDaysRow({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final outline = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final onSurface = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;

    final available = user.rainyDaysAvailable;
    final used = user.rainyDaysUsed;
    final longest = user.longestStreak;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: _kCardPad, vertical: _kGap),
        child: Row(
          children: [
            const Text('🌧️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: _kGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rainy Days',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: onSurface,
                    ),
                  ),
                  Text(
                    'Protect your streak when life gets busy',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: _kGap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$available left',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.skyBlue,
                  ),
                ),
                Text(
                  '$used used · best $longest',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Exploration stats ─────────────────────────────────────────────────────────

class _ExplorationStats extends StatelessWidget {
  const _ExplorationStats({
    required this.user,
    required this.completions,
  });

  final UserModel user;
  final List<CompletionModel> completions;

  String _memberSince() {
    final d = user.createdAt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _topCategory() {
    if (completions.isEmpty) return 'None yet';
    final counts = <ChallengeCategory, int>{};
    for (final c in completions) {
      counts[c.challengeCategory] = (counts[c.challengeCategory] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return '${top.key.emoji} ${top.key.displayName}';
  }

  int _thisWeekCount() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return completions.where((c) => c.completedAt.isAfter(cutoff)).length;
  }

  int _avgXpPerChallenge() {
    if (user.totalCompletions == 0) return 0;
    return (user.xp / user.totalCompletions).round();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tiles = [
      _TileData(
        icon: Icons.calendar_today_rounded,
        value: _memberSince(),
        label: 'Member Since',
        accent: AppColors.skyBlue,
      ),
      _TileData(
        icon: Icons.bolt_rounded,
        value: '${_avgXpPerChallenge()} XP',
        label: 'Avg / Challenge',
        accent: AppColors.achievementGold,
      ),
      _TileData(
        icon: Icons.emoji_nature_rounded,
        value: _topCategory(),
        label: 'Top Category',
        accent: AppColors.grassGreen,
      ),
      _TileData(
        icon: Icons.date_range_rounded,
        value: '${_thisWeekCount()}',
        label: 'This Week',
        accent: AppColors.streakOrange,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: _kGap,
      mainAxisSpacing: _kGap,
      childAspectRatio: 1.65,
      children: [
        for (final t in tiles)
          _ExplorationTile(data: t, isDark: isDark),
      ],
    );
  }
}

class _TileData {
  const _TileData({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;
}

class _ExplorationTile extends StatelessWidget {
  const _ExplorationTile({required this.data, required this.isDark});

  final _TileData data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final textStrong =
        isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, size: 18, color: data.accent),
            const SizedBox(height: 6),
            Text(
              data.value,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: textStrong,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              data.label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Achievement badge ─────────────────────────────────────────────────────────

class _AchievementBadge extends StatefulWidget {
  const _AchievementBadge({
    required this.status,
    required this.user,
    required this.shineCtrl,
    required this.index,
    required this.isDark,
  });

  final AchievementStatus status;
  final UserModel user;
  final AnimationController shineCtrl;
  final int index;
  final bool isDark;

  @override
  State<_AchievementBadge> createState() => _AchievementBadgeState();
}

class _AchievementBadgeState extends State<_AchievementBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));

    final delay = Duration(milliseconds: (widget.index * 35).clamp(0, 600));
    Future<void>.delayed(delay, () {
      if (mounted) _entry.forward();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _onTap(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AchievementSheet(
        status: widget.status,
        user: widget.user,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.status.def;
    final earned = widget.status.earned;
    final isDark = widget.isDark;

    final bg = earned
        ? (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight)
        : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight);
    final borderColor = earned
        ? AppColors.grassGreen.withValues(alpha: 0.5)
        : (isDark ? AppColors.outlineDark : AppColors.outlineLight);
    final textColor = earned
        ? (isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight)
        : (isDark
            ? AppColors.onSurfaceVariantDark
            : AppColors.onSurfaceVariantLight);

    Widget card = GestureDetector(
      onTap: () => _onTap(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: earned
              ? [
                  BoxShadow(
                    color: AppColors.grassGreen.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(def.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 6),
              Text(
                def.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  height: 1.2,
                ),
              ),
              if (!earned) ...[
                const SizedBox(height: 4),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 11,
                  color: isDark
                      ? AppColors.onSurfaceVariantDark
                      : AppColors.onSurfaceVariantLight,
                ),
              ] else ...[
                const SizedBox(height: 4),
                const Icon(
                  Icons.check_rounded,
                  size: 11,
                  color: AppColors.grassGreen,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    // Desaturate locked
    if (!earned) {
      card = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.60, 0.35, 0.05, 0, 0,
          0.10, 0.65, 0.05, 0, 0,
          0.10, 0.35, 0.55, 0, 0,
          0,    0,    0,    0.72, 0,
        ]),
        child: card,
      );
    }

    // Diagonal shine on earned
    if (earned) {
      card = AnimatedBuilder(
        animation: widget.shineCtrl,
        builder: (_, child) {
          final t = widget.shineCtrl.value;
          return ShaderMask(
            blendMode: BlendMode.screen,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment(-2.0 + t * 5.0, -0.6),
              end: Alignment(-1.6 + t * 5.0, 0.6),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.18),
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

// ── Achievement detail sheet ──────────────────────────────────────────────────

class _AchievementSheet extends StatelessWidget {
  const _AchievementSheet({required this.status, required this.user});

  final AchievementStatus status;
  final UserModel user;

  ({double progress, String current, String target}) _progressFor() {
    final def = status.def;
    final u = user;
    return switch (def.id) {
      'first_touch' => (
          progress: (u.totalCompletions / 1).clamp(0.0, 1.0),
          current: '${u.totalCompletions} challenge${u.totalCompletions == 1 ? '' : 's'}',
          target: '1 challenge',
        ),
      'challenges_5' => (
          progress: (u.totalCompletions / 5).clamp(0.0, 1.0),
          current: '${u.totalCompletions} / 5',
          target: '5 challenges',
        ),
      'challenges_10' => (
          progress: (u.totalCompletions / 10).clamp(0.0, 1.0),
          current: '${u.totalCompletions} / 10',
          target: '10 challenges',
        ),
      'challenges_25' => (
          progress: (u.totalCompletions / 25).clamp(0.0, 1.0),
          current: '${u.totalCompletions} / 25',
          target: '25 challenges',
        ),
      'challenges_50' => (
          progress: (u.totalCompletions / 50).clamp(0.0, 1.0),
          current: '${u.totalCompletions} / 50',
          target: '50 challenges',
        ),
      'challenges_100' => (
          progress: (u.totalCompletions / 100).clamp(0.0, 1.0),
          current: '${u.totalCompletions} / 100',
          target: '100 challenges',
        ),
      'streak_3' => (
          progress: (u.streak / 3).clamp(0.0, 1.0),
          current: '${u.streak} day${u.streak == 1 ? '' : 's'}',
          target: '3-day streak',
        ),
      'streak_7' => (
          progress: (u.streak / 7).clamp(0.0, 1.0),
          current: '${u.streak} / 7 days',
          target: '7-day streak',
        ),
      'streak_30' => (
          progress: (u.streak / 30).clamp(0.0, 1.0),
          current: '${u.streak} / 30 days',
          target: '30-day streak',
        ),
      'streak_100' => (
          progress: (u.streak / 100).clamp(0.0, 1.0),
          current: '${u.streak} / 100 days',
          target: '100-day streak',
        ),
      'xp_100' => (
          progress: (u.xp / 100).clamp(0.0, 1.0),
          current: '${u.xp} XP',
          target: '100 XP',
        ),
      'xp_500' => (
          progress: (u.xp / 500).clamp(0.0, 1.0),
          current: '${u.xp} / 500 XP',
          target: '500 XP',
        ),
      'xp_1000' => (
          progress: (u.xp / 1000).clamp(0.0, 1.0),
          current: '${u.xp} / 1,000 XP',
          target: '1,000 XP',
        ),
      'xp_2500' => (
          progress: (u.xp / 2500).clamp(0.0, 1.0),
          current: '${u.xp} / 2,500 XP',
          target: '2,500 XP',
        ),
      'level_5' => (
          progress: (u.level / 5).clamp(0.0, 1.0),
          current: 'Level ${u.level}',
          target: 'Level 5',
        ),
      'level_10' => (
          progress: (u.level / 10).clamp(0.0, 1.0),
          current: 'Level ${u.level}',
          target: 'Level 10',
        ),
      _ => (progress: 0.0, current: '—', target: '—'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textStrong =
        isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;
    final trackColor =
        isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    final def = status.def;
    final earned = status.earned;
    final info = _progressFor();

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        _kPad,
        _kGap,
        _kPad,
        _kPad + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          DecoratedBox(
            decoration: BoxDecoration(
              color: textMuted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: const SizedBox(width: 36, height: 4),
          ),
          const SizedBox(height: _kCardPad),

          // Emoji
          Text(def.emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 10),

          // Badge name
          Text(
            def.title,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: textStrong,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Status pill
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: earned ? AppColors.gradientGold : null,
              color: earned ? null : trackColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    earned
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    size: 14,
                    color: earned ? Colors.white : textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    earned ? 'Earned' : 'Locked',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: earned ? Colors.white : textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: _kGap),

          // Description
          Text(
            def.description,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textMuted,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),

          // Progress bar (locked only)
          if (!earned) ...[
            const SizedBox(height: _kGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Progress',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textStrong,
                  ),
                ),
                Text(
                  info.current,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: info.progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => LayoutBuilder(
                builder: (_, constraints) {
                  final fillWidth = constraints.maxWidth * value;
                  return Stack(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: SizedBox(
                            height: 10, width: constraints.maxWidth),
                      ),
                      if (fillWidth > 0)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientForest,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                          ),
                          child: SizedBox(height: 10, width: fillWidth),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(info.progress * 100).round()}% complete',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                Text(
                  'Goal: ${info.target}',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: _kCardPad),
        ],
      ),
    );
  }
}

// ── Challenge history ─────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.completion});
  final CompletionModel completion;

  String _formattedDate() {
    final d = completion.completedAt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final textStrong =
        isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kCardPad),
        child: Row(
          children: [
            // Emoji container
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.grassGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    completion.challengeEmoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: _kGap),

            // Title + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completion.challengeTitle,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textStrong,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 11, color: textMuted),
                      const SizedBox(width: 4),
                      Text(
                        _formattedDate(),
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              AppColors.grassGreen.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text(
                            completion.challengeCategory.displayName,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.grassGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: _kGap),

            // XP badge
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.gradientGold,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                  '+${completion.xpAwarded} XP',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.outlineDark : AppColors.outlineLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kBreak),
        child: Column(
          children: [
            Icon(
              Icons.nature_people_rounded,
              size: 44,
              color: AppColors.grassGreen.withValues(alpha: 0.45),
            ),
            const SizedBox(height: _kGap),
            Text(
              'No challenges completed yet',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Complete your first outdoor challenge to see your history here.',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textMuted.withValues(alpha: 0.7),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
