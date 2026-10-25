import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/error_service.dart';
import '../../../core/utils/avatar_url.dart';
import '../../../models/leaderboard_entry_model.dart';
import '../../../models/league_definition.dart';
import '../../../providers/leaderboard_providers.dart';
import '../../../providers/settings_providers.dart';
import '../../../services/leaderboard_service.dart';
import '../../../services/perf_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/error_retry_view.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/loading_widgets.dart';
import '../../leagues/screens/leagues_screen.dart';
import '../widgets/league_background.dart';

/// Top-level Leaderboard destination — hosts two tabs sharing one "Leaderboard"
/// header: Rankings (this file's original single-screen content) and Leagues
/// (moved here from its former standalone Profile Settings destination; see
/// LeaguesTabContent in leagues_screen.dart). Both tabs read the same
/// underlying providers as before — no league/leaderboard state is
/// duplicated, only the navigation shell around them changed.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            ColoredBox(
              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: top + AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.screenHorizontal,
                      bottom: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Leaderboard',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? AppColors.onSurfaceDark
                                : AppColors.onSurfaceLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    labelColor: AppColors.forestGreen,
                    unselectedLabelColor: isDark
                        ? AppColors.onSurfaceVariantDark
                        : AppColors.onSurfaceVariantLight,
                    indicatorColor: AppColors.forestGreen,
                    labelStyle: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    tabs: const [
                      Tab(text: 'Rankings', height: 44),
                      Tab(text: 'Leagues', height: 44),
                    ],
                  ),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [_RankingsTab(), LeaguesTabContent()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingsTab extends ConsumerStatefulWidget {
  const _RankingsTab();

  @override
  ConsumerState<_RankingsTab> createState() => _RankingsTabState();
}

class _RankingsTabState extends ConsumerState<_RankingsTab> {
  late int _selectedIdx;
  final _navScrollCtrl = ScrollController();
  Trace? _loadTrace;
  bool _traceCompleted = false;

  @override
  void initState() {
    super.initState();
    // Start on the user's current league; fall back to Seedling.
    final user = ref.read(currentUserLeagueProvider);
    _selectedIdx = user != null ? user.index : 0;
    _loadTrace = PerfService.startTrace(PerfService.traceLeaderboardLoad);
  }

  @override
  void dispose() {
    _navScrollCtrl.dispose();
    super.dispose();
  }

  LeagueDef get _selected => LeagueDef.all[_selectedIdx];

  void _selectLeague(int idx) {
    if (idx == _selectedIdx) return;
    setState(() => _selectedIdx = idx);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myLeague = ref.watch(currentUserLeagueProvider);
    final currentUid = ref.watch(currentUidProvider);
    final boardAsync = ref.watch(leagueBoardProvider(_selected.id));
    final reducedMotion = ref.watch(reducedMotionProvider);

    if (!_traceCompleted && boardAsync.hasValue) {
      _traceCompleted = true;
      _loadTrace?.stop().ignore();
    }

    return Scaffold(
      body: Column(
        children: [
          // ── League navigation bar ───────────────────────────────────────
          _LeagueNavBar(
            selectedIdx: _selectedIdx,
            myLeague: myLeague,
            onSelect: _selectLeague,
            scrollCtrl: _navScrollCtrl,
            isDark: isDark,
          ),

          // ── League header + board, with the league's static background
          // behind both. The nav bar above and self-position footer below
          // keep their own solid ColoredBox backgrounds (unchanged) rather
          // than joining this Stack, since the motif is only meant to sit
          // behind the header/board content it was designed to accompany.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: LeagueBackground(league: _selected)),
                Column(
                  children: [
                    _LeagueHeader(league: _selected, isDark: isDark),
                    Expanded(
                      child: boardAsync.when(
                        loading: () => const _BoardLoading(),
                        error: (e, _) => _BoardError(
                          error: e,
                          onRetry: () =>
                              ref.invalidate(leagueBoardProvider(_selected.id)),
                        ),
                        data: (entries) => entries.isEmpty
                            ? _EmptyBoard(league: _selected)
                            : _Board(
                                entries: entries,
                                currentUid: currentUid,
                                isDark: isDark,
                                reducedMotion: reducedMotion,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Self-position footer ────────────────────────────────────────
          _SelfPositionBar(
            boardAsync: boardAsync,
            myLeague: myLeague,
            selectedLeague: _selected,
            currentUid: currentUid,
            isDark: isDark,
            onJumpToMyLeague: () => _selectLeague(myLeague?.index ?? 0),
          ),
        ],
      ),
    );
  }
}

// ── League navigation bar ─────────────────────────────────────────────────────

class _LeagueNavBar extends StatelessWidget {
  const _LeagueNavBar({
    required this.selectedIdx,
    required this.myLeague,
    required this.onSelect,
    required this.scrollCtrl,
    required this.isDark,
  });

  final int selectedIdx;
  final LeagueDef? myLeague;
  final ValueChanged<int> onSelect;
  final ScrollController scrollCtrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The "Leaderboard" title now lives once in the shared tab header
          // (LeaderboardScreen) above both the Rankings and Leagues tabs —
          // this bar only needs its own top inset before the chip row.
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 72,
            child: ListView.separated(
              controller: scrollCtrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
              ),
              itemCount: LeagueDef.all.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final league = LeagueDef.all[i];
                final isSelected = i == selectedIdx;
                final isMyLeague = league.id == myLeague?.id;
                final isLocked =
                    myLeague != null && league.index > myLeague!.index;

                return _LeagueChip(
                  league: league,
                  isSelected: isSelected,
                  isMyLeague: isMyLeague,
                  isLocked: isLocked,
                  isDark: isDark,
                  onTap: () => onSelect(i),
                );
              },
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: isDark
                ? AppColors.outlineDark.withValues(alpha: 0.4)
                : AppColors.outlineLight.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _LeagueChip extends StatelessWidget {
  const _LeagueChip({
    required this.league,
    required this.isSelected,
    required this.isMyLeague,
    required this.isLocked,
    required this.isDark,
    required this.onTap,
  });

  final LeagueDef league;
  final bool isSelected;
  final bool isMyLeague;
  final bool isLocked;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? league.color.withValues(alpha: isDark ? 0.25 : 0.12)
        : Colors.transparent;
    final borderColor = isSelected
        ? league.color
        : (isDark
              ? AppColors.outlineDark.withValues(alpha: 0.3)
              : AppColors.outlineLight.withValues(alpha: 0.5));
    final textColor = isSelected
        ? league.color
        : (isDark
              ? AppColors.onSurfaceVariantDark
              : AppColors.onSurfaceVariantLight);
    // Locked leagues are still visible and tappable (to preview), but
    // visually greyed out so they read as unavailable at a glance — the
    // lock emoji alone wasn't a strong enough signal on its own.
    final contentOpacity = isLocked ? 0.4 : 1.0;

    final semanticLabel = StringBuffer('${league.name} League')
      ..write(isMyLeague ? ', your league' : '')
      ..write(isLocked ? ', locked' : '')
      ..write(isSelected ? ', selected' : '');

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel.toString(),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standardCurve,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Opacity(
              opacity: contentOpacity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Always the league's own emoji — never substitute a
                      // generic lock glyph. Locked leagues are already
                      // communicated visually via the Opacity(0.4) wrapper
                      // around this whole Column and non-visually via the
                      // Semantics label's ", locked" suffix below, so the
                      // league keeps its identity even before it's unlocked.
                      Text(league.emoji, style: const TextStyle(fontSize: 22)),
                      if (isMyLeague)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: league.color,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(width: 8, height: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    league.name,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── League header ─────────────────────────────────────────────────────────────

class _LeagueHeader extends StatelessWidget {
  const _LeagueHeader({required this.league, required this.isDark});

  final LeagueDef league;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        10,
        AppSpacing.screenHorizontal,
        8,
      ),
      child: Row(
        children: [
          Text(league.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            '${league.name} League',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: league.color,
            ),
          ),
          const Spacer(),
          // Isolated so the 30s-ticking countdown only rebuilds this row,
          // not the whole leaderboard screen (and its list of entries).
          _ResetCountdown(isDark: isDark),
        ],
      ),
    );
  }
}

/// Ticking "Resets in Xh Ym" label. A separate [ConsumerWidget] so watching
/// [weeklyResetCountdownProvider] only rebuilds this small row every 30s
/// instead of the entire leaderboard screen (header, nav bar, board list).
class _ResetCountdown extends ConsumerWidget {
  const _ResetCountdown({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resetLabel =
        ref.watch(weeklyResetCountdownProvider).valueOrNull ?? '…';
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 13, color: muted),
        const SizedBox(width: 4),
        Text(
          'Resets in $resetLabel',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    );
  }
}

// ── Board ─────────────────────────────────────────────────────────────────────

class _Board extends StatelessWidget {
  const _Board({
    required this.entries,
    required this.currentUid,
    required this.isDark,
    required this.reducedMotion,
  });

  final List<LeaderboardEntryModel> entries;
  final String? currentUid;
  final bool isDark;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    const service = LeaderboardService();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: entries.length + (_hasHeader(total) ? 1 : 0),
      itemBuilder: (context, rawIdx) {
        // "TOP THIS WEEK" separator appears after the leading top performers.
        if (_hasHeader(total) && rawIdx == AppConstants.promotionZoneCount) {
          return const _SectionDivider(
            label: 'TOP THIS WEEK',
            color: AppColors.achievementGold,
          );
        }

        final entryIdx =
            _hasHeader(total) && rawIdx > AppConstants.promotionZoneCount
            ? rawIdx - 1
            : rawIdx;
        if (entryIdx >= total) return const SizedBox.shrink();
        final entry = entries[entryIdx];
        final isMe = entry.userId == currentUid;
        final isTopPerformer = service.isTopPerformer(entry.rank, total);

        return _RankRow(
          entry: entry,
          isCurrentUser: isMe,
          isTopPerformer: isTopPerformer,
          isDark: isDark,
          index: entryIdx,
          reducedMotion: reducedMotion,
        );
      },
    );
  }

  bool _hasHeader(int total) => total > AppConstants.promotionZoneCount;
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Divider(color: color.withValues(alpha: 0.35), thickness: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Divider(color: color.withValues(alpha: 0.35), thickness: 1),
          ),
        ],
      ),
    );
  }
}

// ── Rank row ──────────────────────────────────────────────────────────────────

class _RankRow extends StatefulWidget {
  const _RankRow({
    required this.entry,
    required this.isCurrentUser,
    required this.isTopPerformer,
    required this.isDark,
    required this.index,
    required this.reducedMotion,
  });

  final LeaderboardEntryModel entry;
  final bool isCurrentUser;
  final bool isTopPerformer;
  final bool isDark;
  final int index;
  final bool reducedMotion;

  @override
  State<_RankRow> createState() => _RankRowState();
}

class _RankRowState extends State<_RankRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (widget.reducedMotion) {
      _ctrl.value = 1.0;
      return;
    }
    final delay = Duration(milliseconds: (widget.index * 30).clamp(0, 500));
    Future<void>.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _rowBg(BuildContext context) {
    if (widget.isCurrentUser) {
      return AppColors.grassGreen.withValues(alpha: 0.12);
    }
    if (widget.isTopPerformer) {
      return AppColors.grassGreen.withValues(alpha: 0.07);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final entry = widget.entry;
    final isMe = widget.isCurrentUser;
    final rank = entry.rank;

    final textStrong = isDark
        ? AppColors.onSurfaceDark
        : AppColors.onSurfaceLight;
    final textMuted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    final rankColor = switch (rank) {
      1 => const Color(0xFFFFB800),
      2 => const Color(0xFFB0B7BF),
      3 => const Color(0xFFCD7F32),
      _ => isMe ? AppColors.grassGreen : textMuted,
    };

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ColoredBox(
          color: _rowBg(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Rank
                SizedBox(
                  width: 36,
                  child: Text(
                    '#$rank',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: rankColor,
                    ),
                  ),
                ),

                // Avatar
                _Avatar(entry: entry, isMe: isMe, size: 38),
                const SizedBox(width: 10),

                // Name + streak
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isMe ? AppColors.grassGreen : textStrong,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.grassGreen,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusFull,
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                child: Text(
                                  'YOU',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            size: 11,
                            color: Colors.deepOrange,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${entry.streak}',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceVariantDark
                                  : AppColors.surfaceVariantLight,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              child: Text(
                                'Lv.${entry.level}',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isMe
                                      ? AppColors.grassGreen
                                      : textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Weekly XP badge
                _XpBadge(weeklyXp: entry.weeklyXp, isMe: isMe),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.isMe, required this.size});

  final LeaderboardEntryModel entry;
  final bool isMe;
  final double size;

  /// Other users' photos only load from the app's own avatar storage or
  /// Google's profile-photo host (audit N-6); anything else shows initials.
  static String? _loadableUrl(String? url) {
    final bucket = Firebase.apps.isEmpty
        ? null
        : Firebase.app().options.storageBucket;
    return isTrustedAvatarUrl(url, appStorageBucket: bucket) ? url : null;
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _loadableUrl(entry.photoUrl);
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isMe
              ? Border.all(color: AppColors.grassGreen, width: 2)
              : null,
        ),
        child: ClipOval(
          child: photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => const ShimmerBox(),
                  errorWidget: (ctx, url, err) => InitialsAvatar(
                    initials: entry.initials,
                    backgroundColor: isMe
                        ? AppColors.forestGreen
                        : AppColors.grassGreen.withValues(alpha: 0.20),
                    textColor: isMe ? Colors.white : AppColors.forestGreen,
                    fontSize: 13,
                  ),
                )
              : InitialsAvatar(
                  initials: entry.initials,
                  backgroundColor: isMe
                      ? AppColors.forestGreen
                      : AppColors.grassGreen.withValues(alpha: 0.20),
                  textColor: isMe ? Colors.white : AppColors.forestGreen,
                  fontSize: 13,
                ),
        ),
      ),
    );
  }
}

// ── XP badge ──────────────────────────────────────────────────────────────────

class _XpBadge extends StatelessWidget {
  const _XpBadge({required this.weeklyXp, required this.isMe});

  final int weeklyXp;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [AppColors.grassGreen, AppColors.forestGreen],
              )
            : AppColors.gradientGold,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 11, color: Colors.white),
            const SizedBox(width: 2),
            Text(
              '$weeklyXp',
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

// ── Self-position footer ──────────────────────────────────────────────────────

class _SelfPositionBar extends ConsumerWidget {
  const _SelfPositionBar({
    required this.boardAsync,
    required this.myLeague,
    required this.selectedLeague,
    required this.currentUid,
    required this.isDark,
    required this.onJumpToMyLeague,
  });

  final AsyncValue<List<LeaderboardEntryModel>> boardAsync;
  final LeagueDef? myLeague;
  final LeagueDef selectedLeague;
  final String? currentUid;
  final bool isDark;
  final VoidCallback onJumpToMyLeague;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dividerColor = isDark
        ? AppColors.outlineDark.withValues(alpha: 0.4)
        : AppColors.outlineLight.withValues(alpha: 0.6);
    final surfaceBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariantLight;

    // If browsing a different league than the user's own, show a "Jump" bar.
    if (myLeague != null && selectedLeague.id != myLeague!.id) {
      return ColoredBox(
        color: surfaceBg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, thickness: 1, color: dividerColor),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.sm,
                AppSpacing.screenHorizontal,
                AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
              ),
              child: Row(
                children: [
                  Text(
                    '${myLeague!.emoji} You compete in ${myLeague!.name}',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.onSurfaceVariantDark
                          : AppColors.onSurfaceVariantLight,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onJumpToMyLeague,
                    child: Text(
                      'Jump →',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: myLeague!.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // In the user's own league — show their rank.
    final entry = boardAsync.valueOrNull
        ?.where((e) => e.userId == currentUid)
        .firstOrNull;

    if (entry == null) return const SizedBox.shrink();

    return ColoredBox(
      color: AppColors.grassGreen.withValues(alpha: isDark ? 0.15 : 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.grassGreen.withValues(alpha: 0.3),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: [
                Text(
                  '#${entry.rank}',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.grassGreen,
                  ),
                ),
                const SizedBox(width: 10),
                _Avatar(entry: entry, isMe: true, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your position this week',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.onSurfaceDark
                          : AppColors.onSurfaceLight,
                    ),
                  ),
                ),
                _XpBadge(weeklyXp: entry.weeklyXp, isMe: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading / error / empty ───────────────────────────────────────────────────

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏆', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 16),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: AppColors.achievementGold,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading explorers…',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.onSurfaceVariantDark
                  : AppColors.onSurfaceVariantLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardError extends StatelessWidget {
  const _BoardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ErrorRetryView(
      message: ErrorService.friendlyMessage(error),
      onRetry: onRetry,
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.league});

  final LeagueDef league;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.onSurfaceVariantDark
        : AppColors.onSurfaceVariantLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(league.emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              'No explorers in ${league.name} yet',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Complete a challenge this week\nto appear on the board!',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: muted.withValues(alpha: 0.7),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
