import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/library/presentation/library_filter_sheet.dart';

void main() {
  Future<void> seed(
    AppDatabase db,
    String ed, {
    required String status,
    required String language,
    bool favourite = false,
  }) async {
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: ed,
        workId: 'w-$ed',
        title: 'T-$ed',
        authorNames: 'A',
        language: Value(language),
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
    await seed(db, 'e1', status: 'read', language: 'Malayalam', favourite: true);
    await seed(db, 'e2', status: 'reading', language: 'English');
    await seed(db, 'e3', status: 'wishlist', language: 'Malayalam');

    final hits = await db.libraryEntriesDao.allWithBooks();

    int count(LibraryFilter f) => hits.where(f.matches).length;

    expect(count(const LibraryFilter()), 3); // no filter → everything
    expect(count(const LibraryFilter(statuses: {'read'})), 1);
    expect(count(const LibraryFilter(languages: {'Malayalam'})), 2);
    expect(count(const LibraryFilter(favouritesOnly: true)), 1);
    // Filters compose (AND): reading OR read, and English → just e2.
    expect(
      count(const LibraryFilter(statuses: {'read', 'reading'}, languages: {'English'})),
      1,
    );
    expect(const LibraryFilter(statuses: {'read'}, favouritesOnly: true).activeCount, 2);
  });
}
