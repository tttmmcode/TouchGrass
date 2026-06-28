import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

// ── League data ───────────────────────────────────────────────────────────────

class _League {
  const _League({
    required this.name,
    required this.emoji,
    required this.color,
    required this.minXp,
    required this.maxXp,
    required this.description,
  });

  final String name;
  final String emoji;
  final Color color;
  final int minXp;
  final int maxXp; // -1 = no upper cap (Aurora)
  final String description;
}

const _leagues = [
  _League(
    name: 'Seedling',
    emoji: '🌱',
    color: Color(0xFF8BC34A),
    minXp: 0,
    maxXp: 299,
    description: 'Just starting your outdoor journey',
  ),
  _League(
    name: 'Sprout',
    emoji: '🌿',
    color: Color(0xFF43A047),
    minXp: 300,
    maxXp: 699,
    description: 'Growing roots in the great outdoors',
  ),
  _League(
    name: 'Wildflower',
    emoji: '🌸',
    color: Color(0xFFE91E8C),
    minXp: 700,
    maxXp: 1499,
    description: 'Blooming with outdoor adventures',
  ),
  _League(
    name: 'Forest',
    emoji: '🌲',
    color: Color(0xFF2E7D32),
    minXp: 1500,
    maxXp: 2999,
    description: 'Deep in the heart of nature',
  ),
  _League(
    name: 'Mountain',
    emoji: '🏔️',
    color: Color(0xFF5C6BC0),
    minXp: 3000,
    maxXp: 5999,
    description: 'Rising above and beyond',
  ),
  _League(
    name: 'Summit',
    emoji: '✨',
    color: Color(0xFFFFB800),
    minXp: 6000,
    maxXp: 9999,
    description: 'At the peak of outdoor excellence',
  ),
  _League(
    name: 'Sky Trail',
    emoji: '🌤️',
    color: Color(0xFF29B6F6),
    minXp: 10000,
    maxXp: 19999,
    description: 'Blazing trails through the sky',
  ),
  _League(
    name: 'Aurora',
    emoji: '🌌',
    color: Color(0xFF7C4DFF),
    minXp: 20000,
    maxXp: -1,
    description: 'A legend of the great outdoors',
  ),
];

int _leagueIndexForXp(int xp) {
  for (int i = _leagues.length - 1; i >= 0; i--) {
    if (xp >= _leagues[i].minXp) return i;
  }
  return 0;
}

/// XP fraction within the current league (0.0–1.0). Always 1.0 for Summit.
double _progressInLeague(int xp, int idx) {
  final league = _leagues[idx];
  if (league.maxXp == -1) return 1.0;
  final range = league.maxXp - league.minXp + 1;
  return ((xp - league.minXp) / range).clamp(0.0, 1.0);
}

/// Human-readable time until next Monday midnight UTC.
String _weeklyResetLabel() {
  final now = DateTime.now().toUtc();
  final daysUntilMonday = (DateTime.monday - now.weekday + 7) % 7;
  final nextMonday = DateTime.utc(
    now.year,
    now.month,
    now.day + (daysUntilMonday == 0 ? 7 : daysUntilMonday),
  );
  final diff = nextMonday.difference(now);
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  if (days > 0) return '${days}d ${hours}h';
  return '${diff.inHours}h ${diff.inMinutes % 60}m';
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LeaguesScreen extends ConsumerStatefulWidget {
  const LeaguesScreen({super.key});

  @override
  ConsumerState<LeaguesScreen> createState() => _LeaguesScreenState();
}

class _LeaguesScreenState extends ConsumerState<LeaguesScreen> {
  late Timer _timer;
  String _resetLabel = _weeklyResetLabel();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _resetLabel = _weeklyResetLabel());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final xp = user?.xp ?? 0;
    final leagueIdx = _leagueIndexForXp(xp);
    final league = _leagues[leagueIdx];
    final progress = _progressInLeague(xp, leagueIdx);

    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // ── Current league hero ────────────────────────────────────────
          SliverToBoxAdapter(
            child: _LeagueHero(
              league: league,
              xp: xp,
              progress: progress,
              leagueIdx: leagueIdx,
              isDark: isDark,
              resetLabel: _resetLabel,
            ),
          ),

          // ── "League Ladder" header ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.lg,
                AppSpacing.screenHorizontal,
                AppSpacing.sm,
              ),
              child: Text(
                'LEAGUE LADDER',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: muted,
                ),
              ),
            ),
          ),

          // ── League list ────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.xxxl,
            ),
            sliver: SliverList.builder(
              itemCount: _leagues.length,
              itemBuilder: (context, i) {
                // Render in reverse: Summit at top, Seedling at bottom.
                final idx = _leagues.length - 1 - i;
                return _LadderRow(
                  league: _leagues[idx],
                  leagueIdx: idx,
                  currentIdx: leagueIdx,
                  userXp: xp,
                  isDark: isDark,
                  strong: strong,
                  muted: muted,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────────────────

class _LeagueHero extends StatelessWidget {
  const _LeagueHero({
    required this.league,
    required this.xp,
    required this.progress,
    required this.leagueIdx,
    required this.isDark,
    required this.resetLabel,
  });

  final _League league;
  final int xp;
  final double progress;
  final int leagueIdx;
  final bool isDark;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    final isTop = league.maxXp == -1;
    final nextLeague = isTop ? null : _leagues[leagueIdx + 1];
    final xpToNext = isTop ? 0 : (league.maxXp + 1) - xp;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              league.color.withValues(alpha: isDark ? 0.25 : 0.12),
              league.color.withValues(alpha: isDark ? 0.10 : 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(
            color: league.color.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    league.emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          league.name,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: league.color,
                          ),
                        ),
                        Text(
                          league.description,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.onSurfaceVariantDark
                                : AppColors.onSurfaceVariantLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // XP progress bar
              if (!isTop) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$xp XP',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: league.color,
                      ),
                    ),
                    Text(
                      '${nextLeague!.minXp} XP to ${nextLeague.name}',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.onSurfaceVariantDark
                            : AppColors.onSurfaceVariantLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LayoutBuilder(
                    builder: (_, constraints) {
                      final fillW = constraints.maxWidth * value;
                      return Stack(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: league.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull),
                            ),
                            child: SizedBox(
                                height: 8, width: constraints.maxWidth),
                          ),
                          if (fillW > 0)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: league.color,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusFull),
                              ),
                              child: SizedBox(height: 8, width: fillW),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$xpToNext XP needed to promote',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.onSurfaceVariantDark
                        : AppColors.onSurfaceVariantLight,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: league.color.withValues(alpha: 0.15),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_rounded,
                                size: 14, color: league.color),
                            const SizedBox(width: 4),
                            Text(
                              '$xp XP · Max League',
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: league.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // Weekly reset chip
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.surfaceVariantLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: isDark
                            ? AppColors.onSurfaceVariantDark
                            : AppColors.onSurfaceVariantLight,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Leagues reset in $resetLabel',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.onSurfaceVariantDark
                              : AppColors.onSurfaceVariantLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ladder row ────────────────────────────────────────────────────────────────

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.league,
    required this.leagueIdx,
    required this.currentIdx,
    required this.userXp,
    required this.isDark,
    required this.strong,
    required this.muted,
  });

  final _League league;
  final int leagueIdx;
  final int currentIdx;
  final int userXp;
  final bool isDark;
  final Color strong;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final isCurrent = leagueIdx == currentIdx;
    final isCompleted = leagueIdx < currentIdx;
    final surfaceBg = isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isCurrent
              ? league.color.withValues(alpha: isDark ? 0.18 : 0.08)
              : surfaceBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: isCurrent
              ? Border.all(color: league.color.withValues(alpha: 0.5), width: 1.5)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              // Emoji badge
              Text(
                league.emoji,
                style: TextStyle(
                  fontSize: isCurrent ? 28 : 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Name + XP range
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          league.name,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: isCurrent ? 16 : 14,
                            fontWeight: FontWeight.w900,
                            color: isCurrent ? league.color : strong,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: league.color,
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              child: Text(
                                'YOU',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      league.maxXp == -1
                          ? '${league.minXp}+ XP'
                          : '${league.minXp}–${league.maxXp} XP',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),

              // Status indicator
              if (isCompleted)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.grassGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.check_rounded,
                        size: 14, color: AppColors.grassGreen),
                  ),
                )
              else if (!isCurrent)
                Text(
                  '${league.minXp - userXp} XP away',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
