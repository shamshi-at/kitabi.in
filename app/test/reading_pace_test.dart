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
    ReadingPace measured({double pph = 40, int weekly = 19200, int? sitting = 4320}) {
      return ReadingPace(
        pagesPerHour: pph,
        sampleSessions: 12,
        byLanguage: const {},
        weeklySeconds: weekly,
        medianSittingSeconds: sitting,
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
