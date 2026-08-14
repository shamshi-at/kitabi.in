import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
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
