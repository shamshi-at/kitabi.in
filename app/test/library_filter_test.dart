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
}
