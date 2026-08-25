import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/reading_pace.dart';

/// Fixed "now" so every window boundary is deterministic: Wed 15 Jul 2026.
final _now = DateTime(2026, 7, 15, 21);

ReadingSession _session(
  DateTime startedAt,
  int durationSeconds, {
  int? pageStart,
  int? pageEnd,
  String entryId = 'le1',
  DateTime? deletedAt,
}) {
  return ReadingSession(
    id: 'id-${startedAt.microsecondsSinceEpoch}-$entryId-${pageStart ?? 0}',
    userId: 'u1',
    createdAt: startedAt,
    updatedAt: startedAt,
    deletedAt: deletedAt,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    libraryEntryId: entryId,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationSeconds)),
    durationSeconds: durationSeconds,
    pageStart: pageStart,
    pageEnd: pageEnd,
    autoStopped: false,
  );
}

LibraryHit _hit(String entryId, String editionId, {String? language}) {
  final stamp = DateTime(2026, 1, 1);
  return LibraryHit(
    entry: LibraryEntry(
      id: entryId,
      userId: 'u1',
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: 'synced',
      lastSyncedAt: null,
      serverSeq: null,
      editionId: editionId,
      status: 'reading',
      ownership: 'owned',
      startDate: null,
      finishDate: null,
      currentPage: null,
      isFavorite: false,
      notes: null,
    ),
    book: CachedBook(
      editionId: editionId,
      workId: 'w-$editionId',
      title: 'Book $editionId',
      subtitle: null,
      authorNames: 'A',
      publisherName: null,
      seriesName: null,
      seriesNumber: null,
      isbn: null,
      language: language,
      pageCount: 300,
      format: null,
      coverUrl: null,
      firstPublishYear: null,
      genreNames: null,
      form: null,
      cachedAt: stamp,
    ),
  );
}

void main() {
  group('pagesPerHourOf', () {
    test('measures only sittings with a forward page range', () {
      final pace = pagesPerHourOf([
        // 40 pages in 1h → 40 pp/h
        _session(_now, 3600, pageStart: 10, pageEnd: 50),
        // no pages noted — counts as reading time elsewhere, not here
        _session(_now, 3600),
        // backwards (re-read / mis-typed) — ignored, never negative pages
        _session(_now, 3600, pageStart: 90, pageEnd: 40),
      ]);

      expect(pace, 40);
    });

    test('is null when nothing measurable, and skips deleted sittings', () {
      expect(pagesPerHourOf([_session(_now, 1800)]), isNull);
      expect(
        pagesPerHourOf([
          _session(_now, 3600, pageStart: 0, pageEnd: 60, deletedAt: _now),
        ]),
        isNull,
      );
    });

    test('a typo\'d page range is set aside once there are enough sittings', () {
      // Four honest sittings around 30 pp/h, one "10→310" typo (300 pp/h).
      final honest = [
        for (var i = 0; i < 4; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: i * 30, pageEnd: i * 30 + 30),
      ];
      final typo = _session(_now, 3600, pageStart: 10, pageEnd: 310);

      expect(pagesPerHourOf([...honest, typo]), 30);
      expect(measurableSessions([...honest, typo]), 4);
    });

    test('a timer left running is set aside the same way', () {
      // Four sittings at 40 pp/h, then 5 pages across 8 "hours" of reading.
      final honest = [
        for (var i = 0; i < 4; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: i * 40, pageEnd: i * 40 + 40),
      ];
      final idle = _session(_now, 8 * 3600, pageStart: 160, pageEnd: 165);

      expect(pagesPerHourOf([...honest, idle]), 40);
      expect(measurableSessions([...honest, idle]), 4);
    });

    test('below the outlier minimum every sitting counts — no trim on thin evidence', () {
      // Three sittings, one extreme: with so few, nobody can say which is
      // "unlike the others", so all three stay in.
      final rows = [
        _session(_now, 3600, pageStart: 0, pageEnd: 30),
        _session(_now, 3600, pageStart: 30, pageEnd: 60),
        _session(_now, 3600, pageStart: 60, pageEnd: 360),
      ];

      expect(measurableSessions(rows), 3);
      expect(pagesPerHourOf(rows), 120); // 360 pages / 3h — untrimmed
    });

    test('diverse but real paces are all kept — the bounds are generous', () {
      // A dense novel at 18 pp/h next to comics at 60 pp/h: both within 4× of
      // the median, both the same reader.
      final rows = [
        for (var i = 0; i < 3; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: 0, pageEnd: 18),
        for (var i = 3; i < 6; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: 0, pageEnd: 60),
      ];

      expect(measurableSessions(rows), 6);
    });

    test('weights by time, not by sitting count', () {
      // 10 pages in 6 min (100 pp/h) + 100 pages in 2h (50 pp/h)
      // → 110 pages / 2.1h ≈ 52.4, not the 75 a naive mean would give.
      final pace = pagesPerHourOf([
        _session(_now, 360, pageStart: 0, pageEnd: 10),
        _session(_now, 7200, pageStart: 10, pageEnd: 110),
      ])!;

      expect(pace, closeTo(52.4, 0.1));
    });
  });

  group('computeReadingPace', () {
    test('splits pace by the language of the book each sitting was on', () {
      final hits = [
        _hit('le-en', 'ed-en', language: 'English'),
        _hit('le-ml', 'ed-ml', language: 'മലയാളം'),
      ];
      final sessions = [
        for (var i = 0; i < 3; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: 0, pageEnd: 44, entryId: 'le-en'),
        for (var i = 0; i < 3; i++)
          _session(_now.subtract(Duration(days: i)), 3600,
              pageStart: 0, pageEnd: 26, entryId: 'le-ml'),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: hits, now: _now);

      expect(pace.byLanguage['English']!.pagesPerHour, 44);
      expect(pace.byLanguage['മലയാളം']!.pagesPerHour, 26);
      expect(pace.paceFor('മലയാളം'), 26);
      expect(pace.paceFor('English'), 44);
      expect(pace.usesLanguagePace('മലയാളം'), isTrue);
      // A language with no sample of its own falls back to the overall figure.
      expect(pace.paceFor('தமிழ்'), pace.pagesPerHour);
      expect(pace.usesLanguagePace('தமிழ்'), isFalse);
    });

    test('ignores sittings older than the 90-day window', () {
      final sessions = [
        _session(_now.subtract(const Duration(days: 200)), 3600, pageStart: 0, pageEnd: 200),
        _session(_now.subtract(const Duration(days: 1)), 3600, pageStart: 0, pageEnd: 40),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: [], now: _now);

      expect(pace.pagesPerHour, 40);
      expect(pace.sampleSessions, 1);
    });

    test('weekly habit averages over six whole weeks and ignores older reading', () {
      final sessions = [
        _session(_now.subtract(const Duration(days: 2)), 3600),
        _session(_now.subtract(const Duration(days: 9)), 3600),
        // Outside the habit window entirely.
        _session(_now.subtract(const Duration(days: 100)), 36000),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: [], now: _now);

      expect(pace.weeklySeconds, (7200 / 6).round());
      // Only the 2-day-old sitting is inside the last 7 days.
      expect(pace.recentWeekSeconds, 3600);
    });

    test('a current streak outweighs the diluted six-week average', () {
      // Three heavy days after five quiet weeks — the owner's own case
      // (12 Aug 2026): 5h40m in a streak, nothing before it.
      final sessions = [
        for (var i = 0; i < 3; i++) _session(_now.subtract(Duration(days: i)), 6800),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: [], now: _now);

      expect(pace.recentWeekSeconds, 20400);
      expect(pace.weeklySeconds, (20400 / 6).round());
      expect(pace.usesRecentHabit, isTrue);
      expect(pace.effectiveWeeklySeconds, 20400);
    });

    test('a quiet week falls back to the habit — never worsens the estimate', () {
      final sessions = [
        for (var w = 2; w < 6; w++)
          _session(_now.subtract(Duration(days: w * 7)), 7200),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: [], now: _now);

      expect(pace.recentWeekSeconds, 0);
      expect(pace.usesRecentHabit, isFalse);
      expect(pace.effectiveWeeklySeconds, pace.weeklySeconds);
    });

    test('below the minimum sample it is not measured and falls back to typical', () {
      final sessions = [
        _session(_now, 3600, pageStart: 0, pageEnd: 80),
        _session(_now, 3600, pageStart: 80, pageEnd: 160),
      ];

      final pace = computeReadingPace(sessions: sessions, hits: [], now: _now);

      expect(pace.sampleSessions, 2);
      expect(pace.isMeasured, isFalse);
      expect(pace.paceFor('English'), assumedPagesPerHour);
    });

    test('an empty history is empty, not zero-paced', () {
      final pace = computeReadingPace(sessions: [], hits: [], now: _now);

      expect(pace.pagesPerHour, isNull);
      expect(pace.medianSittingSeconds, isNull);
      expect(pace.weeklySeconds, 0);
      expect(pace.paceFor(null), assumedPagesPerHour);
    });
  });

  group('estimateFinish', () {
    ReadingPace measured(
        {double pph = 40, int weekly = 19200, int? sitting = 4320, int recent = 0}) {
      return ReadingPace(
        pagesPerHour: pph,
        sampleSessions: 12,
        byLanguage: const {},
        weeklySeconds: weekly,
        medianSittingSeconds: sitting,
        recentWeekSeconds: recent,
      );
    }

    test('no page count means no estimate — never a guessed total', () {
      expect(estimateFinish(pageCount: null, pace: measured()), isNull);
      expect(estimateFinish(pageCount: 0, pace: measured()), isNull);
    });

    test('a book not started costs the whole book', () {
      final e = estimateFinish(pageCount: 400, pace: measured(pph: 40), now: _now)!;

      expect(e.totalSeconds, 36000); // 10h
      expect(e.remainingSeconds, e.totalSeconds);
      expect(e.sittings, (36000 / 4320).ceil());
      expect(e.weeks, closeTo(36000 / 19200, 0.001));
      expect(e.isAssumedPace, isFalse);
    });

    test('a book in progress costs only what is left', () {
      final e = estimateFinish(
        pageCount: 400,
        currentPage: 300,
        pace: measured(pph: 40),
        now: _now,
      )!;

      expect(e.totalSeconds, 36000);
      expect(e.remainingSeconds, 9000); // 100 pages at 40 pp/h
      expect(e.finishDate!.isAfter(_now), isTrue);
    });

    test('a page past the end never produces negative time', () {
      final e = estimateFinish(pageCount: 200, currentPage: 999, pace: measured())!;

      expect(e.remainingSeconds, 0);
    });

    test('an unmeasured reader gets the typical pace, flagged as assumed', () {
      final e = estimateFinish(pageCount: 400, pace: ReadingPace.empty, now: _now)!;

      expect(e.pagesPerHour, assumedPagesPerHour);
      expect(e.isAssumedPace, isTrue);
      // No habit to divide by, so no weeks and no finish date — rather than
      // a confident date built on nothing.
      expect(e.weeks, isNull);
      expect(e.finishDate, isNull);
      expect(e.sittings, isNull);
    });

    test('the weeks figure divides by the streak when it beats the habit', () {
      // 10h of book at 40 pp/h; habit says 19200 s/week (≈ 1.9 weeks) but the
      // reader has put in 36000 s just this week → ≈ 1 week, flagged as such.
      final e = estimateFinish(
        pageCount: 400,
        pace: measured(pph: 40, weekly: 19200, recent: 36000),
        now: _now,
      )!;

      expect(e.weeks, closeTo(1.0, 0.001));
      expect(e.weeklySecondsUsed, 36000);
      expect(e.usedRecentHabit, isTrue);

      // And with no streak, the habit figure is used and reported as such.
      final habitual = estimateFinish(
        pageCount: 400,
        pace: measured(pph: 40, weekly: 19200, recent: 3600),
        now: _now,
      )!;
      expect(habitual.weeklySecondsUsed, 19200);
      expect(habitual.usedRecentHabit, isFalse);
    });

    test("this book's own pace wins over the reader's average", () {
      final e = estimateFinish(
        pageCount: 400,
        pace: measured(pph: 40),
        bookPagesPerHour: 20,
        now: _now,
      )!;

      expect(e.pagesPerHour, 20);
      expect(e.totalSeconds, 72000); // twice as long — a dense book
      expect(e.isAssumedPace, isFalse);
    });

    test('a book-specific pace is never reported as assumed, even for a new reader', () {
      final e = estimateFinish(
        pageCount: 100,
        pace: ReadingPace.empty,
        bookPagesPerHour: 25,
        now: _now,
      )!;

      expect(e.isAssumedPace, isFalse);
      expect(e.pagesPerHour, 25);
    });
  });

  group('actualFor', () {
    test('sums a finished book and measures the pace it was read at', () {
      final actual = actualFor([
        _session(_now, 3600, pageStart: 0, pageEnd: 38),
        _session(_now, 1800),
        _session(_now, 9999, deletedAt: _now),
      ]);

      expect(actual.sessions, 2);
      expect(actual.totalSeconds, 5400);
      expect(actual.pagesPerHour, 38);
    });
  });
}
