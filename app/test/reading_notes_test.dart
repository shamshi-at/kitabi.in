import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';

/// Notes are a Layer-2 syncable entity, and the whole point of the feature is
/// that they reach the reader's *other devices*. Offline-first means the write
/// lands in Drift immediately and an op goes in the outbox for the engine to
/// carry — so the outbox is what these assert, not just the local row.
void main() {
  const editionId = '44444444-4444-4444-4444-444444444444';
  late AppDatabase db;
  late LibraryRepository library;
  late ReadingNotesRepository notes;
  late String entryId;

  setUp(() async {
    // Never closed — db.close() deadlocks between fake-async and drift.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    library = LibraryRepository(db, session);
    notes = ReadingNotesRepository(db, session);
    entryId = await library.add(editionId: editionId);
    // Clear the entry's own create op so assertions below see only note ops.
    await db.delete(db.syncQueue).go();
  });

  Future<List<SyncQueueData>> outbox() => db.select(db.syncQueue).get();

  test('a note is written locally and queued for the reader other devices', () async {
    final id = await notes.add(
      libraryEntryId: entryId,
      body: 'The Malabar sections read like memory, not plot.',
      pageStart: 24,
      pageEnd: 27,
    );

    final row = await db.readingNotesDao.getById(id);
    expect(row?.body, 'The Malabar sections read like memory, not plot.');
    expect(row?.pageStart, 24);
    expect(row?.pageEnd, 27);
    expect(row?.syncStatus, 'pending');

    final ops = await outbox();
    expect(ops, hasLength(1));
    expect(ops.single.entity, 'reading_notes');
    expect(ops.single.opType, 'create');
    expect(ops.single.payload, contains('Malabar'));
  });

  test('a note needs neither a sitting nor a page', () async {
    // "Lent to mom, she folds pages" belongs to the book, not to a stretch of
    // reading — this is the shape the old free-text blob held.
    final id = await notes.add(
      libraryEntryId: entryId,
      body: 'Lent to mom — she folds pages.',
    );

    final row = await db.readingNotesDao.getById(id);
    expect(row?.sessionId, isNull);
    expect(row?.pageStart, isNull);
    expect(row?.pageEnd, isNull);
  });

  /// The sitting a note is written during isn't a row yet — it lives in
  /// key_values until the clock stops. Sending its id to the server names a
  /// `reading_sessions` row that doesn't exist, and the server refuses to hang
  /// a note off a session it can't prove belongs to the reader: rejected as
  /// `invalid_reference`, dropped from the queue, marked errored. Which meant
  /// every note written while a timer was running — the ones this feature is
  /// for — stayed on the phone that wrote them, forever, in silence.
  group('a note written while the clock is still running', () {
    const sittingId = '99999999-9999-9999-9999-999999999999';

    Future<void> logTheSitting() => ReadingSessionsRepository(
          db,
          const SessionContext(userId: 'u1', deviceId: 'd1'),
        ).logSession(
          id: sittingId,
          libraryEntryId: entryId,
          startedAt: DateTime(2026, 8, 15, 20),
          endedAt: DateTime(2026, 8, 15, 21),
          durationSeconds: 3600,
        );

    test('goes out without the sitting the server has never heard of', () async {
      await notes.add(
        libraryEntryId: entryId,
        sessionId: sittingId,
        body: 'The ferry chapter turns on one word.',
      );

      final ops = await outbox();
      expect(ops.single.payload, isNot(contains('session_id')),
          reason: 'a reference the server cannot resolve is a rejected op');
      // Locally it is attached the whole time — this is only about the wire.
      final row = await db.readingNotesDao.getById(ops.single.entityId);
      expect(row?.sessionId, sittingId);
    });

    test('is handed its sitting the moment the sitting becomes a row', () async {
      final noteId = await notes.add(
        libraryEntryId: entryId,
        sessionId: sittingId,
        body: 'The ferry chapter turns on one word.',
      );
      await db.delete(db.syncQueue).go(); // as if the note had already synced

      await logTheSitting();

      final ops = await outbox();
      expect(ops.map((o) => o.entity).toList(), ['reading_sessions', 'reading_notes'],
          reason: 'the session has to land before anything points at it');
      final link = ops.last;
      expect(link.opType, 'update');
      expect(link.entityId, noteId);
      expect(link.payload, contains(sittingId));
    });

    test('a note written *after* the sitting was logged carries it outright',
        () async {
      await logTheSitting();
      await db.delete(db.syncQueue).go();

      await notes.add(
        libraryEntryId: entryId,
        sessionId: sittingId,
        body: 'Read it again on the platform.',
      );

      final ops = await outbox();
      expect(ops, hasLength(1), reason: 'nothing to defer, nothing to repair');
      expect(ops.single.payload, contains(sittingId));
    });
  });

  test('notes stream per book, newest first', () async {
    await notes.add(libraryEntryId: entryId, body: 'first');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await notes.add(libraryEntryId: entryId, body: 'second');

    final list = await notes.watchForEntry(entryId).first;
    expect(list.map((n) => n.body), ['second', 'first']);
  });

  test('notes stream per sitting, oldest first — the order they were thought', () async {
    await notes.add(libraryEntryId: entryId, body: 'no session');
    await notes.add(libraryEntryId: entryId, body: 'during', sessionId: 's1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await notes.add(libraryEntryId: entryId, body: 'also during', sessionId: 's1');

    final list = await notes.watchForSession('s1').first;
    expect(list.map((n) => n.body), ['during', 'also during']);
  });

  test('editing changes the words and queues an update, never re-dating', () async {
    final id = await notes.add(
      libraryEntryId: entryId,
      body: 'first thought',
      sessionId: 's1',
      pageStart: 22,
    );
    final before = await db.readingNotesDao.getById(id);
    await db.delete(db.syncQueue).go();

    await notes.edit(id, body: 'a better thought', pageStart: 22);

    final after = await db.readingNotesDao.getById(id);
    expect(after?.body, 'a better thought');
    // The journal records when you thought something — an edit must not move
    // the note, or it stops being a record and becomes a draft.
    expect(after?.createdAt, before?.createdAt);
    expect(after?.sessionId, 's1');

    final ops = await outbox();
    expect(ops.single.opType, 'update');
  });

  test('a page can be cleared, unpinning the note', () async {
    final id = await notes.add(
      libraryEntryId: entryId,
      body: 'about the whole book, really',
      pageStart: 22,
    );

    await notes.edit(id, body: 'about the whole book, really');

    final row = await db.readingNotesDao.getById(id);
    expect(row?.pageStart, isNull);
    expect(row?.pageEnd, isNull);
  });

  test('deleting is a soft delete that queues a tombstone', () async {
    final id = await notes.add(libraryEntryId: entryId, body: 'regrettable');
    await db.delete(db.syncQueue).go();

    await notes.remove(id);

    final row = await db.readingNotesDao.getById(id);
    expect(row, isNotNull); // still there — rule 3, never a hard DELETE
    expect(row?.deletedAt, isNotNull);
    // And it drops out of the journal.
    expect(await notes.watchForEntry(entryId).first, isEmpty);

    final ops = await outbox();
    expect(ops.single.opType, 'delete');
  });

  test('an account switch takes every note with it', () async {
    await notes.add(libraryEntryId: entryId, body: 'private to this reader');

    await db.clearUserData();

    expect(await db.select(db.readingNotes).get(), isEmpty);
  });
}
