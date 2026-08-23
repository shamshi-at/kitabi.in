import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// Owner report, 23 Aug 2026: a sitting ran ~2 hours; the 60-minute check-in
/// was missed and the safety net silently closed it at 90 minutes. The
/// reader only noticed once they tried to stop reading themselves, by which
/// point the logged end time and page were both wrong with no way to fix
/// either. This covers the fix: a session the safety net closes is flagged
/// `autoStopped`, and the reader can correct its end time (and the duration
/// derived from it) and end page afterwards.
void main() {
  const editionId = '44444444-4444-4444-4444-444444444444';
  late AppDatabase db;
  late LibraryRepository library;
  late ReadingSessionsRepository sessions;
  const sessionCtx = SessionContext(userId: 'u1', deviceId: 'd1');
  late String entryId;

  setUp(() async {
    // Never closed — db.close() deadlocks between fake-async and drift.
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryRepository(db, sessionCtx);
    sessions = ReadingSessionsRepository(db, sessionCtx);
    entryId = await library.add(editionId: editionId);
    await db.delete(db.syncQueue).go();
  });

  Future<List<SyncQueueData>> outbox() => db.select(db.syncQueue).get();

  test('a sitting the safety net closes is flagged auto-stopped', () async {
    final id = await sessions.logSession(
      libraryEntryId: entryId,
      startedAt: DateTime(2026, 8, 22, 20),
      endedAt: DateTime(2026, 8, 22, 21, 30),
      durationSeconds: 5400,
      autoStopped: true,
    );

    final row = await db.readingSessionsDao.getById(id);
    expect(row?.autoStopped, isTrue);

    final ops = await outbox();
    final payload = jsonDecode(ops.single.payload) as Map<String, dynamic>;
    expect(payload['auto_stopped'], isTrue);
  });

  test('an ordinary manual stop is not flagged', () async {
    final id = await sessions.logSession(
      libraryEntryId: entryId,
      startedAt: DateTime(2026, 8, 22, 20),
      endedAt: DateTime(2026, 8, 22, 20, 30),
      durationSeconds: 1800,
    );

    final row = await db.readingSessionsDao.getById(id);
    expect(row?.autoStopped, isFalse);
  });

  test('correcting the end time recomputes duration and updates the page', () async {
    final started = DateTime(2026, 8, 22, 20);
    final id = await sessions.logSession(
      libraryEntryId: entryId,
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 90)),
      durationSeconds: 5400,
      autoStopped: true,
    );
    await db.delete(db.syncQueue).go();

    // The reader actually kept reading for another 40 minutes past the
    // auto-stop, and got to page 244.
    final actualEnd = started.add(const Duration(minutes: 130));
    await sessions.correctSessionEnd(id, startedAt: started, endedAt: actualEnd, pageEnd: 244);

    final row = await db.readingSessionsDao.getById(id);
    expect(row?.endedAt, actualEnd);
    expect(row?.durationSeconds, const Duration(minutes: 130).inSeconds);
    expect(row?.pageEnd, 244);
    // The historical fact that this was an auto-stopped sitting survives the
    // correction — it isn't a review flag to clear.
    expect(row?.autoStopped, isTrue);

    final ops = await outbox();
    expect(ops, hasLength(1));
    expect(ops.single.entity, 'reading_sessions');
    expect(ops.single.opType, 'update');
    final payload = jsonDecode(ops.single.payload) as Map<String, dynamic>;
    expect(payload['duration_seconds'], const Duration(minutes: 130).inSeconds);
    expect(payload['page_end'], 244);
  });

  test('correcting without a page leaves the existing page untouched', () async {
    final started = DateTime(2026, 8, 22, 20);
    final id = await sessions.logSession(
      libraryEntryId: entryId,
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 90)),
      durationSeconds: 5400,
      pageEnd: 200,
      autoStopped: true,
    );

    await sessions.correctSessionEnd(
      id,
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 95)),
    );

    final row = await db.readingSessionsDao.getById(id);
    expect(row?.pageEnd, 200, reason: 'omitting a page must not clear the one already noted');
  });

  test('stopAndLogActiveSession propagates autoStopped through to the row', () async {
    final started = DateTime.now().subtract(const Duration(minutes: 95));
    await db.keyValuesDao.setValue(activeSessionEntryKey, entryId);
    await db.keyValuesDao.setValue(activeSessionStartedKey, started.toIso8601String());

    final logged = await stopAndLogActiveSession(db, sessionCtx, autoStopped: true);
    expect(logged, isNotNull);

    final row = await db.readingSessionsDao.getById(logged!.sessionId);
    expect(row?.autoStopped, isTrue);
  });
}
