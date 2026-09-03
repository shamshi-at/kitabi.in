import 'dart:async';

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

  /// Lets a test hold the GET open and do something on the device while the
  /// request is in flight — the window every "stale answer" bug lives in.
  Completer<void>? holdGet;

  @override
  Future<Map<String, dynamic>?> getActiveSession() async {
    gets++;
    final hold = holdGet;
    if (hold != null) await hold.future;
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
      // Logging a sitting needs an identity to file it under. Without these the
      // read throws and the whole write is swallowed by a best-effort catch —
      // the tests below would pass over a rule that never ran.
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
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

  /// The reader started reading while this pull's GET was in the air.
  ///
  /// `pendingStopId` was already snapshotted before the request (29 Aug 2026);
  /// `localId` was not, so it was read *after* — and judged against an answer
  /// that predated the sitting it named. With `publishStart` landing in the
  /// same window, `mirrored == localId` held and the empty answer read as
  /// "stopped on the other device": the timer the reader had just started was
  /// cleared, unlogged, and every surface that renders the clock fell to a
  /// frozen 0:00 (owner report, 3 Sep 2026).
  test('a sitting started while the GET was in flight is not cleared by it', () async {
    api.active = null; // true when the request was issued, stale when it lands
    api.holdGet = Completer<void>();

    final pull = sync().pullAndApply();
    await Future<void>.delayed(Duration.zero);

    // The reader taps Start. Both halves of the hazard: the sitting is written
    // locally *and* published, so the account now has a row this answer
    // predates.
    await writeLocal(id: 's-fresh', mirroredId: 's-fresh');
    api.holdGet!.complete();

    expect(await pull, isFalse, reason: 'nothing was decided — the answer aged out');
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-fresh');
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), 'entry-1');
  });

  /// The same window, the other way round: the answer holds the sitting the
  /// reader has just stopped. The older-start rule would then log their
  /// seconds-old new sitting and adopt the dead row over it.
  test('a sitting started while the GET was in flight is not replaced by a dead one',
      () async {
    api.active = {
      'session_id': 's-old',
      'library_entry_id': 'entry-1',
      'started_at': DateTime.utc(2026, 8, 14, 9).toIso8601String(),
      'page_start': null,
      'confirmed_at': null,
      'device_id': 'this-phone',
    };
    api.holdGet = Completer<void>();

    final pull = sync().pullAndApply();
    await Future<void>.delayed(Duration.zero);

    await writeLocal(id: 's-fresh');
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.utc(2026, 8, 14, 11).toIso8601String(),
    );
    api.holdGet!.complete();

    expect(await pull, isFalse);
    expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-fresh');
    expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty,
        reason: 'a sitting seconds old is not a sitting to file away');
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

  /// Two sittings, one account — the reader started on one phone while the
  /// other was offline. **The older start wins** (owner decision, 15 Aug 2026):
  /// a pure comparison, so both devices reach the same answer with nothing to
  /// negotiate. The loser is real reading, so it is logged rather than dropped.
  group('two sittings collide', () {
    Map<String, dynamic> remoteStartedAt(DateTime when, {String id = 's-remote'}) => {
          'session_id': id,
          'library_entry_id': 'entry-1',
          'started_at': when.toIso8601String(),
          'page_start': null,
          'confirmed_at': null,
          'device_id': 'other-phone',
        };

    test('a younger local sitting yields — and is logged, not lost', () async {
      await writeLocal(id: 's-mine'); // started 14 Aug 10:00
      api.active = remoteStartedAt(DateTime.utc(2026, 8, 14, 9)); // an hour older

      expect(await sync().pullAndApply(), isTrue);

      expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-remote');
      final logged = await db.readingSessionsDao.allSince(DateTime.utc(2020));
      expect(logged, hasLength(1), reason: 'losing a race is not a reason to lose the time');
      expect(logged.single.id, 's-mine');
    });

    test('an older local sitting stands, and is put back on the account', () async {
      await writeLocal(id: 's-mine'); // started 14 Aug 10:00
      api.active = remoteStartedAt(DateTime.utc(2026, 8, 14, 11)); // an hour younger

      expect(await sync().pullAndApply(), isFalse, reason: 'ours is the sitting');

      expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-mine');
      expect(api.lastPut?['session_id'], 's-mine',
          reason: 'the other device finds it on its next pull and falls in behind');
      expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty,
          reason: 'nothing ended — it is still running');
    });

    test('a stale mirror is handed over without being logged here', () async {
      // This sitting belongs to the other device; it will log it itself. A row
      // written here too is the duplicate the shared-id design exists to avoid.
      await writeLocal(id: 's-theirs', mirroredId: 's-theirs');
      await db.keyValuesDao.setValue(activeSessionAdoptedKey, 's-theirs');
      api.active = remoteStartedAt(DateTime.utc(2026, 8, 14, 12), id: 's-newer');

      expect(await sync().pullAndApply(), isTrue);

      expect(await db.keyValuesDao.getValue(activeSessionIdKey), 's-newer');
      expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty);
    });

    test('a published sitting is still ours to log when it loses', () async {
      // A successful publish marks the sitting as known to the account, which
      // is *not* the same as belonging to another device — reading the two off
      // one key would have dropped this one unlogged.
      await writeLocal(id: 's-mine', mirroredId: 's-mine');
      api.active = remoteStartedAt(DateTime.utc(2026, 8, 14, 9));

      expect(await sync().pullAndApply(), isTrue);

      final logged = await db.readingSessionsDao.allSince(DateTime.utc(2020));
      expect(logged.map((s) => s.id), ['s-mine']);
    });
  });

  /// The rule's real claim is not "the older one wins on device A" — it is that
  /// two devices land on the same sitting, from either side, without talking to
  /// each other. A rule that merely *prefers* the older one could still have
  /// both devices swap endlessly. So run both pulls and check where they stop.
  group('two devices converge', () {
    late _Server server;
    late AppDatabase dbA, dbB;
    late ProviderContainer a, b;

    ProviderContainer deviceOn(AppDatabase db, String deviceId) {
      final c = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(_DeviceApi(server)),
        sessionContextProvider.overrideWith(
          (ref) async => SessionContext(userId: 'u1', deviceId: deviceId),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    /// A sitting running on [db], started here and never published.
    Future<void> runningOn(AppDatabase db, String id, DateTime startedAt) async {
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(id: 'entry-1', userId: 'u1', editionId: 'e1'),
      );
      await db.keyValuesDao.setValue(activeSessionEntryKey, 'entry-1');
      await db.keyValuesDao.setValue(activeSessionIdKey, id);
      await db.keyValuesDao.setValue(activeSessionStartedKey, startedAt.toIso8601String());
    }

    setUp(() {
      server = _Server();
      dbA = AppDatabase.forTesting(NativeDatabase.memory());
      dbB = AppDatabase.forTesting(NativeDatabase.memory());
      a = deviceOn(dbA, 'device-a');
      b = deviceOn(dbB, 'device-b');
    });

    Future<String?> sittingOn(AppDatabase db) =>
        db.keyValuesDao.getValue(activeSessionIdKey);

    test('the younger device yields, whichever device notices first', () async {
      await runningOn(dbA, 's-a', DateTime.utc(2026, 8, 15, 10)); // older
      await runningOn(dbB, 's-b', DateTime.utc(2026, 8, 15, 10, 30));
      await a.read(activeSessionSyncProvider).publishStart(
            (await readLocalActiveSession(dbA))!,
          );

      // B comes back online and notices.
      await b.read(activeSessionSyncProvider).pullAndApply();
      await a.read(activeSessionSyncProvider).pullAndApply();

      expect(await sittingOn(dbA), 's-a');
      expect(await sittingOn(dbB), 's-a', reason: 'both devices on the older sitting');
      expect(server.active!['session_id'], 's-a');
      // B's own reading is not thrown away…
      expect((await dbB.readingSessionsDao.allSince(DateTime.utc(2020))).map((s) => s.id),
          ['s-b']);
      // …and A, which won, logged nothing: it is still reading.
      expect(await dbA.readingSessionsDao.allSince(DateTime.utc(2020)), isEmpty);
    });

    test('an older sitting reclaims the account from a younger one', () async {
      // The mirror image: the device that was offline holds the *older* one.
      await runningOn(dbA, 's-a', DateTime.utc(2026, 8, 15, 11)); // younger
      await runningOn(dbB, 's-b', DateTime.utc(2026, 8, 15, 9)); // older, offline
      await a.read(activeSessionSyncProvider).publishStart(
            (await readLocalActiveSession(dbA))!,
          );

      await b.read(activeSessionSyncProvider).pullAndApply(); // B pushes back
      await a.read(activeSessionSyncProvider).pullAndApply(); // A stands down

      expect(await sittingOn(dbB), 's-b');
      expect(await sittingOn(dbA), 's-b', reason: 'the older sitting took the account');
      expect(server.active!['session_id'], 's-b');
      expect((await dbA.readingSessionsDao.allSince(DateTime.utc(2020))).map((s) => s.id),
          ['s-a']);
    });

    test('and it settles — further pulls change nothing', () async {
      await runningOn(dbA, 's-a', DateTime.utc(2026, 8, 15, 10));
      await runningOn(dbB, 's-b', DateTime.utc(2026, 8, 15, 10, 30));
      await a.read(activeSessionSyncProvider).publishStart(
            (await readLocalActiveSession(dbA))!,
          );

      // Five rounds of both devices pulling. A rule that only *prefers* the
      // older sitting could still have the two trade it back and forth.
      for (var i = 0; i < 5; i++) {
        await b.read(activeSessionSyncProvider).pullAndApply();
        await a.read(activeSessionSyncProvider).pullAndApply();
      }

      expect(await sittingOn(dbA), 's-a');
      expect(await sittingOn(dbB), 's-a');
      expect((await dbB.readingSessionsDao.allSince(DateTime.utc(2020))).length, 1,
          reason: 'the loser is logged once, not once per pull');
    });
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

/// One `active_reading_sessions` row, shared by two devices — the thing the
/// real server is. [_DeviceApi] instances read and write *this*, so a pull on
/// one device sees what the other actually published.
class _Server {
  Map<String, dynamic>? active;
}

class _DeviceApi extends ApiClient {
  _DeviceApi(this.server);

  final _Server server;

  @override
  Future<Map<String, dynamic>?> getActiveSession() async => server.active;

  @override
  Future<void> putActiveSession(Map<String, dynamic> payload) async {
    server.active = Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> deleteActiveSession({String? deviceId}) async => server.active = null;
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
