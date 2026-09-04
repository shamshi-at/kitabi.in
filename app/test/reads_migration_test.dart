import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kitabi/data/db/database.dart';

/// v13 → v14: `reads`, plus `read_id` on sittings and notes (rule 19).
///
/// The step is additive — a `createTable` and two `addColumn`s, none of which
/// rebuilds a table — so it cannot fail the way v12 did. What this proves is
/// the part that matters to a reader: **an upgrade from the shipped schema
/// keeps their reading history**, and the new column arrives as null rather
/// than as an error.
///
/// Device sqlite has double-quoted string literals disabled while macOS's
/// system sqlite (which host tests link) allows them — the difference that let
/// a broken migration pass every host test and error on every device, 25 Aug
/// 2026. Test databases match the device.
void _matchDeviceSqlite(Database db) {
  db.config.doubleQuotedStringLiterals = false;
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kitabi_reads_migration');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Rewinds a freshly-created file to the v13 shape: no `reads`, and neither
  /// child carrying `read_id` — the schema every install is on today.
  Future<void> rewindToV13(AppDatabase db) async {
    await db.customStatement('DROP TABLE reads');
    await db.customStatement('ALTER TABLE reading_sessions DROP COLUMN read_id');
    await db.customStatement('ALTER TABLE reading_notes DROP COLUMN read_id');
    await db.customStatement('PRAGMA user_version = 13');
  }

  test('a v13 database upgrades, keeping every sitting and note', () async {
    final seed = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    await seed.customStatement('SELECT 1'); // force open + createAll
    await rewindToV13(seed);
    // A reader's history, written on the old schema.
    await seed.customStatement(
      'INSERT INTO reading_sessions '
      '(id, user_id, created_at, updated_at, sync_status, library_entry_id, '
      ' started_at, ended_at, duration_seconds, auto_stopped) '
      "VALUES ('s1', 'u1', 1, 1, 'synced', 'le1', 1, 2, 1800, 0)",
    );
    await seed.customStatement(
      'INSERT INTO reading_notes '
      '(id, user_id, created_at, updated_at, sync_status, library_entry_id, body) '
      "VALUES ('n1', 'u1', 1, 1, 'synced', 'le1', 'The sea is a character.')",
    );
    await seed.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );

    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((row) => row.read<int>('user_version'));
    expect(version, db.schemaVersion, reason: 'the upgrade ran and stamped');

    final sessions = await db.readingSessionsDao.allSince(
      DateTime.fromMillisecondsSinceEpoch(0),
    );
    expect(sessions, hasLength(1), reason: 'the pre-upgrade sitting survived');
    expect(
      sessions.single.readId,
      isNull,
      reason: 'unstamped until the server backfill arrives — not an error',
    );

    final notes = await db.readingNotesDao.watchForEntry('le1').first;
    expect(notes, hasLength(1), reason: 'the pre-upgrade note survived');
    expect(notes.single.readId, isNull);

    // The table exists and is empty: the client deliberately back-fills
    // nothing, because the server's migration writes the passes and they
    // arrive by the ordinary pull. Doing both would mint two ids for one pass.
    expect(await db.readsDao.forEntry('le1'), isEmpty);

    await db.close();
  });

  test('the upgrade step is safe to re-run', () async {
    // Drift does not wrap onUpgrade in a transaction and the workmanager
    // engine opens the same file from another process, so a step can be
    // replayed against a database it has already touched. On the v13 column
    // step that was fatal ("duplicate column name") and wedged devices
    // permanently — every step since is guarded, and this is that guard.
    final seed = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    await seed.customStatement('SELECT 1');
    // The half-applied shape: `reads` and one column already added by a run
    // that died before stamping the version.
    await seed.customStatement('ALTER TABLE reading_notes DROP COLUMN read_id');
    await seed.customStatement('PRAGMA user_version = 13');
    await seed.close();

    final db = AppDatabase.forTesting(
      NativeDatabase(file, setup: _matchDeviceSqlite),
    );
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((row) => row.read<int>('user_version'));
    expect(version, db.schemaVersion);
    expect(await db.readsDao.forEntry('le1'), isEmpty);
    await db.close();
  });
}
