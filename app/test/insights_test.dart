import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/insights_stats.dart';

void main() {
  Future<void> seed(
    AppDatabase db,
    String ed, {
    required String status,
    int? pages,
    DateTime? finish,
  }) async {
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
        finishDate: Value(finish),
      ),
    );
  }

  test('computeInsights reduces the library into year-scoped stats', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'ed1', status: 'read', pages: 200, finish: DateTime(2026, 3, 10));
    await seed(db, 'ed2', status: 'read', pages: 300, finish: DateTime(2026, 3, 20));
    await seed(db, 'ed3', status: 'read', pages: 150, finish: DateTime(2025, 6, 1));
    await seed(db, 'ed4', status: 'reading');

    final hits = await db.libraryEntriesDao.allWithBooks();

    final y2026 = computeInsights(hits, year: 2026);
    expect(y2026.booksRead, 2);
    expect(y2026.pagesRead, 500);
    expect(y2026.currentlyReading, 1);
    expect(y2026.booksPerMonth[2], 2); // two finished in March
    expect(y2026.busiestMonthCount, 2);

    final allTime = computeInsights(hits, year: null);
    expect(allTime.booksRead, 3);
    expect(allTime.pagesRead, 650);

    // The almanac superlatives: all three read books share author 'A', the
    // longest finished one is ed2 (300 pp), and the mean rounds sensibly.
    expect(allTime.topAuthor, 'A');
    expect(allTime.topAuthorCount, 3);
    expect(allTime.longestBookTitle, 'T-ed2');
    expect(allTime.longestBookPages, 300);
    expect(allTime.avgPagesPerBook, 217); // 650 / 3 rounded
  });

  test('a single finish never earns a most-read-author superlative', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db, 'ed1', status: 'read', pages: 120, finish: DateTime(2026, 1, 5));

    final stats = computeInsights(await db.libraryEntriesDao.allWithBooks(), year: null);
    expect(stats.topAuthor, isNull); // one book is not a pattern
    expect(stats.longestBookTitle, 'T-ed1'); // but longest is still honest
  });
}
