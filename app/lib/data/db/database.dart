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

  /// Whether [table] already has [column] — consulted before every
  /// `addColumn` in [migration]. Column-adds are the one step SQLite cannot
  /// re-run (`duplicate column name` is fatal), and a migration here *can*
  /// re-run: drift does not wrap `onUpgrade` in a transaction, and the
  /// workmanager background engine opens this same file from its own process,
  /// so a crash — or two processes racing the same upgrade — leaves the column
  /// added but `user_version` unbumped. Found on-device 25 Aug 2026: a DB
  /// stamped v7 with the v13 column already present crashed every open, which
  /// wedged the app on the splash screen permanently. Every step must be safe
  /// to re-run (`createTable`/`deleteTable` emit IF (NOT) EXISTS and
  /// `TableMigration` rebuilds, so they already are).
  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect("PRAGMA table_info('$table')").get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, Object?> table,
    GeneratedColumn column,
  ) async {
    if (await _hasColumn(table.actualTableName, column.name)) return;
    try {
      await m.addColumn(table, column);
    } on Exception catch (e) {
      // The racing migrator added it between our check and this statement —
      // the column exists, which is all this step promises.
      if (!e.toString().contains('duplicate column name')) rethrow;
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Steps run oldest-first, so a partially-applied upgrade replays in
    // the order the schema actually evolved — never a newer step against
    // a shape the older steps haven't produced yet.
    onUpgrade: (m, from, to) async {
      // Two migrators can run at once (the app and workmanager's background
      // engine open this same file with separate connections), and drift
      // does not serialize them. A single wrapping transaction is not an
      // option — TableMigration BEGINs its own inside — so the defence is
      // convergence, not atomicity: wait instead of failing when the other
      // migrator holds the write lock, re-check the on-disk version at
      // entry, and make every step below safe to re-run against a database
      // any prefix of this list has already touched. An interrupted or
      // interleaved attempt then simply heals on the next open.
      await customStatement('PRAGMA busy_timeout = 30000');
      for (var attempt = 0; ; attempt++) {
        final disk = await customSelect(
          'PRAGMA user_version',
        ).getSingle().then((row) => row.read<int>('user_version'));
        if (disk >= to) return; // another opener already finished
        try {
          await _upgradeSteps(m, disk);
          // Stamp promptly so a competing migrator's version re-check exits
          // as early as possible. Drift re-stamps after this returns.
          await customStatement('PRAGMA user_version = $to');
          return;
        } on Exception catch (e) {
          // Losing the race wears many faces: "database is locked" (SQLite
          // returns BUSY immediately, not via the busy handler, when waiting
          // would deadlock two open transactions), a duplicate column the
          // winner added first, or a TableMigration built against a shape
          // the winner changed mid-flight ("no such column"). Any SQLite
          // error here gets a backoff and another pass — the guards make a
          // re-run skip whatever already succeeded, so retrying is cheap and
          // a genuine schema bug still surfaces once the attempts run out.
          if (!e.toString().contains('SqliteException') || attempt >= 4) {
            rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    },
  );

  Future<void> _upgradeSteps(Migrator m, int from) async {
    if (from < 2 && !await _hasColumn('lending_records', 'direction')) {
      // Lending runs both ways now: add direction/editionId/linkedLoanId/
      // note and make libraryEntryId nullable (borrowed books aren't owned).
      // TableMigration recreates the table with the new schema, copying
      // existing rows and defaulting the new columns.
      // TableMigration is the canonical drift way to add columns + relax
      // a NOT NULL at once; marked experimental but stable in practice.
      // Guarded like the addColumns: the rebuild is only needed when the
      // table still has its old shape, and skipping keeps a re-run cheap
      // and un-raceable.
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
      await _addColumnIfMissing(m, syncQueue, syncQueue.userId);
    }
    if (from < 4) {
      // Reading sessions (10 Jul 2026, pulled forward from the v1.5
      // parking lot) — a whole new table, nothing to migrate from.
      await m.createTable(readingSessions);
    }
    if (from < 5) {
      // Unifies borrowed books into the library (15 Jul 2026, owner
      // request) — existing borrowed loans get their LibraryEntry (and
      // this device's copy of that row) via the normal pull, since the
      // server-side migration backfills them with fresh server_seq
      // values above any cursor a device could already be at; nothing
      // to backfill locally, just the new column.
      await _addColumnIfMissing(m, libraryEntries, libraryEntries.ownership);
    }
    if (from < 6) {
      // Work.form ("Type": Novel/Short stories/Poetry…) mirrored into
      // the offline cache for the library filter (16 Jul 2026). Cached
      // rows refresh on their next catalog fetch; null until then.
      await _addColumnIfMissing(m, cachedBooks, cachedBooks.form);
    }
    if (from < 7) {
      // Private per-book notes as their own syncable rows (21 Jul 2026,
      // owner request) — a whole new table. The old free-text blob on
      // library_entries stays exactly where it is: splitting someone's
      // prose into rows automatically would be lossy, so the journal
      // shows it as one undated note until they move it themselves.
      await m.createTable(readingNotes);
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
    if (from < 11) {
      // The community rating mirrored onto shelf covers (9 Aug 2026).
      // Null until each book's next catalog re-fetch fills it.
      await _addColumnIfMissing(m, cachedBooks, cachedBooks.aggregateRating);
    }
    if (from < 12) {
      // A rating or a review now names a book OR a series (13 Aug 2026),
      // so `work_id` has to be nullable. SQLite cannot relax NOT NULL in
      // place, and Drift's TableMigration is the supported way: it builds
      // the table at its current Dart shape and copies every column the
      // two shapes share, so existing rows keep their book and simply
      // gain a null series. Each rebuild is guarded by the column it
      // introduces, so a re-run (or the second of two racing migrators)
      // skips a table already at the new shape.
      // `newColumns` is not documentation — drift copies every column of the
      // current Dart shape EXCEPT these from the old table, and it never
      // introspects what the old table actually has. Omitting it made this
      // step emit `SELECT "series_id" FROM ratings` against pre-v12 tables:
      // macOS's system sqlite (host tests) has double-quoted-string literals
      // enabled and silently copied the *string* 'series_id', while the
      // sqlite bundled on devices has DQS off and errored every open — which
      // would have wedged every store install upgrading past v11 (found
      // on-emulator, 25 Aug 2026, before any such update shipped).
      if (!await _hasColumn('ratings', 'series_id')) {
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(ratings, newColumns: [ratings.seriesId]),
        );
      }
      if (!await _hasColumn('reviews', 'series_id')) {
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(reviews, newColumns: [reviews.seriesId]),
        );
      }
    }
    if (from < 13) {
      // Flags a sitting closed by the auto-stop safety net rather than
      // the reader tapping Stop, so the reading log can offer a
      // correction (owner report, 23 Aug 2026). Existing rows default
      // to false — there's no way to tell after the fact which of them
      // were auto-stopped, and treating them as ordinary stops is the
      // safe direction.
      await _addColumnIfMissing(
        m,
        readingSessions,
        readingSessions.autoStopped,
      );
    }
  }

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
