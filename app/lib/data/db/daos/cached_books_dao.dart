import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'cached_books_dao.g.dart';

/// DAO for the read-only catalog cache — the Work/Edition fields the library
/// grid needs, cached locally so shelves render offline (CLAUDE.md rule 2).
@DriftAccessor(tables: [CachedBooks, LibraryEntries])
class CachedBooksDao extends DatabaseAccessor<AppDatabase> with _$CachedBooksDaoMixin {
  CachedBooksDao(super.db);

  Future<CachedBook?> getByEditionId(String editionId) => (select(
        cachedBooks,
      )..where((t) => t.editionId.equals(editionId)))
          .getSingleOrNull();

  Stream<CachedBook?> watchByEditionId(String editionId) => (select(
        cachedBooks,
      )..where((t) => t.editionId.equals(editionId)))
          .watchSingleOrNull();

  Future<void> upsert(CachedBooksCompanion row) => into(cachedBooks).insertOnConflictUpdate(row);

  /// Cached books that still have no cover — the set worth re-fetching from the
  /// catalog when a cover may have been added upstream (e.g. a metadata backfill)
  /// after the book was first cached.
  Future<List<CachedBook>> withoutCover() =>
      (select(cachedBooks)..where((t) => t.coverUrl.isNull())).get();

  /// Patch just the cover (after a user uploads their own photo).
  Future<void> updateCoverUrl(String editionId, String? url) =>
      (update(cachedBooks)..where((t) => t.editionId.equals(editionId)))
          .write(CachedBooksCompanion(coverUrl: Value(url)));

  /// Patch just the page count — the reader supplying the total from the
  /// reading timer, where a book with no page count can't show progress at
  /// all. The catalog is still the source of truth (the same number is PATCHed
  /// onto the Edition); this keeps the mirror in step immediately, and keeps
  /// their progress working even if that call couldn't go out.
  Future<void> updatePageCount(String editionId, int? pageCount) =>
      (update(cachedBooks)..where((t) => t.editionId.equals(editionId)))
          .write(CachedBooksCompanion(pageCount: Value(pageCount)));

  /// The reader's own genres, commonest first — how often each one appears
  /// across the books actually on their shelves. Powers the add form's genre
  /// row, so a reader of Malayalam poetry is offered the genres they use
  /// rather than the ten we happened to hardcode (mockup M10).
  ///
  /// Joined to `library_entries` on purpose: `cached_books` also holds rows
  /// cached while merely browsing, and those aren't a signal about this
  /// reader's taste. Tallied in Dart rather than SQL because `genre_names` is
  /// a comma-joined string, not a table — a shelf is a few hundred rows at
  /// most, so splitting them is cheaper than the schema change would be.
  Future<List<String>> readerGenresByUse() async {
    final query = select(cachedBooks).join([
      innerJoin(
        db.libraryEntries,
        db.libraryEntries.editionId.equalsExp(cachedBooks.editionId) &
            db.libraryEntries.deletedAt.isNull(),
      ),
    ]);
    final rows = await query.get();

    final tally = <String, int>{};
    for (final row in rows) {
      final raw = row.readTable(cachedBooks).genreNames;
      if (raw == null || raw.isEmpty) continue;
      for (final name in raw.split(',')) {
        final genre = name.trim();
        if (genre.isEmpty) continue;
        tally.update(genre, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    final ranked = tally.keys.toList()
      ..sort((a, b) {
        final byCount = tally[b]!.compareTo(tally[a]!);
        // Ties alphabetically, so the row doesn't reshuffle between opens.
        return byCount != 0 ? byCount : a.toLowerCase().compareTo(b.toLowerCase());
      });
    return ranked;
  }
}
