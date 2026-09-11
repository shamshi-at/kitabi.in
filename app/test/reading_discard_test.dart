import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/notifications/reading_live_activity.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/note_session_links.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// Discarding a sitting: the reader started the clock and then didn't read
/// (owner request, 12 Sep 2026). The whole feature is one distinction —
/// *nothing is logged* — held against a teardown that must otherwise be
/// identical to a stop's, because every surface a running sitting owns is
/// still up and still has to come down.
const _pluginChannel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cancelled = <int>[];

  setUp(() {
    cancelled.clear();
    // The live surface is only a *notification* on Android, and the plugin
    // picks its implementation from `defaultTargetPlatform` and from whichever
    // platform class registered itself — on a macOS test host neither is
    // Android and every call silently no-ops (same setup as
    // reading_stop_teardown_test).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
      if (call.method == 'cancel') {
        cancelled.add((call.arguments as Map)['id'] as int);
        return null;
      }
      return call.method == 'initialize' ||
              call.method == 'requestNotificationsPermission' ||
              call.method == 'requestPermissions'
          ? true
          : null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
  });

  const session = SessionContext(userId: 'u1', deviceId: 'd1');

  Future<AppDatabase> dbWithRunningSitting({String sessionId = 's-1'}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.keyValuesDao.setValue(activeSessionEntryKey, 'entry-1');
    await db.keyValuesDao.setValue(activeSessionIdKey, sessionId);
    await db.keyValuesDao.setValue(activeSessionPageStartKey, '42');
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.now().subtract(const Duration(minutes: 25)).toIso8601String(),
    );
    return db;
  }

  test('a discarded sitting writes no row and leaves no sitting running', () async {
    final db = await dbWithRunningSitting();

    expect(await discardActiveSession(db), isTrue);

    expect(
      await db.readingSessionsDao.watchForEntry('entry-1').first,
      isEmpty,
      reason: 'the one thing a discard must never do is file the sitting',
    );
    // Nothing queued either — a row that was never written has nothing to push,
    // and a soft-delete op for it would name an id the server has never seen.
    expect(await db.syncQueueDao.pending(limit: 50), isEmpty);
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), isNull);
    expect(await db.keyValuesDao.getValue(activeSessionStartedKey), isNull);
    expect(await db.keyValuesDao.getValue(activeSessionPageStartKey), isNull);
  });

  test('discarding takes down every surface the sitting owned', () async {
    final db = await dbWithRunningSitting();

    await discardActiveSession(db);

    expect(cancelled, contains(ReadingLiveActivity.notificationId),
        reason: 'the lock-screen clock must not outlive the sitting');
    expect(cancelled, contains(readingCheckInNotificationId('entry-1')),
        reason: 'a discarded sitting must never ask "still reading?"');
  });

  test('discarding leaves a note to take the sitting off the account', () async {
    // The account only ever knew one thing about this sitting — that a timer
    // was running — and that still has to be retracted. It is the same note a
    // stop leaves, and the same retry (`publishStop`) clears it.
    final db = await dbWithRunningSitting(sessionId: 's-42');
    await db.keyValuesDao.setValue(activeSessionMirroredKey, 's-42');

    await discardActiveSession(db);

    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), 's-42');
    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), isNull);
  });

  test('notes written during a discarded sitting survive it, cut loose', () async {
    final db = await dbWithRunningSitting(sessionId: 's-7');
    final notes = ReadingNotesRepository(db, session);
    final noteId = await notes.add(
      libraryEntryId: 'entry-1',
      body: 'the opening is slower than I remembered',
      sessionId: 's-7',
    );
    // Written mid-sitting, so the link is waiting for a row that — after the
    // discard — is never coming.
    expect(await db.keyValuesDao.getValue(pendingNoteLinksKey), isNotNull);

    await discardActiveSession(db);

    final note = await db.readingNotesDao.getById(noteId);
    expect(note, isNotNull, reason: 'a thought written down is not the timing');
    expect(note!.body, 'the opening is slower than I remembered');
    expect(note.sessionId, isNull,
        reason: 'pointing at a sitting that will never be a row hides the note '
            'from the book and from the log at the same time');
    expect(await db.keyValuesDao.getValue(pendingNoteLinksKey), isNull,
        reason: 'the link would otherwise be re-checked on every drain forever');
  });

  test('only this sitting\'s links are forgotten', () async {
    // A link belonging to some other sitting — one logged on another device
    // and still on its way here — must survive a discard that has nothing to
    // do with it.
    final db = await dbWithRunningSitting(sessionId: 's-7');
    await db.keyValuesDao.setValue(
      pendingNoteLinksKey,
      jsonEncode({'note-a': 's-7', 'note-b': 's-other'}),
    );

    await discardActiveSession(db);

    final remaining = jsonDecode(
      (await db.keyValuesDao.getValue(pendingNoteLinksKey))!,
    ) as Map;
    expect(remaining, {'note-b': 's-other'});
  });

  test('a discard with nothing running still clears the clock', () async {
    // The mirror of the stop path's own early exit: a second tap, or a sitting
    // a background isolate already ended, must not leave a surface up with
    // nothing behind it (29 Aug 2026).
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    expect(await discardActiveSession(db), isFalse);
    expect(cancelled, contains(ReadingLiveActivity.notificationId));
    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), isNull,
        reason: 'nothing was ended here, so nothing may be retracted from the '
            'account — that row may belong to another device');
  });
}
