import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';

void main() {
  Future<void> seed(AppDatabase db, String edition, String title, String author) async {
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: edition,
        workId: 'w-$edition',
        title: title,
        authorNames: author,
      ),
    );
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(id: 'le-$edition', userId: 'u1', editionId: edition),
    );
  }

  test('library search matches by title or author, case-insensitively', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    await seed(db, 'ed1', 'Khasakkinte Itihasam', 'O.V. Vijayan');
    await seed(db, 'ed2', 'Randamoozham', 'M.T. Vasudevan Nair');
    final repo = LibraryRepository(db, session);

    final byTitle = await repo.search('khasak');
    expect(byTitle.map((h) => h.book.title), contains('Khasakkinte Itihasam'));

    final byAuthor = await repo.search('vasudevan');
    expect(byAuthor.single.book.title, 'Randamoozham');
    expect(byAuthor.single.entry.editionId, 'ed2');

    expect(await repo.search('zzzz-no-match'), isEmpty);
  });
}
