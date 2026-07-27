import '../../data/db/database.dart';
import '../library/session_pages.dart';
import 'period.dart';

/// One finished book for the covers-and-ratings strip under the flagship
/// card. [rating] is the reader's own star rating (Ratings is per-Work, rule
/// 17) — null when the book was finished but never rated, which the strip
/// shows as a plain cover with no badge rather than a zero-star one.
class FinishedBookInfo {
  const FinishedBookInfo({
    required this.workId,
    required this.editionId,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.rating,
  });

  final String workId;
  final String editionId;
  final String title;
  final String author;
  final String? coverUrl;
  final int? rating;
}

/// One cell of the month card's calendar heatmap. [date] is null for the
/// leading/trailing filler that pads the grid to real weekday columns —
/// [isRead]/[isFuture] are meaningless on a filler cell and always false.
class CalendarCell {
  const CalendarCell({required this.date, required this.isRead, required this.isFuture});

  final DateTime? date;
  final bool isRead;
  final bool isFuture;
}

/// Everything the flagship card needs for one window — pure and
/// unit-testable, same shape as [computeInsights]/[computeReadingTimeStats]
/// that it sits alongside. Fields only one or two periods use
/// ([calendarCells], [trendBuckets], [dailyBuckets]) stay null everywhere
/// else rather than being computed and thrown away.
class PeriodSummary {
  const PeriodSummary({
    required this.range,
    required this.totalSeconds,
    required this.pagesRead,
    required this.sittingsCount,
    required this.booksFinished,
    this.previousTotalSeconds,
    this.streakDays,
    this.recentDays,
    this.calendarCells,
    this.trendBuckets,
    this.dailyBuckets,
  });

  final PeriodRange range;
  final int totalSeconds;
  final int pagesRead;
  final int sittingsCount;

  /// Newest-finished-first — the covers strip's source.
  final List<FinishedBookInfo> booksFinished;

  /// Total seconds in the immediately-preceding window of the same period —
  /// null for [InsightsPeriod.year] (the goal-pace note already covers "vs
  /// expected", and "vs last year" would double up on the same idea).
  final int? previousTotalSeconds;

  /// Consecutive days (today backward) with at least one sitting — only set
  /// for [InsightsPeriod.today]. If today has no sitting yet, counts from
  /// yesterday instead of collapsing to zero, so logging late in the day
  /// doesn't read as having broken a streak that's simply still open.
  final int? streakDays;

  /// Whether each of the last 7 calendar days (oldest first, today last) had
  /// a sitting — the daily card's dot row. Only set for
  /// [InsightsPeriod.today]; a trailing week rather than a calendar one,
  /// because a streak doesn't reset at Sunday.
  final List<bool>? recentDays;

  /// Set only for [InsightsPeriod.month].
  final List<CalendarCell>? calendarCells;

  /// Weekly totals (seconds), oldest first — set only for
  /// [InsightsPeriod.threeMonths]/[InsightsPeriod.sixMonths].
  final List<int>? trendBuckets;

  /// Daily totals (seconds), Monday first — set only for
  /// [InsightsPeriod.week].
  final List<int>? dailyBuckets;

  int get booksFinishedCount => booksFinished.length;
}

/// [now] is injectable for tests; real callers never pass it.
PeriodSummary computePeriodSummary({
  required InsightsPeriod period,
  required PeriodRange range,
  required List<ReadingSession> sessions,
  required List<LibraryHit> hits,
  required Map<String, int> ratingsByWorkId,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final liveSessions = sessions.where((s) => s.deletedAt == null).toList();
  final inRange = liveSessions.where((s) => range.contains(s.startedAt)).toList();

  var totalSeconds = 0;
  var pages = 0;
  for (final s in inRange) {
    totalSeconds += s.durationSeconds;
    pages += sessionPagesRead(s) ?? 0;
  }

  int? previousTotalSeconds;
  if (period != InsightsPeriod.year) {
    final previous = previousRangeFor(period, range);
    previousTotalSeconds = liveSessions
        .where((s) => previous.contains(s.startedAt))
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);
  }

  // Same finished-on fallback as computeInsights: not every read book has an
  // explicit finish date (an older row, a CSV import), and without the
  // fallback such a book would silently vanish from every period it's asked
  // about instead of landing in the one it was last touched in.
  DateTime finishedOn(LibraryHit h) => h.entry.finishDate ?? h.entry.updatedAt;
  final finishedHits = hits.where((h) => h.entry.status == 'read' && range.contains(finishedOn(h))).toList()
    ..sort((a, b) => finishedOn(b).compareTo(finishedOn(a)));
  final booksFinished = [
    for (final h in finishedHits)
      FinishedBookInfo(
        workId: h.book.workId,
        editionId: h.book.editionId,
        title: h.book.title,
        author: h.book.authorNames.split(',').first.trim(),
        coverUrl: h.book.coverUrl,
        rating: ratingsByWorkId[h.book.workId],
      ),
  ];

  return PeriodSummary(
    range: range,
    totalSeconds: totalSeconds,
    pagesRead: pages,
    sittingsCount: inRange.length,
    booksFinished: booksFinished,
    previousTotalSeconds: previousTotalSeconds,
    streakDays: period == InsightsPeriod.today ? _streakDays(liveSessions, effectiveNow) : null,
    recentDays: period == InsightsPeriod.today ? _recentDays(liveSessions, effectiveNow) : null,
    calendarCells: period == InsightsPeriod.month ? _monthCells(range, inRange, effectiveNow) : null,
    trendBuckets: period == InsightsPeriod.threeMonths || period == InsightsPeriod.sixMonths
        ? _weeklyBuckets(range, inRange)
        : null,
    dailyBuckets: period == InsightsPeriod.week ? _dailyBuckets(range, inRange) : null,
  );
}

int _streakDays(Iterable<ReadingSession> sessions, DateTime now) {
  final daysWithSession = <DateTime>{
    for (final s in sessions) DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day),
  };
  var cursor = DateTime(now.year, now.month, now.day);
  if (!daysWithSession.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (daysWithSession.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

List<bool> _recentDays(Iterable<ReadingSession> sessions, DateTime now) {
  final daysWithSession = <DateTime>{
    for (final s in sessions) DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day),
  };
  final today = DateTime(now.year, now.month, now.day);
  return [for (var i = 6; i >= 0; i--) daysWithSession.contains(today.subtract(Duration(days: i)))];
}

/// Sunday-first grid (matches the mockup), padded with null-date filler cells
/// so every row is a real week. A day with no sitting past [now] is "future"
/// (dashed in the mockup) rather than "missed" — the two read very
/// differently even though both currently hold zero minutes.
List<CalendarCell> _monthCells(PeriodRange range, Iterable<ReadingSession> inRangeSessions, DateTime now) {
  final readDays = <int>{for (final s in inRangeSessions) s.startedAt.day};
  final daysInMonth = range.lengthInDays;
  final today = DateTime(now.year, now.month, now.day);
  // DateTime.weekday is Mon=1..Sun=7; Sunday-first means Sunday gets column 0.
  final leading = range.start.weekday % 7;
  final trailing = (7 - (leading + daysInMonth) % 7) % 7;

  final cells = <CalendarCell>[
    for (var i = 0; i < leading; i++) const CalendarCell(date: null, isRead: false, isFuture: false),
    for (var day = 1; day <= daysInMonth; day++)
      CalendarCell(
        date: DateTime(range.start.year, range.start.month, day),
        isRead: readDays.contains(day),
        isFuture: DateTime(range.start.year, range.start.month, day).isAfter(today),
      ),
    for (var i = 0; i < trailing; i++) const CalendarCell(date: null, isRead: false, isFuture: false),
  ];
  return cells;
}

List<int> _weeklyBuckets(PeriodRange range, Iterable<ReadingSession> inRangeSessions) {
  final bucketCount = (range.lengthInDays / 7).ceil().clamp(1, 1000);
  final buckets = List<int>.filled(bucketCount, 0);
  for (final s in inRangeSessions) {
    final dayOffset = s.startedAt.difference(range.start).inDays;
    final idx = (dayOffset / 7).floor().clamp(0, bucketCount - 1);
    buckets[idx] += s.durationSeconds;
  }
  return buckets;
}

List<int> _dailyBuckets(PeriodRange range, Iterable<ReadingSession> inRangeSessions) {
  final buckets = List<int>.filled(7, 0);
  for (final s in inRangeSessions) {
    final idx = s.startedAt.difference(range.start).inDays;
    if (idx >= 0 && idx < 7) buckets[idx] += s.durationSeconds;
  }
  return buckets;
}
