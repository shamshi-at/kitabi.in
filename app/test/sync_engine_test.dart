import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_engine.dart';

class _FakeApiClient extends ApiClient {
  final List<Map<String, dynamic>> pushedOps = [];
  List<Map<String, dynamic>> nextPushResults = [];
  bool autoApplyAll = false; // answer every op with applied + a fake seq
  int _seq = 100;
  bool throwOnPush = false;
  Map<String, dynamic> nextPull = {'changes': [], 'next_cursor': 0, 'has_more': false};
  int pullCalls = 0;
  Future<void>? pullGate;

  @override
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    if (throwOnPush) throw Exception('offline');
    pushedOps.addAll(ops);
    if (autoApplyAll) {
      return [
        for (final op in ops)
          {'op_id': op['op_id'], 'status': 'applied', 'server_seq': ++_seq},
      ];
    }
    return nextPushResults;
  }

  final List<String> workByEditionCalls = [];

  @override
  Future<Map<String, dynamic>> getWorkByEdition(String editionId) async {
    workByEditionCalls.add(editionId);
    return {
      'id': 'w-$editionId',
      'title': 'Hydrated $editionId',
      'subtitle': null,
      'first_publish_year': null,
      'authors': [
        {'id': 'a1', 'name': 'An Author'},
      ],
      'genres': const <Map<String, dynamic>>[],
      'editions': [
        {
          'id': editionId,
          'isbn': null,
          'language': null,
          'page_count': null,
          'format': null,
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async {
    pullCalls++;
    if (pullGate != null) await pullGate;
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
    expect(op['payload'], {'edition_id': 'edition-1', 'status': 'pending', 'ownership': 'owned'});

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

  test('the drain only pushes the signed-in user\'s ops', () async {
    // An account switch racing a sync must never push the previous reader's
    // queued ops under the new reader's JWT — the outbox is user-scoped.
    final mine = LibraryRepository(db, session);
    final theirs = LibraryRepository(
      db,
      const SessionContext(userId: 'user-2', deviceId: 'device-2'),
    );
    await mine.add(editionId: 'edition-mine');
    await theirs.add(editionId: 'edition-theirs');
    api.autoApplyAll = true;

    await engine.syncNow('user-1');

    expect(api.pushedOps, hasLength(1));
    expect(api.pushedOps.single['device_id'], 'device-1');
    // user-2's op is still queued, untouched, for their own session to push.
    final left = await db.syncQueueDao.pending(limit: 10, userId: 'user-2');
    expect(left, hasLength(1));
  });

  test('an op the server does not answer cannot spin the drain forever', () async {
    // A partial/malformed push response used to leave the unanswered op
    // untouched — pending() re-fetched it and the while-loop re-pushed it
    // endlessly in a single drain. Now each unanswered round costs an attempt,
    // so the op errors out after maxAttempts and the drain terminates.
    final repo = LibraryRepository(db, session);
    await repo.add(editionId: 'edition-1');
    api.nextPushResults = []; // server answers nothing, every time

    await engine.syncNow('user-1'); // must return, not hang

    expect(api.pushedOps.length, lessThanOrEqualTo(5)); // maxAttempts rounds
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(entry!.syncStatus, 'error'); // surfaced, not silent
  });

  test('a deleted_wins rejection soft-deletes the row locally', () async {
    // While our update op sat in the queue, the pull carrying the server-side
    // delete was skipped (pending-op guard) and the cursor advanced past it.
    // A rejected op bumps no server_seq, so no future pull re-delivers the
    // delete — the push result is the only signal, and it must be applied.
    final repo = LibraryRepository(db, session);
    await repo.add(editionId: 'edition-1');
    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    final opId = (await db.syncQueueDao.pending(limit: 1)).first.opId;
    api.nextPushResults = [
      {'op_id': opId, 'status': 'rejected', 'code': 'deleted_wins'},
    ];

    await engine.syncNow('user-1');

    expect(await db.syncQueueDao.pending(limit: 10), isEmpty);
    final after = await db.libraryEntriesDao.getByEditionId('edition-1');
    expect(after == null || after.deletedAt != null, isTrue,
        reason: 'the row must be locally soft-deleted, not left alive (id ${entry!.id})');
  });

  test('a trigger during an in-flight sync coalesces into a follow-up pass', () async {
    // A mutation enqueued mid-sync used to be silently dropped by the old
    // `_inFlight ??=` guard — the op sat in the queue until the next external
    // trigger (up to 15 minutes). Now the second trigger marks a follow-up
    // pass that runs as soon as the current one finishes.
    final gate = Completer<void>();
    api.pullGate = gate.future;

    final first = engine.syncNow('user-1'); // pass 1: parked on the pull gate
    final second = engine.syncNow('user-1'); // mid-flight trigger — coalesced

    expect(identical(first, second), isTrue); // no overlapping second pass
    gate.complete();
    await first;

    expect(api.pullCalls, 2); // the follow-up pass actually ran
  });

  test('a repository mutation fires the onMutation sync hook', () async {
    var fired = 0;
    final repo = LibraryRepository(db, session, onMutation: () => fired++);

    await repo.add(editionId: 'edition-1');
    expect(fired, 1); // every enqueued op asks the engine to drain immediately

    final entry = await db.libraryEntriesDao.getByEditionId('edition-1');
    await repo.updateStatus(entry!.id, 'read');
    expect(fired, 2);
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

  test('a pull hydrates the catalog cache for owned books, not just borrowed', () async {
    // The fresh-install gap: a pull restores library_entries (synced) but
    // cached_books is device-local, so every Home card rendered its
    // `book?.title ?? '…'` fallback. Healing lived only in the library grid's
    // initState, so Home stayed full of "…" until you visited that tab
    // (owner report, 23 Jul 2026).
    api.nextPull = {
      'changes': [
        {
          'entity': 'library_entries',
          'data': {
            'id': 'entry-owned',
            'user_id': 'user-1',
            'edition_id': 'edition-owned',
            'status': 'reading',
            'start_date': null,
            'finish_date': null,
            'current_page': null,
            'is_favorite': false,
            'notes': null,
            'created_at': '2026-07-23T10:00:00+00:00',
            'updated_at': '2026-07-23T10:00:00+00:00',
            'deleted_at': null,
            'server_seq': 7,
          },
        },
      ],
      'next_cursor': 7,
      'has_more': false,
    };

    await engine.syncNow('user-1');

    final cached = await db.cachedBooksDao.getByEditionId('edition-owned');
    expect(cached, isNotNull, reason: 'the pull must hydrate the owned book');
    expect(cached!.title, 'Hydrated edition-owned');
    expect(api.workByEditionCalls, contains('edition-owned'));
  });
}
