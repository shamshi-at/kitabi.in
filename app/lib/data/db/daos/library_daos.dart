import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'library_daos.g.dart';

@DriftAccessor(tables: [LibraryEntries])
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

@DriftAccessor(tables: [LendingRecords])
class LendingRecordsDao extends DatabaseAccessor<AppDatabase> with _$LendingRecordsDaoMixin {
  LendingRecordsDao(super.db);

  Stream<List<LendingRecord>> watchForEntry(String libraryEntryId) => (select(
        lendingRecords,
      )..where((t) => t.libraryEntryId.equals(libraryEntryId) & t.deletedAt.isNull()))
          .watch();

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
