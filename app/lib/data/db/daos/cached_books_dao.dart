import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'cached_books_dao.g.dart';

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

  /// Patch just the cover (after a user uploads their own photo).
  Future<void> updateCoverUrl(String editionId, String? url) =>
      (update(cachedBooks)..where((t) => t.editionId.equals(editionId)))
          .write(CachedBooksCompanion(coverUrl: Value(url)));
}
