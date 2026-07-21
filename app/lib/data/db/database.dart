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

/// The app's local Drift database — the offline source of truth (CLAUDE.md
/// rule 1). Wires up every Layer-2 syncable table plus the read-only catalog
/// cache and sync bookkeeping tables, and their DAOs.
@DriftDatabase(
  tables: [
    LibraryEntries,
    Ratings,
    ReadingSessions,
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
    ReadingSessionsDao,
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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 6) {
            // Work.form ("Type": Novel/Short stories/Poetry…) mirrored into
            // the offline cache for the library filter (16 Jul 2026). Cached
            // rows refresh on their next catalog fetch; null until then.
            await m.addColumn(cachedBooks, cachedBooks.form);
          }
          if (from < 5) {
            // Unifies borrowed books into the library (15 Jul 2026, owner
            // request) — existing borrowed loans get their LibraryEntry (and
            // this device's copy of that row) via the normal pull, since the
            // server-side migration backfills them with fresh server_seq
            // values above any cursor a device could already be at; nothing
            // to backfill locally, just the new column.
            await m.addColumn(libraryEntries, libraryEntries.ownership);
          }
          if (from < 4) {
            // Reading sessions (10 Jul 2026, pulled forward from the v1.5
            // parking lot) — a whole new table, nothing to migrate from.
            await m.createTable(readingSessions);
          }
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
          if (from < 3) {
            // Scope the outbox by user so a drain racing an account switch
            // can't push one reader's ops under another's JWT. Pre-existing
            // rows get '' and are still drained (single-user devices).
            await m.addColumn(syncQueue, syncQueue.userId);
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
        await delete(readingSessions).go();
        await delete(reviews).go();
        await delete(personalTags).go();
        await delete(libraryEntryTags).go();
        await delete(lendingRecords).go();
        await delete(activityLogEntries).go();
        await delete(syncQueue).go();
        await delete(syncState).go();
        await delete(conflictHistoryEntries).go();
        await delete(cachedBooks).go();
        // KeyValues survives as a whole (device_id, the active-user marker),
        // but the personal keys in it must not — a search history is as
        // personal as the library it searched.
        await (delete(keyValues)..where((k) => k.key.equals('recent_searches'))).go();
      });
}
