import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/active_session_sync.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// One account, two devices, one running timer (owner request, 14 Aug 2026).
///
/// The dangerous direction is *clearing*: a pull that misreads "the server has
/// nothing" can throw away a sitting the reader is in the middle of. So the
/// interesting cases here are not the happy adopt — they are the two ways a
/// device must refuse to let go.
class _FakeApi extends ApiClient {
  Map<String, dynamic>? active;
  int gets = 0;
  int deletes = 0;
  Map<String, dynamic>? lastPut;

  @override
  Future<Map<String, dynamic>?> getActiveSession() async {
    gets++;
    return active;
  }

  @override
  Future<void> putActiveSession(Map<String, dynamic> payload) async {
    lastPut = payload;
  }

  @override
  Future<void> deleteActiveSession({String? deviceId}) async {
    deletes++;
    active = null;
  }
}

void main() {
  late AppDatabase db;
  late _FakeApi api;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _FakeApi();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ]);
  });

  tearDown(() => container.dispose());

  ActiveSessionSync sync() => container.read(activeSessionSyncProvider);

  Future<void> writeLocal({required String id, String? mirroredId}) async {
    // The shelf row the sitting hangs off. publishStart refuses to announce a
    // sitting whose entry is gone, so a fixture without one silently tests
    // nothing.
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(id: 'entry-1', userId: 'u1', editionId: 'e1'),
    );
    await db.keyValuesDao.setValue(activeSessionEntryKey, 'entry-1');
    await db.keyValuesDao.setValue(activeSessionIdKey, id);
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.utc(2026, 8, 14, 10).toIso8601String(),
    );
    if (mirroredId != null) {
      await db.keyValuesDao.setValue(activeSessionMirroredKey, mirroredId);
    }
  }

  test('a sitting started on the other device is adopted, page and all', () async {
    api.active = {
      'session_id': 's-remote',
      'library_entry_id': 'entry-9',
      'started_at': DateTime.utc(2026, 8, 14, 9, 30).toIso8601String(),
      'page_start': 88,
      'confirmed_at': null,
      'device_id': 'other-phone',
    };

    expect(await sync().pullAndApply(), isTrue);

    // Mirrored into the *same* keys the timer already reads, which is what
    // makes every surface on this device work with no new code path.
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), 'entry-9');
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-remote');
    expect(await db.keyValuesDao.getValue(activeSessionPageStartKey), '88');
    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), 's-remote');
  });

  test('a sitting stopped on the other device is dropped here, not logged again',
      () async {
    await writeLocal(id: 's-remote', mirroredId: 's-remote');
    api.active = null;

    expect(await sync().pullAndApply(), isTrue);

    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), isNull);
    // The other device wrote the finished row; writing one here too is the
    // duplicate this whole design exists to avoid.
    expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty);
  });

  /// The guard above, in the direction it was missing.
  ///
  /// The "never clear what we started" rule was keyed only on *adopting* a
  /// sitting, so the device that started one never recorded that the account
  /// knew about it. When the other device stopped it, the empty server read as
  /// "not published yet" and this device kept counting — clock running,
  /// lock-screen notification up, over a sitting already logged and already
  /// pulled back onto this very device (found with two emulators, 15 Aug 2026).
  test('a sitting started here and published IS cleared when the other device stops it',
      () async {
    await writeLocal(id: 's-mine');
    // publishStart succeeded, so the account has heard of this sitting.
    await db.keyValuesDao.setValue(activeSessionMirroredKey, 's-mine');
    api.active = null; // …and now the other device has stopped it

    expect(await sync().pullAndApply(), isTrue);
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
    // The other device wrote the row; writing a second one here is the
    // duplicate this whole design exists to avoid.
    expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty);
  });

  test('publishing a start is what records that the account knows', () async {
    final entryId = await LibraryRepository(
      db,
      const SessionContext(userId: 'u1', deviceId: 'd1'),
    ).add(editionId: '44444444-4444-4444-4444-444444444444');

    await sync().publishStart(ActiveSession(
      libraryEntryId: entryId,
      startedAt: DateTime.utc(2026, 8, 15, 20),
      id: 's-mine',
    ));

    expect(api.lastPut?['session_id'], 's-mine');
    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), 's-mine',
        reason: 'only a *successful* publish may record it');
  });

  test('a start that never reached the server records nothing', () async {
    final entryId = await LibraryRepository(
      db,
      const SessionContext(userId: 'u1', deviceId: 'd1'),
    ).add(editionId: '44444444-4444-4444-4444-444444444444');
    final offlineContainer = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_PutFailsApi()),
    ]);
    addTearDown(offlineContainer.dispose);

    await offlineContainer.read(activeSessionSyncProvider).publishStart(ActiveSession(
          libraryEntryId: entryId,
          startedAt: DateTime.utc(2026, 8, 15, 20),
          id: 's-offline',
        ));

    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), isNull,
        reason: 'an unpublished sitting is the one a pull must never throw away');
  });

  test('a sitting this device started is never cleared by an empty server',
      () async {
    // Started here while offline, so it was never published. An empty server
    // means "not published yet", not "stopped elsewhere" — and getting this
    // wrong deletes a running timer out from under the reader.
    await writeLocal(id: 's-local');
    api.active = null;

    expect(await sync().pullAndApply(), isFalse);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-local');
  });

  test('an unreachable server changes nothing', () async {
    await writeLocal(id: 's-local', mirroredId: 's-local');
    api.active = null;
    final offline = _OfflineApi();
    final offlineContainer = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(offline),
    ]);
    addTearDown(offlineContainer.dispose);

    expect(await offlineContainer.read(activeSessionSyncProvider).pullAndApply(), isFalse);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-local');
  });

  /// The resurrection: a sitting stopped here while offline is still on the
  /// account, and the pull that finds it there must not hand it back.
  ///
  /// This is what a stop in airplane mode looks like from the server's side —
  /// the DELETE never went out, so the row it would have removed is exactly
  /// the row this pull reads. Adopting it restarted the clock from the
  /// original start time, put the lock-screen notification back up over a
  /// sitting the reader had finished, and made the next stop write a second
  /// row for one sitting.
  test('a sitting stopped here but never published is retracted, not re-adopted',
      () async {
    await db.keyValuesDao.setValue(activeSessionPendingStopKey, 's-mine');
    api.active = {
      'session_id': 's-mine',
      'library_entry_id': 'entry-1',
      'started_at': DateTime.utc(2026, 8, 14, 10).toIso8601String(),
      'page_start': null,
      'confirmed_at': null,
      'device_id': 'this-phone',
    };

    expect(await sync().pullAndApply(), isFalse, reason: 'nothing to adopt — it is over');
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
    expect(api.deletes, 1, reason: 'the delay only delayed it');
    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), isNull,
        reason: 'published — the note has done its job');
  });

  test('the note is dropped once the account has moved on', () async {
    // The other device started a *new* sitting after ours ended. Our stop has
    // nothing left to retract, and a note kept past its subject would block
    // that new sitting from ever being adopted.
    await db.keyValuesDao.setValue(activeSessionPendingStopKey, 's-mine');
    api.active = {
      'session_id': 's-newer',
      'library_entry_id': 'entry-9',
      'started_at': DateTime.utc(2026, 8, 14, 11).toIso8601String(),
      'page_start': null,
      'confirmed_at': null,
      'device_id': 'other-phone',
    };

    expect(await sync().pullAndApply(), isTrue);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-newer');
    expect(api.deletes, 0, reason: 'never delete a sitting that is genuinely running');
    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), isNull);
  });

  test('an offline retraction keeps its note for next time', () async {
    await db.keyValuesDao.setValue(activeSessionPendingStopKey, 's-mine');
    final flaky = _DeleteFailsApi()
      ..active = {
        'session_id': 's-mine',
        'library_entry_id': 'entry-1',
        'started_at': DateTime.utc(2026, 8, 14, 10).toIso8601String(),
        'page_start': null,
        'confirmed_at': null,
        'device_id': 'this-phone',
      };
    final offlineContainer = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(flaky),
    ]);
    addTearDown(offlineContainer.dispose);

    expect(await offlineContainer.read(activeSessionSyncProvider).pullAndApply(), isFalse);
    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), 's-mine',
        reason: 'still unpublished — the retry has to survive');
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
  });

  /// Started offline, then the signal came back.
  ///
  /// Publishing happens once, at `start`, and with no network it fails
  /// silently — by design, because a timer that refused to start because
  /// another phone was unreachable would be the worse bug. But nothing ever
  /// tried again, so the sitting stayed device-local for good. The reader saw
  /// the book turn to "reading" on their other device (that rides the sync
  /// queue, which does retry) with no timer beside it (owner report,
  /// 15 Aug 2026).
  ///
  /// An empty server plus an unpublished local sitting is not a stalemate: it
  /// is the one moment we know the account is reachable *and* has nothing
  /// running, which is exactly when to say what we are doing.
  test('a sitting started offline is published once the account is reachable',
      () async {
    await writeLocal(id: 's-local'); // no mirrored id — never published
    api.active = null;

    expect(await sync().pullAndApply(), isFalse, reason: 'nothing to adopt — it is ours');

    expect(api.lastPut, isNotNull, reason: 'the other device has to be told eventually');
    expect(api.lastPut!['session_id'], 's-local');
    expect(api.lastPut!['library_entry_id'], 'entry-1');
    // And it is now on the account, so a later empty server means the other
    // device stopped it rather than "we never published".
    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), 's-local');
    // The reader's own running timer is untouched throughout.
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-local');
  });

  test('a still-unreachable account leaves the sitting unpublished, to try again',
      () async {
    await writeLocal(id: 's-local');
    final offline = _PutFailsApi();
    final offlineContainer = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(offline),
    ]);
    addTearDown(offlineContainer.dispose);

    expect(await offlineContainer.read(activeSessionSyncProvider).pullAndApply(), isFalse);

    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), isNull,
        reason: 'unpublished is the state that makes the next pull try again');
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-local',
        reason: 'and it must never cost the reader their running timer');
  });

  test('the confirmation travels with a late publish', () async {
    // "Yes, still reading" moves the deadline. Publishing without it would have
    // the other device compute a deadline 90 minutes from the original start
    // and stop a sitting the reader had just confirmed.
    await writeLocal(id: 's-local');
    await db.keyValuesDao.setValue(
      activeSessionConfirmedKey,
      DateTime.utc(2026, 8, 14, 11).toIso8601String(),
    );
    api.active = null;

    await sync().pullAndApply();

    expect(api.lastPut!['confirmed_at'], startsWith('2026-08-14T11:00:00'));
  });

  test('the same sitting twice is not re-applied', () async {
    await writeLocal(id: 's-remote', mirroredId: 's-remote');
    api.active = {
      'session_id': 's-remote',
      'library_entry_id': 'entry-1',
      'started_at': DateTime.utc(2026, 8, 14, 10).toIso8601String(),
      'page_start': null,
      'confirmed_at': null,
      'device_id': 'other-phone',
    };

    expect(await sync().pullAndApply(), isFalse, reason: 'already in step');
  });
}

class _OfflineApi extends ApiClient {
  @override
  Future<Map<String, dynamic>?> getActiveSession() async => throw Exception('offline');
}

/// Reachable enough to answer a read, not enough to accept a write — the shape
/// of a stop published from a train.
class _DeleteFailsApi extends _FakeApi {
  @override
  Future<void> deleteActiveSession({String? deviceId}) async => throw Exception('offline');
}

/// The same, for the start half.
class _PutFailsApi extends _FakeApi {
  @override
  Future<void> putActiveSession(Map<String, dynamic> payload) async =>
      throw Exception('offline');
}
