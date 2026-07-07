import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'cached_books_dao.g.dart';

/// DAO for the read-only catalog cache — the Work/Edition fields the library
/// grid needs, cached locally so shelves render offline (CLAUDE.md rule 2).
@DriftAccessor(tables: [CachedBooks])
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
}
