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
        ),
      ],
    );
  }
}

// ── Calendar grid ─────────────────────────────────────────────────────────────

enum _DayState { future, today, completed, rainyDay, missed }

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
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }).toSet();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  _DayState _stateFor(DateTime day, Set<String> completedDates) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayOnly = DateTime(day.year, day.month, day.day);

    if (dayOnly.isAfter(today)) return _DayState.future;
    if (dayOnly == today) {
      return completedDates.contains(_dateKey(dayOnly))
          ? _DayState.completed
          : _DayState.today;
    }

    if (completedDates.contains(_dateKey(dayOnly))) return _DayState.completed;

    // If the user was created after this date, it's not a missed day.
    if (user != null) {
      final created =
          DateTime(user!.createdAt.year, user!.createdAt.month, user!.createdAt.day);
      if (dayOnly.isBefore(created)) return _DayState.future;
    }

    // Check if this could be a rainy day: a Firestore event per rainy-day-used
    // isn't tracked granularly per-day, so we approximate: if the streak was
    // maintained without a completion doc, show rainy-day color. Since we can't
    // easily determine per-day rainy use from the current data model without
    // extra reads, we mark missed days as missed and leave rainy-day display
    // for the streak stats summary above.
    return _DayState.missed;
  }

  @override
  Widget build(BuildContext context) {
    final completedDates = _completedDates();
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
            final state = _stateFor(day, completedDates);
            return _DayCell(
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
    required this.dayNum,
    required this.state,
    required this.surface,
    required this.onSurface,
    required this.outline,
  });

  final int dayNum;
  final _DayState state;
  final Color surface;
  final Color onSurface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    Widget? icon;
    BoxBorder? border;

    switch (state) {
      case _DayState.completed:
        bg = AppColors.grassGreen;
        textColor = Colors.white;
        icon = const Icon(Icons.check_rounded, color: Colors.white, size: 10);
      case _DayState.rainyDay:
        bg = AppColors.skyBlue.withValues(alpha: 0.25);
        textColor = AppColors.skyBlue;
        icon = const Text('🌧', style: TextStyle(fontSize: 9));
        border = Border.all(color: AppColors.skyBlue.withValues(alpha: 0.5));
      case _DayState.missed:
        bg = AppColors.error.withValues(alpha: 0.12);
        textColor = AppColors.error.withValues(alpha: 0.7);
        icon = null;
        border = Border.all(color: AppColors.error.withValues(alpha: 0.25));
      case _DayState.today:
        bg = AppColors.forestGreen.withValues(alpha: 0.15);
        textColor = AppColors.forestGreen;
        border = Border.all(color: AppColors.forestGreen, width: 1.5);
        icon = null;
      case _DayState.future:
        bg = Colors.transparent;
        textColor = onSurface.withValues(alpha: 0.25);
        icon = null;
    }

    return DecoratedBox(
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
            borderRadius: BorderRadius.circular(4),
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
