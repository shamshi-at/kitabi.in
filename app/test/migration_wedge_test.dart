import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kitabi/data/db/database.dart';

/// The sqlite bundled on devices (sqlite3_flutter_libs) is compiled with
/// double-quoted string literals disabled; macOS's system sqlite, which host
/// tests link, still allows them — and that difference let a broken migration
/// (`SELECT "series_id"` against a table without it) pass every host test
/// while erroring on every device (25 Aug 2026). Test databases match the
/// device configuration.
void _matchDeviceSqlite(Database db) {
  db.config.doubleQuotedStringLiterals = false;
}

/// The half-migrated database found on a real device, 25 Aug 2026.
///
/// Drift does not wrap `onUpgrade` in a transaction, and the workmanager
/// background engine opens the same file from its own process — so a crash
/// (or two processes racing one upgrade) can leave a *later* step applied
/// while `user_version` still says an earlier version. The device in
/// question was stamped v7 with the v13 `auto_stopped` column already
/// present: every open re-ran the v13 `addColumn`, SQLite answered
/// "duplicate column name", and the app was permanently wedged on the
/// splash screen. These tests open exactly that database and require the
/// migration to self-heal instead.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kitabi_wedge_test');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Rewinds a freshly-created (v13-shaped) file to the wedged state: the
  /// v8+ artifacts gone, ratings/reviews back at their NOT NULL shape,
  /// `user_version` stamped 7 — but `reading_sessions.auto_stopped` LEFT IN
  /// PLACE, which is the wedge.
  Future<void> wedgeAtV7(AppDatabase db) async {
    await db.customStatement('DROP TABLE cached_promotions');
    await db.customStatement('DROP TABLE promotion_event_queue');
    await db.customStatement(
      'ALTER TABLE cached_books DROP COLUMN aggregate_rating',
    );
    await db.customStatement('DROP TABLE ratings');
    await db.customStatement('DROP TABLE reviews');
    await db.customStatement('''
      CREATE TABLE ratings (
        id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at INTEGER NULL,
        server_seq INTEGER NULL,
        work_id TEXT NOT NULL,
        value INTEGER NOT NULL
      )''');
    await db.customStatement('''
      CREATE TABLE reviews (
        id TEXT NOT NULL PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at INTEGER NULL,
        server_seq INTEGER NULL,
        work_id TEXT NOT NULL,
        body TEXT NOT NULL,
        visible INTEGER NOT NULL DEFAULT 0
      )''');
    // A sitting logged before the wedge — it must survive the healing run.
    await db.customStatement(
      'INSERT INTO reading_sessions '
      '(id, user_id, created_at, updated_at, sync_status, library_entry_id, '
      ' started_at, ended_at, duration_seconds, auto_stopped) '
      "VALUES ('s1', 'u1', 1, 1, 'synced', 'le1', 1, 2, 1800, 0)",
    );
    await db.customStatement('PRAGMA user_version = 7');
  }

  test(
    'a v7 database that already has the v13 column opens and heals',
    () async {
      final seed = AppDatabase.forTesting(
        NativeDatabase(file, setup: _matchDeviceSqlite),
      );
      await seed.customStatement('SELECT 1'); // force open + createAll
      await wedgeAtV7(seed);
      await seed.close();

      // On the unfixed migration this open threw
      // "duplicate column name: auto_stopped" — forever.
      final db = AppDatabase.forTesting(
        NativeDatabase(file, setup: _matchDeviceSqlite),
      );

      final sessions = await db.readingSessionsDao.allSince(
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(sessions, hasLength(1), reason: 'the pre-wedge sitting survived');
      expect(sessions.single.autoStopped, isFalse);

      final version = await db
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version'));
      expect(version, 13, reason: 'the healing run stamps the current version');

      // The steps the failed run never reached have now been applied.
      final promos = await db.promotionsDao
          .watchServable(DateTime.utc(2026))
          .first;
      expect(
        promos,
        isEmpty,
        reason: 'cached_promotions exists and is queryable',
      );
      await db.close();
    },
  );

  test(
    'two connections upgrading the same file at once both come up healthy',
    () async {
      final seed = AppDatabase.forTesting(
        NativeDatabase(file, setup: _matchDeviceSqlite),
      );
      await seed.customStatement('SELECT 1');
      await wedgeAtV7(seed);
      await seed.close();

      // The app and workmanager's background engine each open the file with
      // their own connection — this is that race. The loser's step list is
      // idempotent and retried after a backoff, so both openers converge;
      // without that, the two interleaved a TableMigration rebuild and died
      // with "no such column" (25 Aug 2026).
      final a = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file, setup: _matchDeviceSqlite),
      );
      final b = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file, setup: _matchDeviceSqlite),
      );
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final results = await Future.wait([
        a.readingSessionsDao.allSince(epoch),
        b.readingSessionsDao.allSince(epoch),
      ]);
      expect(results[0], hasLength(1));
      expect(results[1], hasLength(1));

      final version = await a
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version'));
      expect(version, 13);
      await a.close();
      await b.close();
    },
  );

  test('a clean v7 database (column absent) still upgrades normally', () async {
    final seed = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    await seed.customStatement('SELECT 1');
    await wedgeAtV7(seed);
    await seed.customStatement(
      'ALTER TABLE reading_sessions DROP COLUMN auto_stopped',
    );
    await seed.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    final sessions = await db.readingSessionsDao.allSince(
      DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(
      sessions.single.autoStopped,
      isFalse,
      reason: 'the column was added with its default',
    );
    await db.close();
  });
}
