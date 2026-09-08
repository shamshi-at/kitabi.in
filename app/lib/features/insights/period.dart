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

/// [now] is injectable for tests; real callers don't pass it.
///
/// [year] only matters for [InsightsPeriod.year] — null means "all time".
/// [month] only matters for [InsightsPeriod.month]: any date inside the wanted
/// month, null meaning this one. The two sub-choices are deliberately
/// symmetrical — a reader who can ask "how was 2025?" should be able to ask
/// "how was August?" (owner report, 8 Sep 2026: there was no way to).
PeriodRange rangeFor(InsightsPeriod period, {DateTime? now, int? year, DateTime? month}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (period) {
    case InsightsPeriod.today:
      return PeriodRange(start: today, end: today.add(const Duration(days: 1)));
    case InsightsPeriod.week:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return PeriodRange(start: monday, end: monday.add(const Duration(days: 7)));
    case InsightsPeriod.month:
      final anchor = month ?? today;
      return PeriodRange(
        start: DateTime(anchor.year, anchor.month, 1),
        // Dart normalizes month 13 to January of next year — the standard
        // "first of next month" trick, correct across every year boundary.
        end: DateTime(anchor.year, anchor.month + 1, 1),
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

// ---------------------------------------------------------------------------
// Recap keys — the URL-safe name of a window
// ---------------------------------------------------------------------------

/// The key a shared recap link carries: `kitabi.in/reader/<handle>/recap/<key>`.
///
/// Six shapes, one per window:
///
/// | window            | key                |
/// |-------------------|--------------------|
/// | today             | `2026-09-08`       |
/// | week              | `2026-w37`         |
/// | month             | `2026-09`          |
/// | year              | `2026`             |
/// | all time          | `all`              |
/// | 3 months          | `90d-2026-09-08`   |
/// | 6 months          | `182d-2026-09-08`  |
///
/// The trailing windows carry their end date because that is all they are —
/// "the 90 days up to the 8th" — and a link has to keep meaning the window it
/// was shared for after the clock has moved on.
///
/// Deliberately derivable: the link needs no token, no round trip and no row,
/// so the share sheet can print it with no network at all. The price is that
/// the *server* must read this same grammar back, and two implementations of
/// one rule is how `shareRouteFor` and the app-site-association files came to
/// disagree about which URLs this app owns (1 Sep 2026). So this is one pure
/// function, `parse_recap_key` in `api/app/services/recap_service.py` is its
/// one mirror, and the two test suites share a fixture table that names the
/// other file.
String recapKeyFor(InsightsPeriod period, PeriodRange range, {int? year}) {
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
  switch (period) {
    case InsightsPeriod.today:
      return day(range.start);
    case InsightsPeriod.week:
      final (isoYear, isoWeek) = isoWeekOf(range.start);
      return '$isoYear-w${_two(isoWeek)}';
    case InsightsPeriod.month:
      return '${range.start.year.toString().padLeft(4, '0')}-${_two(range.start.month)}';
    case InsightsPeriod.threeMonths:
      return '90d-${day(range.end)}';
    case InsightsPeriod.sixMonths:
      return '182d-${day(range.end)}';
    case InsightsPeriod.year:
      return year == null ? 'all' : '$year';
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// The ISO-8601 week-numbering year and week of [date].
///
/// The week-*year* is not always the calendar year: 1 Jan 2027 falls in week 53
/// of 2026, and a recap link that said `2027-w53` would name a week that does
/// not exist. Both come from the Thursday of the date's week, which is the
/// definition ISO uses and the reason it is unambiguous.
(int, int) isoWeekOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstOfYear = DateTime(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(firstOfYear).inDays + 1;
  return (thursday.year, ((dayOfYear - 1) ~/ 7) + 1);
}
