import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/cached_books_dao.dart';
import 'daos/library_daos.dart';
import 'daos/sync_daos.dart';
import 'tables.dart';

// Hand-written join result types the DAOs return need to be visible wherever
// `database.dart` is imported (repositories, providers, screens).
export 'daos/library_daos.dart' show LendingWithBook, LibraryHit;

part 'database.g.dart';

@DriftDatabase(
  tables: [
    LibraryEntries,
    Ratings,
    Reviews,
    PersonalTags,
    LibraryEntryTags,
    LendingRecords,
    ActivityLogEntries,
    SyncQueue,
    SyncState,
    ConflictHistoryEntries,
    KeyValues,
    CachedBooks,
  ],
  daos: [
    LibraryEntriesDao,
    RatingsDao,
    ReviewsDao,
    TagsDao,
    LendingRecordsDao,
    ActivityLogDao,
    SyncQueueDao,
    SyncStateDao,
    ConflictHistoryDao,
    KeyValuesDao,
    CachedBooksDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'kitabi'));

  /// In-memory executor for tests — never touches disk.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Lending runs both ways now: add direction/editionId/linkedLoanId/
            // note and make libraryEntryId nullable (borrowed books aren't owned).
            // TableMigration recreates the table with the new schema, copying
            // existing rows and defaulting the new columns.
            // TableMigration is the canonical drift way to add columns + relax
            // a NOT NULL at once; marked experimental but stable in practice.
            await m.alterTable(
              // ignore: experimental_member_use
              TableMigration(
                lendingRecords,
                newColumns: [
                  lendingRecords.direction,
                  lendingRecords.editionId,
                  lendingRecords.linkedLoanId,
                  lendingRecords.note,
                ],
              ),
            );
          }
        },
      );

  /// Wipe all per-user data (Layer 2 entities, the offline caches, and the sync
  /// bookkeeping) when the signed-in account changes on this device — so one
  /// reader's library/loans never leak into another's. `KeyValues` is kept
  /// (device settings + the active-user marker); the sync cursor in `SyncState`
  /// is cleared, so the new account re-pulls everything from server_seq 0.
  Future<void> clearUserData() => transaction(() async {
        await delete(libraryEntries).go();
        await delete(ratings).go();
        await delete(reviews).go();
        await delete(personalTags).go();
        await delete(libraryEntryTags).go();
        await delete(lendingRecords).go();
        await delete(activityLogEntries).go();
        await delete(syncQueue).go();
        await delete(syncState).go();
        await delete(conflictHistoryEntries).go();
        await delete(cachedBooks).go();
      });
}
