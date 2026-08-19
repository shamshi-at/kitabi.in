import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

const _entryId = 'le-1';

class _FakeApi extends ApiClient {}

/// A Live Activity/notification tap forces a fresh `ActiveSessionController`
/// build on a cold-started process: `build()` kicks off `_hydrate()` but
/// returns immediately, and a Stop tap landing in that window used to read
/// `state == null` and silently no-op — no error, nothing for the reader to
/// retry (owner report, 19 Aug 2026, mid-flight in airplane mode).
///
/// This reproduces the race directly against the Notifier with no timers to
/// fake: a sitting is already on disk (exactly what a restored session
/// looks like) before the container is created, and `stop()` is called in
/// the same synchronous stretch as reading the notifier — before
/// `_hydrate()`'s awaited KeyValues reads can possibly have resolved.
void main() {
  test('stop() does not race a still-hydrating cold start', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');

    await db.keyValuesDao.setValue(activeSessionEntryKey, _entryId);
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // Reading the notifier runs build() synchronously, which kicks off
    // _hydrate() without awaiting it — this is the moment the race window
    // opens.
    final notifier = container.read(activeSessionProvider.notifier);

    // A Stop tap landing right here, before any of _hydrate()'s awaits have
    // resolved, must still find and log the restored sitting rather than
    // reading `state` as null and doing nothing.
    final logged = await notifier.stop();

    expect(logged, isNotNull);
    expect(logged!.libraryEntryId, _entryId);
  });

  test('start() does not race a still-hydrating cold start', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');

    await db.keyValuesDao.setValue(activeSessionEntryKey, _entryId);
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(activeSessionProvider.notifier);

    // Starting a *different* book right in the same window must stop and log
    // the restored sitting first, not silently overwrite it — a start() that
    // reads state as null here would clobber the old session's KeyValues
    // without ever logging it.
    await notifier.start('le-2');

    final logged = await db.readingSessionsDao.watchForEntry(_entryId).first;
    expect(logged, hasLength(1));
  });
}
