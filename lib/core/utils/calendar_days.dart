/// Whole calendar days from [from]'s date to [to]'s date (audit D-17).
///
/// Only the year/month/day fields are used, re-built as UTC dates, so the
/// count is exact across daylight-saving changes. `difference().inDays`
/// between two *local* midnights comes out one short after a spring-forward
/// night (23 hours). Pass both values in the same time zone — normally
/// `.toLocal()`, so "today" is the user's calendar day.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
