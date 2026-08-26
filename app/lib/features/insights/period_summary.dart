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
    this.pageCount,
  });

  final String workId;
  final String editionId;
  final String title;
  final String author;
  final String? coverUrl;
  final int? rating;

  /// Drives the year shelf's spine width — null (no page count) renders at
  /// the minimum width, present but slim, never absent.
  final int? pageCount;
}

/// One cell of the month card's calendar heatmap. [date] is null for the
/// leading/trailing filler that pads the grid to real weekday columns —
/// [isRead]/[isFuture] are meaningless on a filler cell and always false.
class CalendarCell {
  const CalendarCell({
    required this.date,
    required this.isRead,
    required this.isFuture,
    this.isHeavy = false,
  });

  final DateTime? date;
  final bool isRead;
  final bool isFuture;

  /// A top-quartile day by seconds read — the calendar's deep-oxblood tint
  /// (B6 / the card catalogue). Only ever true on a read day, and only once
  /// the month has enough read days for a quartile to mean anything.
  final bool isHeavy;
}

/// One book the reader actually sat with today — the Today ledger's
/// "In hand" section (B3). Ordered by time spent, most first, so the day's
/// main book leads whether it shows as a pair of rows or a section.
class BookInHand {
  const BookInHand({
    required this.libraryEntryId,
    required this.workId,
    required this.editionId,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.seconds,
  });

  final String libraryEntryId;
  final String workId;
  final String editionId;
  final String title;
  final int? currentPage;
  final int? pageCount;
  final int seconds;
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
    this.booksInHand,
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

  /// The books read *today*, most time first — set only for
  /// [InsightsPeriod.today]. Empty when today's sittings can't be joined to a
  /// live entry (a deleted book), which the ledger renders as no section.
  final List<BookInHand>? booksInHand;

  int get booksFinishedCount => booksFinished.length;

  /// Read days over elapsed days — the month pill's "22 of 26 days read".
  /// (0, 0) for periods without a calendar.
  (int, int) get daysReadOfElapsed {
    final cells = calendarCells;
    if (cells == null) return (0, 0);
    final elapsed = cells.where((c) => c.date != null && !c.isFuture).length;
    final read = cells.where((c) => c.isRead).length;
    return (read, elapsed);
  }
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
        pageCount: h.book.pageCount,
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
    booksInHand: period == InsightsPeriod.today ? _booksInHand(inRange, hits) : null,
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

/// The Today ledger's "In hand" list — today's sittings grouped per book,
/// joined back to the live library rows. A sitting whose entry is gone (the
/// book was deleted) is simply skipped: the totals above the section still
/// count it, the section only names what it can still name.
List<BookInHand> _booksInHand(Iterable<ReadingSession> inRange, List<LibraryHit> hits) {
  final secondsByEntry = <String, int>{};
  for (final s in inRange) {
    secondsByEntry[s.libraryEntryId] = (secondsByEntry[s.libraryEntryId] ?? 0) + s.durationSeconds;
  }
  final byEntryId = {for (final h in hits) h.entry.id: h};
  final books = <BookInHand>[
    for (final MapEntry(key: entryId, value: seconds) in secondsByEntry.entries)
      if (byEntryId[entryId] case final hit?)
        BookInHand(
          libraryEntryId: entryId,
          workId: hit.book.workId,
          editionId: hit.book.editionId,
          title: hit.book.title,
          currentPage: hit.entry.currentPage,
          pageCount: hit.book.pageCount,
          seconds: seconds,
        ),
  ]..sort((a, b) => b.seconds.compareTo(a.seconds));
  return books;
}

/// Sunday-first grid (matches the mockup), padded with null-date filler cells
/// so every row is a real week. A day with no sitting past [now] is "future"
/// (dashed in the mockup) rather than "missed" — the two read very
/// differently even though both currently hold zero minutes.
///
/// Heavy days (the calendar's deep-oxblood tint) are the top quartile of read
/// days by seconds — and only once the month holds at least four read days,
/// because a quartile over two points is a coin toss wearing a statistic.
List<CalendarCell> _monthCells(PeriodRange range, Iterable<ReadingSession> inRangeSessions, DateTime now) {
  final secondsByDay = <int, int>{};
  for (final s in inRangeSessions) {
    secondsByDay[s.startedAt.day] = (secondsByDay[s.startedAt.day] ?? 0) + s.durationSeconds;
  }
  final readDays = secondsByDay.keys.toSet();

  var heavyThreshold = 0;
  var lightestDay = 0;
  if (readDays.length >= 4) {
    final sorted = secondsByDay.values.toList()..sort();
    heavyThreshold = sorted[(sorted.length * 3) ~/ 4];
    lightestDay = sorted.first;
  }
  // "Heavy" means the day stands out — a month of identical sittings has no
  // heavy days, and a threshold that ties the minimum must not mark the
  // whole calendar oxblood.
  bool isHeavy(int day) {
    if (heavyThreshold == 0) return false;
    final seconds = secondsByDay[day] ?? 0;
    return seconds >= heavyThreshold && seconds > lightestDay;
  }

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
        isHeavy: isHeavy(day),
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
