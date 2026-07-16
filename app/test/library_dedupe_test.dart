import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/library_dedupe.dart';
import 'package:kitabi/data/sync/sync_engine.dart';

/// Duplicate active library entries for one edition — reachable when a pull
/// delivers an entry created on another device/install next to the local one
/// (upserts are by id). These lock in: the tolerant lookup, the idempotent
/// add, and the post-pull heal that merges the rows back into one.
class _FakeApiClient extends ApiClient {
  Map<String, dynamic> nextPull = {'changes': [], 'next_cursor': 0, 'has_more': false};
  bool pullOnce = true; // serve nextPull once, then empty pages
  int pullCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    return [
      for (final op in ops) {'op_id': op['op_id'], 'status': 'applied', 'server_seq': 1},
    ];
  }

  @override
  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async {
    pullCalls++;
    if (pullOnce && pullCalls > 1) {
      return {'changes': [], 'next_cursor': cursor, 'has_more': false};
    }
    return nextPull;
  }
}

void main() {
  late AppDatabase db;
  const userId = 'user-1';
  const deviceId = 'device-1';
  const session = SessionContext(userId: userId, deviceId: deviceId);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> insertEntry(
    String id, {
    String editionId = 'edition-1',
    required DateTime createdAt,
    DateTime? updatedAt,
    String status = 'pending',
    String ownership = 'owned',
    int? currentPage,
    DateTime? startDate,
    DateTime? finishDate,
    bool isFavorite = false,
    String? notes,
  }) {
    return db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(
        id: id,
        userId: userId,
        editionId: editionId,
        status: Value(status),
        ownership: Value(ownership),
        currentPage: Value(currentPage),
        startDate: Value(startDate),
        finishDate: Value(finishDate),
        isFavorite: Value(isFavorite),
        notes: Value(notes),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt ?? createdAt),
      ),
    );
  }

  test('getByEditionId prefers the original instead of throwing on duplicates', () async {
    await insertEntry('newer', createdAt: DateTime(2026, 7, 10));
    await insertEntry('original', createdAt: DateTime(2026, 7, 1));

    // Used to throw "Bad state: Too many elements" (getSingleOrNull on 2 rows),
    // which blanked the whole Yours tab.
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.id, 'original');
  });

  test('add() reuses the existing active entry instead of creating a duplicate', () async {
    final repo = LibraryRepository(db, session);
    final first = await repo.add(editionId: 'edition-1');
    final second = await repo.add(editionId: 'edition-1'); // the double-tap

    expect(second, first);
    final rows = await db.libraryEntriesDao.activeForUser(userId);
    expect(rows, hasLength(1));
    // Only the first tap enqueued a create op.
    final ops = await db.syncQueueDao.pending(limit: 10);
    expect(ops, hasLength(1));
  });

  test('heal merges duplicates: folds content, re-points children, soft-deletes', () async {
    // The original (keeper): older, has notes and a finish date.
    await insertEntry(
      'keeper',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 2),
      status: 'read',
      currentPage: 120,
      finishDate: DateTime(2026, 7, 2),
      notes: 'my notes',
    );
    // The duplicate: newer, more recently touched, further progress, favorite.
    await insertEntry(
      'dup',
      createdAt: DateTime(2026, 7, 10),
      updatedAt: DateTime(2026, 7, 12),
      status: 'reading',
      currentPage: 200,
      startDate: DateTime(2026, 7, 10),
      isFavorite: true,
    );

    // Children hanging off the duplicate.
    await db.readingSessionsDao.insertOne(ReadingSessionsCompanion.insert(
      id: 'session-1',
      userId: userId,
      libraryEntryId: 'dup',
      startedAt: DateTime(2026, 7, 11, 20),
      endedAt: DateTime(2026, 7, 11, 21),
      durationSeconds: 3600,
    ));
    await db.lendingRecordsDao.insertOne(LendingRecordsCompanion.insert(
      id: 'loan-1',
      userId: userId,
      libraryEntryId: Value('dup'),
      borrowerName: 'Anu',
      lentDate: DateTime(2026, 7, 11),
    ));
    await db.tagsDao.insertTag(PersonalTagsCompanion.insert(
      id: 'tag-shared',
      userId: userId,
      name: 'favourites',
    ));
    await db.tagsDao.insertTag(PersonalTagsCompanion.insert(
      id: 'tag-only-dup',
      userId: userId,
      name: 'malayalam',
    ));
    // tag-shared is on both entries; tag-only-dup only on the duplicate.
    await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
      id: 'assign-keeper-shared',
      userId: userId,
      libraryEntryId: 'keeper',
      tagId: 'tag-shared',
    ));
    await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
      id: 'assign-dup-shared',
      userId: userId,
      libraryEntryId: 'dup',
      tagId: 'tag-shared',
    ));
    await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
      id: 'assign-dup-only',
      userId: userId,
      libraryEntryId: 'dup',
      tagId: 'tag-only-dup',
    ));

    final merged = await healDuplicateLibraryEntries(db, userId: userId, deviceId: deviceId);
    expect(merged, 1);

    // One active entry left — the original — with everything folded in.
    final active = await db.libraryEntriesDao.activeForUser(userId);
    expect(active, hasLength(1));
    final keeper = active.single;
    expect(keeper.id, 'keeper');
    expect(keeper.status, 'reading'); // from the most recently updated row
    expect(keeper.currentPage, 200); // furthest progress
    expect(keeper.startDate, DateTime(2026, 7, 10)); // earliest start
    expect(keeper.finishDate, DateTime(2026, 7, 2)); // kept
    expect(keeper.isFavorite, isTrue); // OR-ed
    expect(keeper.notes, 'my notes'); // keeper's notes survive

    // Children now hang off the keeper.
    final session1 = (await db.select(db.readingSessions).get()).single;
    expect(session1.libraryEntryId, 'keeper');
    final loan = (await db.select(db.lendingRecords).get()).single;
    expect(loan.libraryEntryId, 'keeper');

    // Tags: the shared tag isn't duplicated; the dup-only tag moved over.
    final assignments = await (db.select(db.libraryEntryTags)
          ..where((t) => t.libraryEntryId.equals('keeper') & t.deletedAt.isNull()))
        .get();
    expect(assignments.map((a) => a.tagId).toSet(), {'tag-shared', 'tag-only-dup'});
    final dupAssignments = await (db.select(db.libraryEntryTags)
          ..where((t) => t.libraryEntryId.equals('dup') & t.deletedAt.isNull()))
        .get();
    expect(dupAssignments, isEmpty);

    // Every mutation was enqueued for the server to converge too.
    final ops = await db.syncQueueDao.pending(limit: 20);
    final byKind = <String, int>{};
    for (final op in ops) {
      byKind['${op.entity}/${op.opType}'] = (byKind['${op.entity}/${op.opType}'] ?? 0) + 1;
    }
    expect(byKind['library_entries/update'], 1); // folded keeper fields
    expect(byKind['library_entries/delete'], 1); // the duplicate
    expect(byKind['reading_sessions/update'], 1);
    expect(byKind['lending_records/update'], 1);
    expect(byKind['library_entry_tags/create'], 1); // dup-only tag onto keeper
    expect(byKind['library_entry_tags/delete'], 2); // both dup assignments

    // The wire payloads carry the re-pointed ids / date-only fields.
    final sessionOp =
        ops.singleWhere((o) => o.entity == 'reading_sessions' && o.opType == 'update');
    expect(jsonDecode(sessionOp.payload), {'library_entry_id': 'keeper'});
    final keeperOp =
        ops.singleWhere((o) => o.entity == 'library_entries' && o.opType == 'update');
    final keeperPayload = jsonDecode(keeperOp.payload) as Map<String, dynamic>;
    expect(
      keeperPayload['start_date'],
      DateTime(2026, 7, 10).toUtc().toIso8601String().split('T').first, // date-only on the wire
    );
    expect(keeperPayload['status'], 'reading');
  });

  test('heal is a no-op when every edition has one entry', () async {
    await insertEntry('a', editionId: 'e1', createdAt: DateTime(2026, 7, 1));
    await insertEntry('b', editionId: 'e2', createdAt: DateTime(2026, 7, 2));

    final merged = await healDuplicateLibraryEntries(db, userId: userId, deviceId: deviceId);
    expect(merged, 0);
    expect(await db.syncQueueDao.pending(limit: 10), isEmpty);
  });

  test('a pull that lands a second entry for an owned edition heals in the same sync', () async {
    // The Aadujeevitham case: this device already has the book; a pull delivers
    // the entry a previous install created for the same edition.
    final repo = LibraryRepository(db, session);
    final localId = await repo.add(editionId: 'edition-1');

    final api = _FakeApiClient();
    api.nextPull = {
      'changes': [
        {
          'entity': 'library_entries',
          'data': {
            'id': 'remote-original',
            'user_id': userId,
            'edition_id': 'edition-1',
            'status': 'read',
            'ownership': 'owned',
            'start_date': null,
            'finish_date': null,
            'current_page': 240,
            'is_favorite': false,
            'notes': null,
            'created_at': '2026-06-01T10:00:00+00:00', // older — the original
            'updated_at': '2026-06-20T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 42,
          },
        },
      ],
      'next_cursor': 42,
      'has_more': false,
    };

    final engine = SyncEngine(db, api);
    await engine.syncNow(userId);

    // One active entry per edition again — the server's original won the
    // identity, and the lookup that used to crash the Yours tab works.
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.id, 'remote-original');
    expect(entry.status, 'read');
    expect(entry.currentPage, 240);
    final active = await db.libraryEntriesDao.activeForUser(userId);
    expect(active, hasLength(1));
    expect(localId, isNot('remote-original'));
    // The heal marked a follow-up pass, so its ops pushed in the same syncNow.
    expect(api.pullCalls, greaterThan(1));
  });

  test('pull maps ownership onto the local row', () async {
    final api = _FakeApiClient();
    api.nextPull = {
      'changes': [
        {
          'entity': 'library_entries',
          'data': {
            'id': 'borrowed-1',
            'user_id': userId,
            'edition_id': 'edition-7',
            'status': 'pending',
            'ownership': 'borrowed', // used to be dropped → defaulted to owned
            'start_date': null,
            'finish_date': null,
            'current_page': null,
            'is_favorite': false,
            'notes': null,
            'created_at': '2026-07-06T10:00:00+00:00',
            'updated_at': '2026-07-06T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 9,
          },
        },
      ],
      'next_cursor': 9,
      'has_more': false,
    };

    final engine = SyncEngine(db, api);
    await engine.syncNow(userId);

    final entry = await db.libraryEntriesDao.getByEditionId('edition-7');
    expect(entry!.ownership, 'borrowed');
  });
}
