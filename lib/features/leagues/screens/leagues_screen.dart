import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/league_definition.dart';
import '../../../providers/leaderboard_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

// ── League data ───────────────────────────────────────────────────────────────
//
// Sourced entirely from LeagueDef (lib/models/league_definition.dart) — the
// single canonical league catalog also used by the leaderboard/promotion
// logic, so this screen can never drift from it again.

int _leagueIndexForXp(int xp) => LeagueDef.forXp(xp).index;

/// XP fraction within the current league (0.0–1.0). Always 1.0 for Aurora.
double _progressInLeague(int xp, int idx) {
  final league = LeagueDef.all[idx];
  if (league.maxXp == -1) return 1.0;
  final range = league.maxXp - league.minXp + 1;
  return ((xp - league.minXp) / range).clamp(0.0, 1.0);
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Standalone Leagues screen — kept for anything that still wants Leagues
/// as its own full page, but no longer routed to directly; the Leaderboard
/// screen's "Leagues" tab renders [LeaguesTabContent] itself instead (see
/// leaderboard_screen.dart). Both use the exact same content/state, so
/// there's no duplicated league logic between them.
class LeaguesScreen extends StatelessWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leagues'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const LeaguesTabContent(),
    );
  }
}

/// The actual Leagues content (current-league hero + full league ladder) —
/// extracted so it can be embedded directly inside Leaderboard's "Leagues"
/// tab without a second, redundant AppBar.
class LeaguesTabContent extends ConsumerWidget {
  const LeaguesTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final reducedMotion = ref.watch(reducedMotionProvider);
    final xp = user?.xp ?? 0;
    final leagueIdx = _leagueIndexForXp(xp);
    final league = LeagueDef.all[leagueIdx];
    final progress = _progressInLeague(xp, leagueIdx);

    final strong = isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return CustomScrollView(
      slivers: [
        // ── Current league hero ────────────────────────────────────────
        SliverToBoxAdapter(
          child: _LeagueHero(
            league: league,
            xp: xp,
            progress: progress,
            leagueIdx: leagueIdx,
            isDark: isDark,
            reducedMotion: reducedMotion,
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
            itemCount: LeagueDef.all.length,
            itemBuilder: (context, i) {
              // Render in reverse: Aurora at top, Seedling at bottom.
              final idx = LeagueDef.all.length - 1 - i;
              return _LadderRow(
                league: LeagueDef.all[idx],
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
    required this.reducedMotion,
  });

  final LeagueDef league;
  final int xp;
  final double progress;
  final int leagueIdx;
  final bool isDark;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final isTop = league.maxXp == -1;
    final nextLeague = isTop ? null : LeagueDef.all[leagueIdx + 1];
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
                  Text(league.emoji, style: const TextStyle(fontSize: 48)),
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
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 1000),
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
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: SizedBox(
                              height: 8,
                              width: constraints.maxWidth,
                            ),
                          ),
                          if (fillW > 0)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: league.color,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull,
                                ),
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
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 14,
                              color: league.color,
                            ),
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

              // Weekly reset chip — isolated Consumer so the 30s-ticking
              // countdown only rebuilds this chip, not the whole hero card
              // (and, transitively, the whole league ladder screen).
              _ResetChip(isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ticking "Leagues reset in Xh Ym" chip. A separate [ConsumerWidget] —
/// shares the same 30-second source as the leaderboard screen instead of a
/// second independent Timer — so watching it only rebuilds this chip rather
/// than the whole league ladder.
class _ResetChip extends ConsumerWidget {
  const _ResetChip({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resetLabel =
        ref.watch(weeklyResetCountdownProvider).valueOrNull ?? '—';
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 13, color: muted),
            const SizedBox(width: 5),
            Text(
              'Leagues reset in $resetLabel',
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

  final LeagueDef league;
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
    final surfaceBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isCurrent
              ? league.color.withValues(alpha: isDark ? 0.18 : 0.08)
              : surfaceBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: isCurrent
              ? Border.all(
                  color: league.color.withValues(alpha: 0.5),
                  width: 1.5,
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // Emoji badge
              Text(
                league.emoji,
                style: TextStyle(fontSize: isCurrent ? 28 : 22),
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
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
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
                      league.xpRangeLabel,
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
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.grassGreen,
                    ),
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
