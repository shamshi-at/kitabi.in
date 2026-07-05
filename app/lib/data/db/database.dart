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
}
