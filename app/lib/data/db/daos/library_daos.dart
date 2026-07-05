import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'library_daos.g.dart';

/// A library entry joined to its cached book — the shape global search (S4)
/// needs for the "in your library" section.
class LibraryHit {
  LibraryHit({required this.entry, required this.book});

  final LibraryEntry entry;
  final CachedBook book;
}

@DriftAccessor(tables: [LibraryEntries, CachedBooks])
class LibraryEntriesDao extends DatabaseAccessor<AppDatabase> with _$LibraryEntriesDaoMixin {
  LibraryEntriesDao(super.db);

  Stream<List<LibraryEntry>> watchActive() => (select(
        libraryEntries,
      )..where((t) => t.deletedAt.isNull()))
          .watch();

  Future<LibraryEntry?> getByEditionId(String editionId) =>
      (select(libraryEntries)
            ..where((t) => t.editionId.equals(editionId) & t.deletedAt.isNull()))
          .getSingleOrNull();

  /// Every active entry joined to its cached book — feeds the insights/stats
  /// screen (S10), which needs page counts, finish dates, and statuses together.
  Future<List<LibraryHit>> allWithBooks() {
    final stmt = select(libraryEntries).join([
      innerJoin(cachedBooks, cachedBooks.editionId.equalsExp(libraryEntries.editionId)),
    ])..where(libraryEntries.deletedAt.isNull());
    return stmt
        .map(
          (row) => LibraryHit(
            entry: row.readTable(libraryEntries),
            book: row.readTable(cachedBooks),
          ),
        )
        .get();
  }

  /// Global-search the personal library by title or author (offline, from the
  /// cached-book mirror). SQLite LIKE is case-insensitive for ASCII.
  Future<List<LibraryHit>> search(String query) {
    final q = '%${query.trim()}%';
    final stmt = select(libraryEntries).join([
      innerJoin(cachedBooks, cachedBooks.editionId.equalsExp(libraryEntries.editionId)),
    ])..where(
        libraryEntries.deletedAt.isNull() &
            (cachedBooks.title.like(q) | cachedBooks.authorNames.like(q)),
      );
    return stmt
        .map(
          (row) => LibraryHit(
            entry: row.readTable(libraryEntries),
            book: row.readTable(cachedBooks),
          ),
        )
        .get();
  }

  Future<void> insertOne(LibraryEntriesCompanion row) => into(libraryEntries).insert(row);

  Future<void> patch(String id, LibraryEntriesCompanion patch) =>
      (update(libraryEntries)..where((t) => t.id.equals(id))).write(patch);
}

@DriftAccessor(tables: [Ratings])
class RatingsDao extends DatabaseAccessor<AppDatabase> with _$RatingsDaoMixin {
  RatingsDao(super.db);

  Stream<Rating?> watchForWork(String workId) => (select(
        ratings,
      )..where((t) => t.workId.equals(workId) & t.deletedAt.isNull()))
          .watchSingleOrNull();

  Future<void> insertOne(RatingsCompanion row) => into(ratings).insert(row);

  Future<void> patch(String id, RatingsCompanion patch) =>
      (update(ratings)..where((t) => t.id.equals(id))).write(patch);
}

@DriftAccessor(tables: [Reviews])
class ReviewsDao extends DatabaseAccessor<AppDatabase> with _$ReviewsDaoMixin {
  ReviewsDao(super.db);

  Stream<Review?> watchForWork(String workId) => (select(
        reviews,
      )..where((t) => t.workId.equals(workId) & t.deletedAt.isNull()))
          .watchSingleOrNull();

  Future<void> insertOne(ReviewsCompanion row) => into(reviews).insert(row);

  Future<void> patch(String id, ReviewsCompanion patch) =>
      (update(reviews)..where((t) => t.id.equals(id))).write(patch);
}

@DriftAccessor(tables: [PersonalTags, LibraryEntryTags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  Stream<List<PersonalTag>> watchAll() =>
      (select(personalTags)..where((t) => t.deletedAt.isNull())).watch();

  Stream<List<LibraryEntryTag>> watchForEntry(String libraryEntryId) => (select(
        libraryEntryTags,
      )..where((t) => t.libraryEntryId.equals(libraryEntryId) & t.deletedAt.isNull()))
          .watch();

  Future<void> insertTag(PersonalTagsCompanion row) => into(personalTags).insert(row);

  Future<void> insertAssignment(LibraryEntryTagsCompanion row) =>
      into(libraryEntryTags).insert(row);

  Future<void> patchAssignment(String id, LibraryEntryTagsCompanion patch) =>
      (update(libraryEntryTags)..where((t) => t.id.equals(id))).write(patch);
}

/// One lending record joined to the book it concerns — the shape the ledger
/// (S8) needs, so each row can show a cover + title without a per-row lookup.
class LendingWithBook {
  LendingWithBook({required this.record, this.book});

  final LendingRecord record;
  final CachedBook? book;
}

@DriftAccessor(tables: [LendingRecords, LibraryEntries, CachedBooks])
class LendingRecordsDao extends DatabaseAccessor<AppDatabase> with _$LendingRecordsDaoMixin {
  LendingRecordsDao(super.db);

  Stream<List<LendingRecord>> watchForEntry(String libraryEntryId) => (select(
        lendingRecords,
      )..where((t) => t.libraryEntryId.equals(libraryEntryId) & t.deletedAt.isNull()))
          .watch();

  /// Every active lending record for the whole library, newest-lent first,
  /// joined to its cached book. A lent record resolves the book through the
  /// owned library entry; a borrowed one has no entry, so it falls back to the
  /// record's own `editionId`.
  Stream<List<LendingWithBook>> watchAllActive() {
    final bookEdition = coalesce([libraryEntries.editionId, lendingRecords.editionId]);
    final query = select(lendingRecords).join([
      leftOuterJoin(libraryEntries, libraryEntries.id.equalsExp(lendingRecords.libraryEntryId)),
      leftOuterJoin(cachedBooks, cachedBooks.editionId.equalsExp(bookEdition)),
    ])
      ..where(lendingRecords.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(lendingRecords.lentDate)]);
    return query.watch().map(
          (rows) => rows
              .map(
                (r) => LendingWithBook(
                  record: r.readTable(lendingRecords),
                  book: r.readTableOrNull(cachedBooks),
                ),
              )
              .toList(),
        );
  }

  Future<void> insertOne(LendingRecordsCompanion row) => into(lendingRecords).insert(row);

  Future<void> patch(String id, LendingRecordsCompanion patch) =>
      (update(lendingRecords)..where((t) => t.id.equals(id))).write(patch);
}

@DriftAccessor(tables: [ActivityLogEntries])
class ActivityLogDao extends DatabaseAccessor<AppDatabase> with _$ActivityLogDaoMixin {
  ActivityLogDao(super.db);

  Stream<List<ActivityLogEntry>> watchRecent({int limit = 50}) => (select(
        activityLogEntries,
      )
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
        ..limit(limit))
          .watch();
}
