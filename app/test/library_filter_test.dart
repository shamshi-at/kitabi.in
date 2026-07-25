import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/reading_pace.dart';
import 'package:kitabi/features/library/presentation/library_filter_sheet.dart';

void main() {
  Future<void> seed(
    AppDatabase db,
    String ed, {
    required String status,
    required String language,
    String? form,
    bool favourite = false,
  }) async {
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: ed,
        workId: 'w-$ed',
        title: 'T-$ed',
        authorNames: 'A',
        language: Value(language),
        form: Value(form),
      ),
    );
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(
        id: 'le-$ed',
        userId: 'u1',
        editionId: ed,
        status: Value(status),
        isFavorite: Value(favourite),
      ),
    );
  }

  test('LibraryFilter narrows by status, language, and favourites', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'e1', status: 'read', language: 'Malayalam', form: 'Novel', favourite: true);
    await seed(db, 'e2', status: 'reading', language: 'English', form: 'Memoir');
    await seed(db, 'e3', status: 'wishlist', language: 'Malayalam');

    final hits = await db.libraryEntriesDao.allWithBooks();

    int count(LibraryFilter f) => hits.where(f.matches).length;

    expect(count(const LibraryFilter()), 3); // no filter → everything
    expect(count(const LibraryFilter(statuses: {'read'})), 1);
    expect(count(const LibraryFilter(languages: {'Malayalam'})), 2);
    // Type: one Novel; a form-less book (e3) never matches a type filter.
    expect(count(const LibraryFilter(forms: {'Novel'})), 1);
    expect(count(const LibraryFilter(forms: {'Novel', 'Memoir'})), 2);
    expect(count(const LibraryFilter(favouritesOnly: true)), 1);
    // Filters compose (AND): reading OR read, and English → just e2.
    expect(
      count(const LibraryFilter(statuses: {'read', 'reading'}, languages: {'English'})),
      1,
    );
    expect(const LibraryFilter(statuses: {'read'}, favouritesOnly: true).activeCount, 2);
  });

  test('the shelf facet narrows to one personal shelf and composes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'e1', status: 'read', language: 'Malayalam', form: 'Novel');
    await seed(db, 'e2', status: 'reading', language: 'Malayalam');
    await seed(db, 'e3', status: 'read', language: 'English');

    final hits = await db.libraryEntriesDao.allWithBooks();
    // e1 and e2 sit on the "classics" shelf; e3 doesn't.
    const shelvesOf = {
      'le-e1': {'tag-classics'},
      'le-e2': {'tag-classics', 'tag-loved'},
    };

    int count(LibraryFilter f) =>
        hits.where((h) => f.matches(h, shelvesOf: shelvesOf)).length;

    expect(count(const LibraryFilter(shelf: 'tag-classics')), 2);
    expect(count(const LibraryFilter(shelf: 'tag-loved')), 1);
    expect(count(const LibraryFilter(shelf: 'tag-empty')), 0);
    // Shelf composes with the other facets: classics AND read → just e1.
    expect(count(const LibraryFilter(shelf: 'tag-classics', statuses: {'read'})), 1);
    // Without the map, a shelf filter matches nothing rather than everything.
    expect(hits.where((h) => const LibraryFilter(shelf: 'tag-classics').matches(h)).length, 0);
    expect(const LibraryFilter(shelf: 'tag-classics').activeCount, 1);
  });

  group('the time-to-finish facet', () {
    // 40 pp/h measured, so the maths is readable: 100 pp = 2h 30m.
    const pace = ReadingPace(
      pagesPerHour: 40,
      sampleSessions: 12,
      byLanguage: {},
      weeklySeconds: 19200,
      medianSittingSeconds: 3600,
    );

    Future<List<LibraryHit>> seedBooks(AppDatabase db) async {
      Future<void> book(String ed, {int? pages, int? currentPage, String status = 'pending'}) async {
        await db.cachedBooksDao.upsert(
          CachedBooksCompanion.insert(
            editionId: ed,
            workId: 'w-$ed',
            title: 'T-$ed',
            authorNames: 'A',
            pageCount: Value(pages),
          ),
        );
        await db.libraryEntriesDao.insertOne(
          LibraryEntriesCompanion.insert(
            id: 'le-$ed',
            userId: 'u1',
            editionId: ed,
            status: Value(status),
            currentPage: Value(currentPage),
          ),
        );
      }

      await book('short', pages: 80); // 2h
      await book('mid', pages: 200); // 5h
      await book('long', pages: 600); // 15h
      await book('nearlydone', pages: 600, currentPage: 560); // 1h left
      await book('nopages'); // can't be estimated
      await book('finished', pages: 300, currentPage: 300, status: 'read'); // 0 left
      return db.libraryEntriesDao.allWithBooks();
    }

    test('buckets by the time actually left, not by the whole book', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      Set<String> ids(FinishBucket bucket) => hits
          .where((h) => LibraryFilter(finish: bucket).matches(h, pace: pace))
          .map((h) => h.book.editionId)
          .toSet();

      // 'nearlydone' is a 600-page book with an hour left — it belongs with
      // the short reads, which is the whole point of filtering on remaining.
      // 'finished' also has ~0 left, but a book you've read is not something
      // you can finish, so it must not lead the list.
      expect(ids(finishBuckets.first.bucket), {'short', 'nearlydone'});
      expect(ids(finishBuckets[1].bucket), {'mid'});
      expect(ids(finishBuckets.last.bucket), {'long'});
    });

    test('a book with no page count is excluded, and counted so it can be said', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      final filter = LibraryFilter(finish: finishBuckets.first.bucket);
      expect(
        hits.where((h) => filter.matches(h, pace: pace)).map((h) => h.book.editionId),
        isNot(contains('nopages')),
      );
      expect(unestimatableCount(hits, filter, pace: pace), 1);
      // No time facet, nothing excluded — the note never appears unasked.
      expect(unestimatableCount(hits, const LibraryFilter(), pace: pace), 0);
    });

    test('the excluded count respects the other facets', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      // 'nopages' is 'pending'; narrowing to 'reading' leaves nothing to exclude.
      final filter = LibraryFilter(
        finish: finishBuckets.first.bucket,
        statuses: const {'reading'},
      );
      expect(unestimatableCount(hits, filter, pace: pace), 0);
    });

    test('a finished book is not a candidate, and not counted as excluded either',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      // Every bucket, including the one its zero-seconds estimate would land in.
      for (final b in finishBuckets) {
        expect(
          hits
              .where((h) => LibraryFilter(finish: b.bucket).matches(h, pace: pace))
              .map((h) => h.book.editionId),
          isNot(contains('finished')),
        );
      }
      // It has a page count, so it was never in the excluded count — but a
      // page-count-less *finished* book must not inflate it either.
      await db.cachedBooksDao.upsert(
        CachedBooksCompanion.insert(
          editionId: 'readnopages',
          workId: 'w-readnopages',
          title: 'T',
          authorNames: 'A',
        ),
      );
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
          id: 'le-readnopages',
          userId: 'u1',
          editionId: 'readnopages',
          status: const Value('read'),
        ),
      );
      final withRead = await db.libraryEntriesDao.allWithBooks();
      expect(
        unestimatableCount(withRead, LibraryFilter(finish: finishBuckets.first.bucket),
            pace: pace),
        1, // still just 'nopages'
      );
    });

    test('without a pace the facet matches nothing rather than everything', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      final filter = LibraryFilter(finish: finishBuckets.first.bucket);
      expect(hits.where(filter.matches).length, 0);
      expect(filter.activeCount, 1);
      // Dropping the facet is how the excluded count knows what "would have
      // matched" means — it must not carry the time bucket with it.
      expect(filter.withoutFinish.finish, isNull);
      expect(filter.withoutFinish.activeCount, 0);
    });

    test('an unmeasured reader still gets buckets, at the typical pace', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final hits = await seedBooks(db);

      // 80 pages at the assumed 40 pp/h is 2h — still under three.
      final matched = hits
          .where((h) =>
              LibraryFilter(finish: finishBuckets.first.bucket)
                  .matches(h, pace: ReadingPace.empty))
          .map((h) => h.book.editionId);

      expect(matched, contains('short'));
    });
  });
}
