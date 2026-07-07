import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_engine.dart';

class _FakeApiClient extends ApiClient {
  final List<Map<String, dynamic>> pushedOps = [];
  List<Map<String, dynamic>> nextPushResults = [];
  bool throwOnPush = false;
  Map<String, dynamic> nextPull = {'changes': [], 'next_cursor': 0, 'has_more': false};

  @override
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    if (throwOnPush) throw Exception('offline');
    pushedOps.addAll(ops);
    return nextPushResults;
  }

  @override
  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async {
    return nextPull;
  }
}

void main() {
  late AppDatabase db;
  late _FakeApiClient api;
  late SyncEngine engine;
  const session = SessionContext(userId: 'user-1', deviceId: 'device-1');

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApiClient();
    engine = SyncEngine(db, api);
  });

  tearDown(() => db.close());

  test('adding a book writes to Drift and enqueues a create op', () async {
    final repo = LibraryRepository(db, session);
    final id = await repo.add(editionId: 'edition-1', status: 'reading');

    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry, isNotNull);
    expect(entry!.id, id);
    expect(entry.status, 'reading');
    expect(entry.syncStatus, 'pending');

    final pending = await db.syncQueueDao.pending(limit: 10);
    expect(pending, hasLength(1));
    expect(pending.first.entity, 'library_entries');
    expect(pending.first.opType, 'create');
    expect(pending.first.deviceId, 'device-1');
  });

  test('syncNow pushes queued ops with the wire shape the API expects', () async {
    final repo = LibraryRepository(db, session);
    final id = await repo.add(editionId: 'edition-1');
    api.nextPushResults = [
      {'op_id': (await db.syncQueueDao.pending(limit: 1)).first.opId, 'status': 'applied', 'server_seq': 7},
    ];

    await engine.syncNow('user-1');

    expect(api.pushedOps, hasLength(1));
    final op = api.pushedOps.first;
    expect(op['entity'], 'library_entries');
    expect(op['device_id'], 'device-1');
    expect(op['payload'], {'edition_id': 'edition-1', 'status': 'pending'});

    // Queue drained and the row marked synced with the server's seq.
    expect(await db.syncQueueDao.pending(limit: 10), isEmpty);
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.syncStatus, 'synced');
    expect(entry.serverSeq, 7);
    expect(entry.id, id);
  });

  test('a rejected push (not deleted_wins) is marked error and removed from the queue', () async {
    final repo = LibraryRepository(db, session);
    await repo.add(editionId: 'edition-1');
    final opId = (await db.syncQueueDao.pending(limit: 1)).first.opId;
    api.nextPushResults = [
      {'op_id': opId, 'status': 'rejected', 'code': 'invalid_reference'},
    ];

    await engine.syncNow('user-1');

    expect(await db.syncQueueDao.pending(limit: 10), isEmpty);
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.syncStatus, 'error');
  });

  test('pull applies an incoming change via insert-on-conflict-update', () async {
    api.nextPull = {
      'changes': [
        {
          'entity': 'library_entries',
          'data': {
            'id': 'remote-entry-1',
            'user_id': 'user-1',
            'edition_id': 'edition-9',
            'status': 'read',
            'start_date': null,
            'finish_date': null,
            'current_page': null,
            'is_favorite': false,
            'notes': null,
            'created_at': '2026-07-06T10:00:00+00:00',
            'updated_at': '2026-07-06T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 42,
          },
        },
      ],
      'next_cursor': 42,
      'has_more': false,
    };

    await engine.syncNow('user-1');

    final entry = await db.libraryEntriesDao.getByEditionId('edition-9');
    expect(entry, isNotNull);
    expect(entry!.id, 'remote-entry-1');
    expect(entry.status, 'read');
    expect(entry.syncStatus, 'synced');
    expect(entry.serverSeq, 42);

    // Cursor advances so a second sync doesn't re-fetch the same page.
    expect(await db.syncStateDao.cursorFor('user-1'), 42);
  });

  test('pull applies a borrowed mirror record (null library_entry_id, has edition_id)', () async {
    // A book lent to me by a connected reader arrives as a borrowed mirror:
    // library_entry_id is null (I don't own it) and the book rides on edition_id.
    // The old apply cast library_entry_id to a non-null String and threw, failing
    // the whole pull; and it dropped direction/edition_id so the Borrowed shelf
    // stayed empty. This locks in the fix.
    api.nextPull = {
      'changes': [
        {
          'entity': 'lending_records',
          'data': {
            'id': 'mirror-1',
            'user_id': 'user-1',
            'direction': 'borrowed',
            'library_entry_id': null,
            'edition_id': 'edition-borrowed-1',
            'borrower_name': 'Alice',
            'borrower_user_id': 'lender-1',
            'linked_loan_id': 'loan-1',
            'lent_date': '2026-07-06',
            'due_date': null,
            'returned_date': null,
            'note': null,
            'created_at': '2026-07-06T10:00:00+00:00',
            'updated_at': '2026-07-06T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 50,
          },
        },
      ],
      'next_cursor': 50,
      'has_more': false,
    };

    await engine.syncNow('user-1');

    final records = await db.select(db.lendingRecords).get();
    expect(records, hasLength(1));
    final r = records.first;
    expect(r.id, 'mirror-1');
    expect(r.direction, 'borrowed');
    expect(r.libraryEntryId, isNull);
    expect(r.editionId, 'edition-borrowed-1');
    expect(r.borrowerName, 'Alice');
    expect(r.linkedLoanId, 'loan-1');
    // The pull committed (cursor advanced) — i.e. it didn't crash and roll back.
    expect(await db.syncStateDao.cursorFor('user-1'), 50);
    // And it's queued for cover hydration (no owned entry, so edition-carried).
    expect(await db.lendingRecordsDao.activeBorrowedEditionIds(), ['edition-borrowed-1']);
  });

  test('a row with a pending local op is not clobbered by an in-flight pull', () async {
    final repo = LibraryRepository(db, session);
    await repo.add(editionId: 'edition-1', status: 'reading');
    final localEntry = await db.libraryEntriesDao.getByEditionId('edition-1');

    // Server sends back a change for the SAME id before our push landed.
    api.nextPull = {
      'changes': [
        {
          'entity': 'library_entries',
          'data': {
            'id': localEntry!.id,
            'user_id': 'user-1',
            'edition_id': 'edition-1',
            'status': 'read', // would overwrite 'reading' if applied
            'start_date': null,
            'finish_date': null,
            'current_page': null,
            'is_favorite': false,
            'notes': null,
            'created_at': '2026-07-06T10:00:00+00:00',
            'updated_at': '2026-07-06T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 1,
          },
        },
      ],
      'next_cursor': 1,
      'has_more': false,
    };
    api.throwOnPush = true; // simulate offline — the local edit hasn't pushed yet

    await engine.syncNow('user-1');

    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.status, 'reading'); // local pending edit wins until it pushes
  });
}
