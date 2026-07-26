import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/features/library/mark_finished.dart';

/// The three rules of finishing a book, in the one place all three surfaces
/// (book page status row, timer wax-seal face, quick-stop sheet) go through.
void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  const session = SessionContext(userId: 'u1', deviceId: 'd1');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db, session);
  });

  tearDown(() async => db.close());

  Future<void> seed({
    required String id,
    String status = 'reading',
    int? currentPage,
    int? pageCount,
    DateTime? finishDate,
  }) async {
    await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
      editionId: 'ed-$id',
      workId: 'w-$id',
      title: 'Book $id',
      authorNames: 'Author',
      pageCount: Value(pageCount),
    ));
    await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
      id: id,
      userId: 'u1',
      editionId: 'ed-$id',
      status: Value(status),
      currentPage: Value(currentPage),
      finishDate: Value(finishDate),
    ));
  }

  test('marks read, stamps the finish date, and fills progress to the total', () async {
    await seed(id: 'e1', currentPage: 302, pageCount: 724);

    final result = await markBookFinished(db: db, repo: repo, libraryEntryId: 'e1');

    final entry = await db.libraryEntriesDao.getById('e1');
    expect(entry!.status, 'read');
    expect(entry.finishDate, isNotNull);
    // A book marked Read that still says p. 302 of 724 is a contradiction the
    // reader would have to go and fix by hand.
    expect(entry.currentPage, 724);
    expect(result.pagesFilledTo, 724);
  });

  test('never re-stamps a book that was already finished once', () async {
    final original = DateTime(2026, 6, 1);
    await seed(id: 'e2', status: 'read', currentPage: 200, pageCount: 200, finishDate: original);

    await markBookFinished(db: db, repo: repo, libraryEntryId: 'e2');

    final entry = await db.libraryEntriesDao.getById('e2');
    expect(entry!.finishDate, original);
    // Already on the last page — nothing to snap, so no snackbar claim either.
    expect(entry.currentPage, 200);
  });

  test('a book with no page count is still finished, just without a page', () async {
    await seed(id: 'e3', currentPage: 40);

    final result = await markBookFinished(db: db, repo: repo, libraryEntryId: 'e3');

    final entry = await db.libraryEntriesDao.getById('e3');
    expect(entry!.status, 'read');
    expect(entry.finishDate, isNotNull);
    expect(entry.currentPage, 40, reason: 'no total to fill in — leave the page alone');
    expect(result.pagesFilledTo, isNull);
  });

  test('enqueues the change for sync rather than writing only locally', () async {
    await seed(id: 'e4', currentPage: 10, pageCount: 100);

    await markBookFinished(db: db, repo: repo, libraryEntryId: 'e4');

    final queued = await db.syncQueueDao.pending(limit: 50);
    expect(
      queued.where((op) => op.entity == 'library_entries' && op.entityId == 'e4'),
      isNotEmpty,
    );
  });

  test('a missing entry is a no-op, not a crash', () async {
    final result = await markBookFinished(db: db, repo: repo, libraryEntryId: 'nope');
    expect(result.pagesFilledTo, isNull);
  });
}
