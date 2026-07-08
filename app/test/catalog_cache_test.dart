import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/catalog_cache.dart';
import 'package:kitabi/data/db/database.dart';

/// The fresh-install regression (TestFlight build 39): sync pull restored
/// library_entries but cached_books is device-local, so the grid's inner join
/// showed "0 books" while home counted 5. cacheMissingLibraryBooks re-fetches
/// the missing editions and the join heals.
class _FakeApi extends ApiClient {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getWorkByEdition(String editionId) async {
    calls++;
    return {
      'id': 'w-$editionId',
      'title': 'Book $editionId',
      'subtitle': null,
      'first_publish_year': null,
      'authors': [
        {'id': 'a1', 'name': 'An Author'},
      ],
      'genres': const <Map<String, dynamic>>[],
      'editions': [
        {
          'id': editionId,
          'isbn': null,
          'language': null,
          'page_count': null,
          'format': null,
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };
  }
}

void main() {
  test('cacheMissingLibraryBooks hydrates entries the grid join was dropping', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi();

    // Two synced-down entries, NO cached_books rows (fresh install).
    for (final id in ['e1', 'e2']) {
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(id: 'le-$id', userId: 'u1', editionId: id),
      );
    }
    expect(await db.libraryEntriesDao.watchAllWithBooks().first, isEmpty); // the bug

    final cached = await cacheMissingLibraryBooks(db, api);

    expect(cached, 2);
    final hits = await db.libraryEntriesDao.watchAllWithBooks().first;
    expect(hits, hasLength(2)); // the join healed
    expect(hits.map((h) => h.book.title), containsAll(['Book e1', 'Book e2']));

    // Second call is a cheap no-op — nothing missing, no network.
    api.calls = 0;
    expect(await cacheMissingLibraryBooks(db, api), 0);
    expect(api.calls, 0);
  });
}
