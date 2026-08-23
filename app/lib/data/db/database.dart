import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/cached_books_dao.dart';
import 'daos/library_daos.dart';
import 'daos/promotions_dao.dart';
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
    ReadingNotes,
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
    CachedPromotions,
    PromotionEventQueue,
  ],
  daos: [
    LibraryEntriesDao,
    RatingsDao,
    ReadingSessionsDao,
    ReadingNotesDao,
    ReviewsDao,
    TagsDao,
    LendingRecordsDao,
    ActivityLogDao,
    SyncQueueDao,
    SyncStateDao,
    ConflictHistoryDao,
    KeyValuesDao,
    CachedBooksDao,
    PromotionsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'kitabi'));

  /// In-memory executor for tests — never touches disk.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 13) {
            // Flags a sitting closed by the auto-stop safety net rather than
            // the reader tapping Stop, so the reading log can offer a
            // correction (owner report, 23 Aug 2026). Existing rows default
            // to false — there's no way to tell after the fact which of them
            // were auto-stopped, and treating them as ordinary stops is the
            // safe direction.
            await m.addColumn(readingSessions, readingSessions.autoStopped);
          }
          if (from < 12) {
            // A rating or a review now names a book OR a series (13 Aug 2026),
            // so `work_id` has to be nullable. SQLite cannot relax NOT NULL in
            // place, and Drift's TableMigration is the supported way: it builds
            // the table at its current Dart shape and copies every column the
            // two shapes share, so existing rows keep their book and simply
            // gain a null series.
            // TableMigration is marked experimental in drift but is its
            // documented answer for relaxing a NOT NULL, and the alternative is
            // hand-written create/copy/drop/rename SQL that would have to be
            // kept in step with the generated schema by hand.
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(ratings));
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(reviews));
          }
          if (from < 11) {
            // The community rating mirrored onto shelf covers (9 Aug 2026).
            // Null until each book's next catalog re-fetch fills it.
            await m.addColumn(cachedBooks, cachedBooks.aggregateRating);
          }
          // Promotions, v8 → v10. Exclusive branches on purpose: a device that
          // has never seen the tables just creates them at the final shape,
          // and one that has them at an older shape recreates the cache. The
          // v9 book*-column step is gone — v10 supersedes it, and leaving it
          // would have tried to add columns to a table that no longer has them.
          if (from < 8) {
            // In-app promotions (31 Jul 2026) — a server-resolved cache plus
            // its own append-only event outbox. Both start empty; the first
            // /promotions fetch fills the cache, and with nothing published
            // they simply stay empty and Home renders exactly as before.
            await m.createTable(cachedPromotions);
            await m.createTable(promotionEventQueue);
          } else if (from < 10) {
            // The featured subject generalised from book-only to book / author
            // / publisher. Drift can't drop columns without recreating the
            // table, and this is a pure cache — emptying it is correct, and
            // the next /promotions fetch refills it within the half hour.
            await m.deleteTable('cached_promotions');
            await m.createTable(cachedPromotions);
          }
          if (from < 7) {
            // Private per-book notes as their own syncable rows (21 Jul 2026,
            // owner request) — a whole new table. The old free-text blob on
            // library_entries stays exactly where it is: splitting someone's
            // prose into rows automatically would be lossy, so the journal
            // shows it as one undated note until they move it themselves.
            await m.createTable(readingNotes);
          }
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

  /// The `KeyValues` keys that belong to the *reader*, not the device — wiped
  /// on account switch alongside every other Layer 2 table. Everything else in
  /// that table (device_id, the active-user marker) is device state and stays.
  /// Add to this list, not to `KeyValues` blindly: a key that holds anything
  /// personal and isn't named here follows the device to the next reader.
  static const _personalKeys = ['recent_searches', 'reading_goal'];

  /// Wipe all per-user data (Layer 2 entities, the offline caches, the sync
  /// bookkeeping, and the personal `KeyValues` keys) when the signed-in account
  /// changes on this device — so one reader's library, loans, searches or goal
  /// never leak into another's. The rest of `KeyValues` is kept (device
  /// settings + the active-user marker); the sync cursor in `SyncState` is
  /// cleared, so the new account re-pulls everything from server_seq 0.
  Future<void> clearUserData() => transaction(() async {
        await delete(libraryEntries).go();
        await delete(ratings).go();
        await delete(readingSessions).go();
        await delete(readingNotes).go();
        await delete(reviews).go();
        await delete(personalTags).go();
        await delete(libraryEntryTags).go();
        await delete(lendingRecords).go();
        await delete(activityLogEntries).go();
        await delete(syncQueue).go();
        await delete(syncState).go();
        await delete(conflictHistoryEntries).go();
        await delete(cachedBooks).go();
        // Campaigns are resolved per reader (targeting, dismissals, impression
        // counts), so they must go on an account switch exactly like the rest —
        // otherwise the next reader inherits the last one's promotions and
        // their unsent engagement events get attributed to the wrong account.
        await delete(cachedPromotions).go();
        await delete(promotionEventQueue).go();
        await (delete(keyValues)..where((k) => k.key.isIn(_personalKeys))).go();
      });
}
