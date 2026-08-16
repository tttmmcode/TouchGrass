/// Human-friendly account-age duration for the Profile screen's "Member
/// Since" stat tile, e.g. "2 days" / "3 months" / "1 year" — the tile's own
/// "Member Since" caption already supplies the "member since" framing, so
/// this returns just the duration, not a repeated "Member for" prefix.
///
/// [now] is a parameter (not read internally via `DateTime.now()`) so this
/// stays a pure, directly-testable function.
///
/// Both dates are compared as calendar days in whatever timezone the caller
/// already normalized them to — pass `.toLocal()` values, matching the same
/// timezone-safety pattern used for streak day comparisons elsewhere in this
/// codebase, so "today" isn't thrown off by a UTC/local mismatch.
String memberSinceDuration({
  required DateTime createdAt,
  required DateTime now,
}) {
  final joined = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(joined).inDays;

  if (days <= 0) return 'Today';
  if (days == 1) return '1 day';
  if (days < 30) return '$days days';

  final years = _yearsBetween(joined, today);
  if (years >= 1) return years == 1 ? '1 year' : '$years years';

  final months = _monthsBetween(joined, today);
  return months <= 1 ? '1 month' : '$months months';
}

/// Whole calendar months elapsed from [from] to [to] (never negative).
int _monthsBetween(DateTime from, DateTime to) {
  final months =
      (to.year - from.year) * 12 +
      (to.month - from.month) -
      (to.day < from.day ? 1 : 0);
  return months < 0 ? 0 : months;
}

/// Whole calendar years elapsed from [from] to [to] (never negative).
int _yearsBetween(DateTime from, DateTime to) {
  final crossedAnniversary =
      to.month < from.month || (to.month == from.month && to.day < from.day);
  final years = to.year - from.year - (crossedAnniversary ? 1 : 0);
  return years < 0 ? 0 : years;
}
