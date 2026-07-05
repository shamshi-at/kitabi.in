import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/import_books/csv_export.dart';

void main() {
  test('buildLibraryCsv writes a header + one RFC-4180-escaped row per book', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: 'e1',
        workId: 'w1',
        title: 'Chemmeen, and other stories', // comma → must be quoted
        authorNames: 'Thakazhi',
        isbn: const Value('9788126415419'),
        language: const Value('Malayalam'),
      ),
    );
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(
        id: 'le1',
        userId: 'u1',
        editionId: 'e1',
        status: const Value('read'),
        finishDate: Value(DateTime(2026, 3, 10)),
        isFavorite: const Value(true),
        notes: const Value('Loved it'),
      ),
    );

    final hits = await db.libraryEntriesDao.allWithBooks();
    final csv = buildLibraryCsv(hits);
    final lines = csv.trim().split('\n');

    expect(lines.first, startsWith('Title,Author,ISBN,Language,Exclusive Shelf'));
    expect(lines[1], contains('"Chemmeen, and other stories"')); // quoted comma
    expect(lines[1], contains('9788126415419'));
    expect(lines[1], contains('read'));
    expect(lines[1], contains('2026-03-10'));
    expect(lines[1], contains('yes')); // favorite
    expect(lines[1], contains('Loved it'));
  });
}
