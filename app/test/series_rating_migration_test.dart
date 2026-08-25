import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';

/// See migration_wedge_test.dart: device sqlite has double-quoted string
/// literals disabled, and testing against the permissive macOS build let a
/// device-only migration failure through. Match the device.
void _matchDeviceSqlite(Database db) {
  db.config.doubleQuotedStringLiterals = false;
}

/// The v11 → v12 upgrade, run against a real file database.
///
/// This is the step that touches data already on readers' phones: `work_id` was
/// NOT NULL, and SQLite cannot relax that in place, so drift rebuilds the two
/// tables and copies the rows across. A mistake here is not a failed feature —
/// it is a reader's ratings and reviews gone. The unit tests above exercise the
/// new columns on a fresh database, which by construction never runs this path.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kitabi_migration_test');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Rewrites `ratings` and `reviews` back to their v11 shape — `work_id`
  /// NOT NULL, no `series_id` — and stamps the file as schema 11, so opening
  /// AppDatabase over it runs the real upgrade rather than a fresh create.
  Future<void> downgradeToV11(AppDatabase db) async {
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
    await db.customStatement(
      'INSERT INTO ratings (id, user_id, created_at, updated_at, sync_status, work_id, value) '
      "VALUES ('r1', 'u1', 1, 1, 'synced', 'work-1', 4)",
    );
    await db.customStatement(
      'INSERT INTO reviews '
      '(id, user_id, created_at, updated_at, sync_status, work_id, body, visible) '
      "VALUES ('v1', 'u1', 1, 1, 'synced', 'work-1', 'A fine book.', 1)",
    );
    // v13 added reading_sessions.auto_stopped (23 Aug 2026) — createAll above
    // built every other table at the *current* Dart shape regardless of the
    // stamped version below, so without this the v13 onUpgrade step tries to
    // add a column that's already there.
    await db.customStatement(
      'ALTER TABLE reading_sessions DROP COLUMN auto_stopped',
    );
    await db.customStatement('PRAGMA user_version = 11');
  }

  test('upgrading from v11 keeps existing ratings and reviews', () async {
    final seed = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    await downgradeToV11(seed);
    await seed.close();

    // Reopening runs onUpgrade(11 → 12).
    final db = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    const session = SessionContext(userId: 'u1', deviceId: 'd1');

    final rating = await RatingsRepository(
      db,
      session,
    ).watchForWork('work-1').first;
    expect(rating?.value, 4, reason: 'the rating survived the table rebuild');
    expect(rating?.syncStatus, 'synced', reason: 'and so did its sync state');

    final review = await ReviewsRepository(
      db,
      session,
    ).watchForWork('work-1').first;
    expect(review?.body, 'A fine book.');
    expect(review?.visible, isTrue);

    await db.close();
  });

  test('after upgrading, a series rating can be written alongside', () async {
    final seed = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    await downgradeToV11(seed);
    await seed.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final ratings = RatingsRepository(db, session);

    // The whole point of the rebuild: work_id is now nullable, so this insert
    // would have failed with a NOT NULL constraint before it.
    await ratings.setSeriesRating('series-1', 5);

    expect((await ratings.watchForSeries('series-1').first)?.value, 5);
    expect((await ratings.watchForWork('work-1').first)?.value, 4);

    await db.close();
  });
}
