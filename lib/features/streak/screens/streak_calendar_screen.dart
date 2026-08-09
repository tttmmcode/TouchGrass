import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/completion_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/challenge_providers.dart';
import '../../../providers/progression_providers.dart';
import '../../../providers/user_providers.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';

class StreakCalendarScreen extends ConsumerStatefulWidget {
  const StreakCalendarScreen({super.key});

  @override
  ConsumerState<StreakCalendarScreen> createState() =>
      _StreakCalendarScreenState();
}

class _StreakCalendarScreenState extends ConsumerState<StreakCalendarScreen> {
  DateTime _displayMonth = DateTime.now();

  void _prevMonth() => setState(() {
        _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
      });

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_displayMonth.year, _displayMonth.month + 1);
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _displayMonth = next);
  }

  bool get _canGoNext {
    final now = DateTime.now();
    return _displayMonth.year < now.year ||
        (_displayMonth.year == now.year && _displayMonth.month < now.month);
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final completionsAsync = ref.watch(recentCompletionsProvider);
    final progressionAsync = ref.watch(progressionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final user = userAsync.valueOrNull;
    final completions = completionsAsync.valueOrNull ?? const [];
    final progression = progressionAsync.valueOrNull;

    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface =
        isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onSurface =
        isDark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight;
    final outline =
        isDark ? AppColors.outlineDark : AppColors.outlineLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Streak Calendar',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Top stats ──────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal, 8, AppSpacing.screenHorizontal, 0),
              sliver: SliverToBoxAdapter(
                child: _TopStats(
                  user: user,
                  progression: progression,
                  surface: surface,
                  onSurface: onSurface,
                  outline: outline,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),

            // ── Month navigator ────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal),
              sliver: SliverToBoxAdapter(
                child: _MonthNavigator(
                  displayMonth: _displayMonth,
                  canGoNext: _canGoNext,
                  onPrev: _prevMonth,
                  onNext: _nextMonth,
                  onSurface: onSurface,
                  outline: outline,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),

            // ── Calendar grid ──────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal),
              sliver: SliverToBoxAdapter(
                child: _CalendarGrid(
                  displayMonth: _displayMonth,
                  completions: completions,
                  user: user,
                  surface: surface,
                  onSurface: onSurface,
                  outline: outline,
                  isDark: isDark,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),

            // ── Legend ─────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal),
              sliver: SliverToBoxAdapter(
                child: _Legend(surface: surface, outline: outline),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }
}

// ── Top stats ─────────────────────────────────────────────────────────────────

class _TopStats extends StatelessWidget {
  const _TopStats({
    required this.user,
    required this.progression,
    required this.surface,
    required this.onSurface,
    required this.outline,
  });

  final UserModel? user;
  final dynamic progression; // ProgressionModel?
  final Color surface;
  final Color onSurface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final streak = user?.streak ?? 0;
    final longest = user?.longestStreak ?? 0;
    final rainyAvail = user?.rainyDaysAvailable ?? 0;
    final rainyUsed = user?.rainyDaysUsed ?? 0;

    return Row(
      children: [
        _StatBox(
          icon: '🔥',
          label: 'Current',
          value: '$streak',
          sub: streak == 1 ? 'day' : 'days',
          color: AppColors.streakOrange,
          surface: surface,
          onSurface: onSurface,
          outline: outline,
        ),
        const SizedBox(width: AppSpacing.md),
        _StatBox(
          icon: '🏆',
          label: 'Longest',
          value: '$longest',
          sub: longest == 1 ? 'day' : 'days',
          color: AppColors.achievementGold,
          surface: surface,
          onSurface: onSurface,
          outline: outline,
        ),
        const SizedBox(width: AppSpacing.md),
        _StatBox(
          icon: '🌧️',
          label: 'Rainy Days',
          value: '$rainyAvail',
          sub: 'left ($rainyUsed used)',
          color: AppColors.skyBlue,
          surface: surface,
          onSurface: onSurface,
          outline: outline,
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.surface,
    required this.onSurface,
    required this.outline,
  });

  final String icon;
  final String label;
  final String value;
  final String sub;
  final Color color;
  final Color surface;
  final Color onSurface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: outline, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.sm),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: onSurface.withValues(alpha: 0.40),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Month navigator ───────────────────────────────────────────────────────────

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.displayMonth,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.onSurface,
    required this.outline,
  });

  final DateTime displayMonth;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Color onSurface;
  final Color outline;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: onSurface),
          onPressed: onPrev,
          tooltip: 'Previous month',
        ),
        Text(
          '${_months[displayMonth.month - 1]} ${displayMonth.year}',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: onSurface,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right_rounded,
            color: canGoNext ? onSurface : outline,
          ),
          onPressed: canGoNext ? onNext : null,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

// ── Calendar grid ─────────────────────────────────────────────────────────────

/// Formats a calendar-day [DateTime] (year/month/day only) as "yyyy-MM-dd".
/// Must stay in sync with [UserRepository.dateKeyForCalendarDay] — both
/// derive keys for the same [UserModel.frozenDates] values.
@visibleForTesting
String dateKeyForDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

@visibleForTesting
enum CalendarDayState { future, today, completed, rainyDay, missed }

/// Pure day-state resolution for one calendar cell — extracted from
/// [_CalendarGrid] so the frozen/missed/completed/future logic (and its
/// DST-safety, calendar-field-arithmetic requirement) is directly
/// unit-testable without building a widget tree. [now] and [userCreatedAt]
/// are passed in rather than read from `DateTime.now()` so tests are
/// deterministic; callers must pass local (not UTC) values.
@visibleForTesting
CalendarDayState resolveCalendarDayState({
  required DateTime day,
  required DateTime now,
  required Set<String> completedDates,
  required Set<String> frozenDates,
  DateTime? userCreatedAt,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final dayOnly = DateTime(day.year, day.month, day.day);
  final key = dateKeyForDay(dayOnly);

  if (dayOnly.isAfter(today)) return CalendarDayState.future;
  if (dayOnly == today) {
    return completedDates.contains(key)
        ? CalendarDayState.completed
        : CalendarDayState.today;
  }

  if (completedDates.contains(key)) return CalendarDayState.completed;

  // If the user was created after this date, it's not a missed day.
  if (userCreatedAt != null) {
    final created =
        DateTime(userCreatedAt.year, userCreatedAt.month, userCreatedAt.day);
    if (dayOnly.isBefore(created)) return CalendarDayState.future;
  }

  if (frozenDates.contains(key)) return CalendarDayState.rainyDay;

  return CalendarDayState.missed;
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.displayMonth,
    required this.completions,
    required this.user,
    required this.surface,
    required this.onSurface,
    required this.outline,
    required this.isDark,
  });

  final DateTime displayMonth;
  final List<CompletionModel> completions;
  final UserModel? user;
  final Color surface;
  final Color onSurface;
  final Color outline;
  final bool isDark;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Build a set of completed date keys "yyyy-MM-dd" for O(1) lookup.
  Set<String> _completedDates() {
    return completions.map((c) {
      final d = c.completedAt.toLocal();
      return dateKeyForDay(DateTime(d.year, d.month, d.day));
    }).toSet();
  }

  CalendarDayState _stateFor(
    DateTime day,
    Set<String> completedDates,
    Set<String> frozenDates,
  ) {
    // createdAt is stored/parsed as UTC — convert to local before extracting
    // the calendar day so it's compared in the same reference frame as
    // `day` (built from local calendar fields), the same DST-safety
    // reasoning as UserRepository.awardCompletionRewards.
    return resolveCalendarDayState(
      day: day,
      now: DateTime.now(),
      completedDates: completedDates,
      frozenDates: frozenDates,
      userCreatedAt: user?.createdAt.toLocal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedDates = _completedDates();
    final frozenDates = user?.frozenDates.toSet() ?? const <String>{};
    final firstOfMonth = DateTime(displayMonth.year, displayMonth.month, 1);
    // weekday: 1=Mon…7=Sun, grid starts Monday
    final startOffset = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth =
        DateTime(displayMonth.year, displayMonth.month + 1, 0).day;

    return Column(
      children: [
        // Weekday headers
        Row(
          children: _weekdays
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        // Day cells
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.05,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: startOffset + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startOffset) return const SizedBox.shrink();
            final dayNum = index - startOffset + 1;
            final day = DateTime(displayMonth.year, displayMonth.month, dayNum);
            final state = _stateFor(day, completedDates, frozenDates);
            return _DayCell(
              date: day,
              dayNum: dayNum,
              state: state,
              surface: surface,
              onSurface: onSurface,
              outline: outline,
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.dayNum,
    required this.state,
    required this.surface,
    required this.onSurface,
    required this.outline,
  });

  final DateTime date;
  final int dayNum;
  final CalendarDayState state;
  final Color surface;
  final Color onSurface;
  final Color outline;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _semanticLabel {
    final dateLabel = '${_months[date.month - 1]} ${date.day}';
    return switch (state) {
      CalendarDayState.completed => '$dateLabel, challenge completed',
      CalendarDayState.rainyDay => '$dateLabel, Rainy Day freeze used',
      CalendarDayState.missed => '$dateLabel, missed',
      CalendarDayState.today => '$dateLabel, today',
      CalendarDayState.future => dateLabel,
    };
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    Widget? icon;
    BoxBorder? border;

    switch (state) {
      case CalendarDayState.completed:
        bg = AppColors.grassGreen;
        textColor = Colors.white;
        icon = const Icon(Icons.check_rounded, color: Colors.white, size: 10);
      case CalendarDayState.rainyDay:
        bg = AppColors.skyBlue.withValues(alpha: 0.25);
        textColor = AppColors.skyBlue;
        icon = const Text('🌧', style: TextStyle(fontSize: 9));
        border = Border.all(color: AppColors.skyBlue.withValues(alpha: 0.5));
      case CalendarDayState.missed:
        bg = AppColors.error.withValues(alpha: 0.12);
        textColor = AppColors.error.withValues(alpha: 0.7);
        icon = null;
        border = Border.all(color: AppColors.error.withValues(alpha: 0.25));
      case CalendarDayState.today:
        bg = AppColors.forestGreen.withValues(alpha: 0.15);
        textColor = AppColors.forestGreen;
        border = Border.all(color: AppColors.forestGreen, width: 1.5);
        icon = null;
      case CalendarDayState.future:
        bg = Colors.transparent;
        textColor = onSurface.withValues(alpha: 0.25);
        icon = null;
    }

    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: border,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNum',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            ?icon,
          ],
        ),
      ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.surface, required this.outline});

  final Color surface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: [
            const _LegendItem(color: AppColors.grassGreen, label: 'Completed'),
            _LegendItem(color: AppColors.skyBlue.withValues(alpha: 0.5), label: 'Rainy Day'),
            _LegendItem(color: AppColors.error.withValues(alpha: 0.4), label: 'Missed'),
            _LegendItem(
              color: AppColors.forestGreen.withValues(alpha: 0.25),
              label: 'Today',
              hasBorder: true,
              borderColor: AppColors.forestGreen,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.hasBorder = false,
    this.borderColor,
  });

  final Color color;
  final String label;
  final bool hasBorder;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
            border: hasBorder
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
          ),
          child: const SizedBox(width: 14, height: 14),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.onSurfaceDark
                : AppColors.onSurfaceLight,
          ),
        ),
      ],
    );
  }
}
