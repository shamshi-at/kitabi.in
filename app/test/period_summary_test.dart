import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/period.dart';
import 'package:kitabi/features/insights/period_summary.dart';

ReadingSession _session(
  DateTime startedAt, {
  int durationSeconds = 1800,
  int? pageStart,
  int? pageEnd,
  DateTime? deletedAt,
  String libraryEntryId = 'le1',
}) {
  return ReadingSession(
    id: 'id-${startedAt.microsecondsSinceEpoch}',
    userId: 'u1',
    createdAt: startedAt,
    updatedAt: startedAt,
    deletedAt: deletedAt,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    libraryEntryId: libraryEntryId,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationSeconds)),
    durationSeconds: durationSeconds,
    pageStart: pageStart,
    pageEnd: pageEnd,
    autoStopped: false,
  );
}

Future<void> _seedFinished(
  AppDatabase db,
  String ed, {
  required DateTime finish,
  int? pages,
}) async {
  await db.cachedBooksDao.upsert(
    CachedBooksCompanion.insert(
      editionId: ed,
      workId: 'w-$ed',
      title: 'T-$ed',
      authorNames: 'A-$ed',
      pageCount: Value(pages),
    ),
  );
  await db.libraryEntriesDao.insertOne(
    LibraryEntriesCompanion.insert(
      id: 'le-$ed',
      userId: 'u1',
      editionId: ed,
      status: const Value('read'),
      finishDate: Value(finish),
    ),
  );
}

void main() {
  final now = DateTime(2026, 7, 27, 20); // Monday, mid-evening.

  test('totals and sittings only count sessions inside the window', () async {
    final range = rangeFor(InsightsPeriod.week, now: now);
    final sessions = [
      _session(DateTime(2026, 7, 27, 19), durationSeconds: 1200, pageStart: 10, pageEnd: 20),
      _session(DateTime(2026, 7, 26, 10), durationSeconds: 999), // last week — excluded
      _session(DateTime(2026, 7, 27, 8), durationSeconds: 600, deletedAt: now), // soft-deleted
    ];

    final summary = computePeriodSummary(
      period: InsightsPeriod.week,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );

    expect(summary.totalSeconds, 1200);
    expect(summary.pagesRead, 10);
    expect(summary.sittingsCount, 1);
  });

  test('previousTotalSeconds compares against the prior window, null for year', () async {
    final range = rangeFor(InsightsPeriod.week, now: now);
    final sessions = [
      _session(DateTime(2026, 7, 27, 19), durationSeconds: 1200), // this week
      _session(DateTime(2026, 7, 22, 19), durationSeconds: 700), // last week
    ];

    final week = computePeriodSummary(
      period: InsightsPeriod.week,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(week.previousTotalSeconds, 700);

    final yearRange = rangeFor(InsightsPeriod.year, now: now);
    final year = computePeriodSummary(
      period: InsightsPeriod.year,
      range: yearRange,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(year.previousTotalSeconds, isNull);
  });

  test('booksFinished is scoped to the window, newest first, carries the rating', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedFinished(db, 'ed1', finish: DateTime(2026, 7, 5), pages: 200);
    await _seedFinished(db, 'ed2', finish: DateTime(2026, 7, 20), pages: 300);
    await _seedFinished(db, 'ed3', finish: DateTime(2026, 6, 1), pages: 150); // outside the month
    final hits = await db.libraryEntriesDao.allWithBooks();

    final range = rangeFor(InsightsPeriod.month, now: now);
    final summary = computePeriodSummary(
      period: InsightsPeriod.month,
      range: range,
      sessions: const [],
      hits: hits,
      ratingsByWorkId: const {'w-ed2': 5},
      now: now,
    );

    expect(summary.booksFinishedCount, 2);
    expect(summary.booksFinished.first.title, 'T-ed2'); // newest finish first
    expect(summary.booksFinished.first.rating, 5);
    expect(summary.booksFinished.last.rating, isNull); // finished but never rated
  });

  test('streakDays counts consecutive days ending today', () {
    final sessions = [
      _session(DateTime(2026, 7, 27, 9)), // today
      _session(DateTime(2026, 7, 26, 9)),
      _session(DateTime(2026, 7, 25, 9)),
      _session(DateTime(2026, 7, 23, 9)), // gap on the 24th breaks it
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.today,
      range: rangeFor(InsightsPeriod.today, now: now),
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(summary.streakDays, 3);
  });

  test('streakDays counts from yesterday when today has no sitting yet', () {
    final sessions = [
      _session(DateTime(2026, 7, 26, 9)),
      _session(DateTime(2026, 7, 25, 9)),
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.today,
      range: rangeFor(InsightsPeriod.today, now: now),
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(summary.streakDays, 2);
  });

  test('recentDays is a trailing 7-day window ending today, oldest first', () {
    final sessions = [
      _session(DateTime(2026, 7, 27, 9)), // today
      _session(DateTime(2026, 7, 25, 9)),
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.today,
      range: rangeFor(InsightsPeriod.today, now: now),
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    // Trailing window Jul21..Jul27 — sessions land on the 25th and today (27th).
    expect(summary.recentDays, [false, false, false, false, true, false, true]);
  });

  test('streakDays is null for every period except today', () {
    final summary = computePeriodSummary(
      period: InsightsPeriod.week,
      range: rangeFor(InsightsPeriod.week, now: now),
      sessions: const [],
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(summary.streakDays, isNull);
  });

  test('calendarCells is a real weekday-aligned July grid with future days marked', () {
    // 1 Jul 2026 is a Wednesday — 3 blank leading cells (Sun, Mon, Tue).
    final range = rangeFor(InsightsPeriod.month, now: now);
    final sessions = [_session(DateTime(2026, 7, 5, 9))];

    final summary = computePeriodSummary(
      period: InsightsPeriod.month,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );

    final cells = summary.calendarCells!;
    expect(cells[0].date, isNull); // leading filler
    expect(cells[1].date, isNull);
    expect(cells[2].date, isNull);
    expect(cells[3].date, DateTime(2026, 7, 1));
    final jul5 = cells.firstWhere((c) => c.date == DateTime(2026, 7, 5));
    expect(jul5.isRead, isTrue);
    expect(jul5.isFuture, isFalse);
    final jul31 = cells.firstWhere((c) => c.date == DateTime(2026, 7, 31));
    expect(jul31.isFuture, isTrue); // today is the 27th
    expect(jul31.isRead, isFalse);
  });

  test('dailyBuckets lines up Monday-first with the week range', () {
    final range = rangeFor(InsightsPeriod.week, now: now); // Mon 27 Jul
    final sessions = [
      _session(DateTime(2026, 7, 27, 19), durationSeconds: 500), // Monday
      _session(DateTime(2026, 7, 29, 8), durationSeconds: 700), // Wednesday
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.week,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(summary.dailyBuckets, [500, 0, 700, 0, 0, 0, 0]);
  });

  test('trendBuckets buckets a trailing window into weeks, oldest first', () {
    final range = rangeFor(InsightsPeriod.threeMonths, now: now);
    final sessions = [
      _session(range.start.add(const Duration(hours: 10)), durationSeconds: 300), // first week
      _session(range.end.subtract(const Duration(hours: 10)), durationSeconds: 900), // last week
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.threeMonths,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(summary.trendBuckets!.first, 300);
    expect(summary.trendBuckets!.last, 900);
  });

  test('calendar heavy days are the standout top quartile, never the whole month', () {
    final range = rangeFor(InsightsPeriod.month, now: now);
    // Four ordinary evenings and one long Sunday — only the Sunday is heavy.
    final sessions = [
      _session(DateTime(2026, 7, 2, 20), durationSeconds: 600),
      _session(DateTime(2026, 7, 3, 20), durationSeconds: 600),
      _session(DateTime(2026, 7, 4, 20), durationSeconds: 600),
      _session(DateTime(2026, 7, 5, 20), durationSeconds: 600),
      _session(DateTime(2026, 7, 12, 10), durationSeconds: 7200),
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.month,
      range: range,
      sessions: sessions,
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    final heavy = summary.calendarCells!.where((c) => c.isHeavy).toList();
    expect(heavy, hasLength(1));
    expect(heavy.single.date!.day, 12);

    // A month of identical sittings has no heavy days — heavy means the day
    // stands out, and a threshold tying the minimum must not paint the grid.
    final flat = computePeriodSummary(
      period: InsightsPeriod.month,
      range: range,
      sessions: [
        for (final day in [2, 3, 4, 5, 6]) _session(DateTime(2026, 7, day, 20), durationSeconds: 600),
      ],
      hits: const [],
      ratingsByWorkId: const {},
      now: now,
    );
    expect(flat.calendarCells!.where((c) => c.isHeavy), isEmpty);
  });

  test('booksInHand joins today\'s sittings to books, most time first', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedFinished(db, 'edA', finish: DateTime(2026, 7, 1), pages: 384);
    await _seedFinished(db, 'edB', finish: DateTime(2026, 7, 2), pages: 180);
    final hits = await db.libraryEntriesDao.allWithBooks();

    final range = rangeFor(InsightsPeriod.today, now: now);
    final sessions = [
      _session(DateTime(2026, 7, 27, 8), durationSeconds: 600, libraryEntryId: 'le-edB'),
      _session(DateTime(2026, 7, 27, 20), durationSeconds: 1800, libraryEntryId: 'le-edA'),
      _session(DateTime(2026, 7, 27, 21), durationSeconds: 300, libraryEntryId: 'le-gone'),
    ];
    final summary = computePeriodSummary(
      period: InsightsPeriod.today,
      range: range,
      sessions: sessions,
      hits: hits,
      ratingsByWorkId: const {},
      now: now,
    );

    final books = summary.booksInHand!;
    // The orphan sitting (deleted book) still counts in the totals but can't
    // be named — the section only names what it can still name.
    expect(summary.sittingsCount, 3);
    expect(books, hasLength(2));
    expect(books.first.title, 'T-edA'); // 1800s beats 600s
    expect(books.first.pageCount, 384);
    expect(books.last.title, 'T-edB');

    // And only Today computes it at all.
    final week = computePeriodSummary(
      period: InsightsPeriod.week,
      range: rangeFor(InsightsPeriod.week, now: now),
      sessions: sessions,
      hits: hits,
      ratingsByWorkId: const {},
      now: now,
    );
    expect(week.booksInHand, isNull);
  });
}
