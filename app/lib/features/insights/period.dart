/// The windows the redesigned Insights screen scrolls between (27 Jul 2026
/// redesign — one flagship card, reused across every grain a reader might
/// mean by "how's my reading going?"). [year] is the odd one out: it carries
/// its own calendar-year sub-choice (2026 / 2025 / all time) rather than
/// always meaning "this year", which every other period does.
enum InsightsPeriod { today, week, month, threeMonths, sixMonths, year }

/// A concrete `[start, end)` window — start inclusive, end exclusive, so a
/// session starting exactly at midnight on the boundary belongs to the next
/// window, never both.
class PeriodRange {
  const PeriodRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime at) => !at.isBefore(start) && at.isBefore(end);

  int get lengthInDays => end.difference(start).inDays;
}

/// [now] and [year] are injectable for tests; real callers pass neither.
/// [year] only matters for [InsightsPeriod.year] — null means "all time".
PeriodRange rangeFor(InsightsPeriod period, {DateTime? now, int? year}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (period) {
    case InsightsPeriod.today:
      return PeriodRange(start: today, end: today.add(const Duration(days: 1)));
    case InsightsPeriod.week:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return PeriodRange(start: monday, end: monday.add(const Duration(days: 7)));
    case InsightsPeriod.month:
      return PeriodRange(
        start: DateTime(today.year, today.month, 1),
        // Dart normalizes month 13 to January of next year — the standard
        // "first of next month" trick, correct across every year boundary.
        end: DateTime(today.year, today.month + 1, 1),
      );
    case InsightsPeriod.threeMonths:
      return PeriodRange(start: today.subtract(const Duration(days: 90)), end: today);
    case InsightsPeriod.sixMonths:
      return PeriodRange(start: today.subtract(const Duration(days: 182)), end: today);
    case InsightsPeriod.year:
      if (year == null) {
        // All time — 2000 predates every real reader's library (the same
        // sentinel `ReadingSessionsRepository.sessionsSince` already uses),
        // so this range is, in effect, unbounded. It has no "previous"
        // window; computePeriodSummary never asks previousRangeFor for one.
        return PeriodRange(start: DateTime(2000, 1, 1), end: today.add(const Duration(days: 1)));
      }
      return PeriodRange(start: DateTime(year, 1, 1), end: DateTime(year + 1, 1, 1));
  }
}

/// The immediately-preceding window a reader would compare [range] against —
/// "vs last week". Calendar-aware for month/year (so a 31-day month compares
/// against the real length of the previous one, not a fixed 30/31), a plain
/// same-length shift otherwise. Trailing windows (3/6 months) are explicitly
/// *not* calendar quarters (screen-design.md), so their previous window is
/// just the same number of days again, immediately before.
PeriodRange previousRangeFor(InsightsPeriod period, PeriodRange range) {
  switch (period) {
    case InsightsPeriod.today:
      return PeriodRange(start: range.start.subtract(const Duration(days: 1)), end: range.start);
    case InsightsPeriod.week:
      return PeriodRange(start: range.start.subtract(const Duration(days: 7)), end: range.start);
    case InsightsPeriod.month:
      return PeriodRange(
        start: DateTime(range.start.year, range.start.month - 1, 1),
        end: range.start,
      );
    case InsightsPeriod.threeMonths:
    case InsightsPeriod.sixMonths:
      final length = range.end.difference(range.start);
      return PeriodRange(start: range.start.subtract(length), end: range.start);
    case InsightsPeriod.year:
      return PeriodRange(start: DateTime(range.start.year - 1, 1, 1), end: range.start);
  }
}
