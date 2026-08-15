import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_engine.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// A flight, end to end: shelve a book, read it, take notes, stop the clock,
/// note the page — all with no network — and then land.
///
/// Each piece has its own test elsewhere; this one exists because the failures
/// this guards were only ever visible in the whole sequence. The queue burned
/// its retries on the *fourth or fifth* offline action, not the first. The
/// mid-sitting note was rejected only because the sitting it named didn't
/// exist yet, which is only true in this order. Nothing here should need the
/// reader to notice anything, tap a retry bar, or lose a word.
class _Api extends ApiClient {
  bool offline = true;
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/sync/push'),
        type: DioExceptionType.connectionError,
      );
    }
    pushed.addAll(ops);
    // The server applies a batch in order, and rejects a reference it can't
    // resolve — the behaviour test_sync.py pins on the API side.
    final live = <String>{};
    return [
      for (final op in ops)
        () {
          final payload = op['payload'] as Map<String, dynamic>;
          if (op['entity'] == 'reading_sessions') live.add(op['entity_id'] as String);
          final cited = payload['session_id'] as String?;
          if (cited != null && !live.contains(cited)) {
            return {'op_id': op['op_id'], 'status': 'rejected', 'code': 'invalid_reference'};
          }
          return {'op_id': op['op_id'], 'status': 'applied', 'server_seq': ops.indexOf(op) + 1};
        }(),
    ];
  }

  @override
  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: '/sync/pull'),
        type: DioExceptionType.connectionError,
      );
    }
    return {'changes': <Map<String, dynamic>>[], 'next_cursor': cursor, 'has_more': false};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const editionId = '44444444-4444-4444-4444-444444444444';
  const session = SessionContext(userId: 'u1', deviceId: 'd1');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => call.method == 'initialize' ? true : null,
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
  });

  test('a flight-mode reading session lands intact when the network comes back',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final api = _Api(); // no network for the whole trip
    final engine = SyncEngine(db, api);
    final library = LibraryRepository(db, session);
    final notes = ReadingNotesRepository(db, session);

    // Sync fires after every mutation, exactly as the app wires it — which is
    // what used to spend the retry budget before the plane had levelled off.
    Future<void> trigger() => engine.syncNow('u1');

    // — shelve it, start reading it
    final entryId = await library.add(editionId: editionId);
    await trigger();
    await library.updateStatus(entryId, 'reading');
    await trigger();

    // — start the clock (device-local, as it must be)
    final sittingId = 'a1b2c3d4-0000-4000-8000-000000000001';
    final startedAt = DateTime.now().subtract(const Duration(minutes: 47));
    await db.keyValuesDao.setValue(activeSessionEntryKey, entryId);
    await db.keyValuesDao.setValue(activeSessionIdKey, sittingId);
    await db.keyValuesDao.setValue(activeSessionStartedKey, startedAt.toIso8601String());
    await db.keyValuesDao.setValue(activeSessionPageStartKey, '61');

    // — think two things while reading
    await notes.add(
      libraryEntryId: entryId,
      sessionId: sittingId,
      body: 'The ferry chapter turns on one word.',
      pageStart: 63,
    );
    await trigger();
    await notes.add(
      libraryEntryId: entryId,
      sessionId: sittingId,
      body: 'He never names the river.',
      pageStart: 71,
    );
    await trigger();

    // — stop and log, then say where you got to
    final logged = await stopAndLogActiveSession(db, session, onMutation: trigger);
    expect(logged, isNotNull);
    await trigger();
    final sessions = ReadingSessionsRepository(db, session);
    await sessions.updateSessionPageEnd(logged!.sessionId, 92);
    await library.updateProgress(entryId, currentPage: 92);
    await trigger();

    // Nothing has reached anyone. Everything is still on the device, whole,
    // and — the part that used to fail — still *pending*, not errored.
    expect(api.pushed, isEmpty);
    final waiting = await db.syncQueueDao.pending(limit: 100, userId: 'u1');
    expect(waiting.every((o) => o.attempts == 0), isTrue,
        reason: 'a phone with no signal has not failed at anything');
    expect((await db.libraryEntriesDao.getById(entryId))!.currentPage, 92);
    expect(await db.readingNotesDao.forSession(logged.sessionId), hasLength(2));

    // — landing
    api.offline = false;
    await engine.syncNow('u1');

    expect(await db.syncQueueDao.pending(limit: 100, userId: 'u1'), isEmpty,
        reason: 'the whole trip goes up on its own, with nothing to tap');
    // Every row the reader touched is now the server's too…
    expect((await db.libraryEntriesDao.getById(entryId))!.syncStatus, 'synced');
    final sitting = await db.readingSessionsDao.getById(logged.sessionId);
    expect(sitting!.syncStatus, 'synced');
    expect(sitting.pageStart, 61);
    expect(sitting.pageEnd, 92);
    for (final note in await db.readingNotesDao.forSession(logged.sessionId)) {
      expect(note.syncStatus, 'synced', reason: 'a thought is not a second-class row');
    }
    // …and both notes ended up attached to the sitting on the wire, despite
    // being written before it existed.
    final linked = api.pushed.where(
      (op) => op['entity'] == 'reading_notes' && (op['payload'] as Map)['session_id'] != null,
    );
    expect(linked, hasLength(2));
  });
}
