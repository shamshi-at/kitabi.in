import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

class _FakeApi extends ApiClient {
  @override
  Future<void> putActiveSession(Map<String, dynamic> payload) async {}
}

/// "Sometimes when I start the timer, the clock is not moving" (owner report,
/// 3 Sep 2026).
///
/// The clock every surface draws comes from `activeSessionProvider`, and
/// `start()` used to publish that state only *after* five sequential
/// `key_values` writes. Drift serializes queries behind an open
/// `db.transaction`, and the sync engine's pull applies every page inside one
/// — so a start that happened to land during a sync pass sat with `state ==
/// null` for the whole pull: the mini-bar absent, Home's live card absent, and
/// the timer screen rendering `Duration.zero` under a sweeping hand.
///
/// The transaction here is that pull, reduced to the one property that
/// matters: it holds the database and it takes a while.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('the clock starts before the sitting reaches the database', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.hydrated; // a warm app: storage has already answered

    // A sync pull, holding the database the way drift makes it hold it.
    final pull = db.transaction(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final start = notifier.start('entry-1', pageStart: 12);

    // Still inside the pull: not one of start()'s writes can have landed — a
    // read issued now is queued behind the transaction just as they are, so
    // its silence is the proof.
    String? stored;
    var storedRead = false;
    unawaited(db.keyValuesDao.getValue(activeSessionEntryKey).then((v) {
      stored = v;
      storedRead = true;
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(storedRead, isFalse,
        reason: 'the fixture is only meaningful while the writes are blocked');
    expect(stored, isNull);

    // …and yet the reader's clock is already running.
    final active = container.read(activeSessionProvider);
    expect(active, isNotNull, reason: 'the clock starts when the reader says it does');
    expect(active!.libraryEntryId, 'entry-1');
    expect(active.pageStart, 12);

    await Future.wait<void>([pull, start]);
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), 'entry-1');
  });

  test('a stop tapped inside a start\'s write window still stops, cleanly', () async {
    // Publishing `state` first makes that tap do what it says — it used to be
    // a silent no-op, because `state` was still null until the writes landed.
    // Which then puts a stop's seven deletes in among the five writes still
    // arriving behind it, unless the two take turns.
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.hydrated;

    final pull = db.transaction(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final start = notifier.start('entry-1', pageStart: 3);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(activeSessionProvider), isNotNull);

    final stop = notifier.stop();
    await Future.wait<void>([pull, start, stop]);

    expect(await stop, isNotNull, reason: 'a Stop tap is not a no-op');
    expect(container.read(activeSessionProvider), isNull);
    // Nothing of the sitting may be left behind for a later pull to find.
    for (final key in [
      activeSessionEntryKey,
      activeSessionStartedKey,
      activeSessionIdKey,
      activeSessionPageStartKey,
      activeSessionAdoptedKey,
      activeSessionMirroredKey,
    ]) {
      expect(await db.keyValuesDao.getValue(key), isNull, reason: key);
    }
    expect(await db.readingSessionsDao.allSince(DateTime.utc(2020)), hasLength(1));
  });

  test('the safety net stands down while a start settles', () async {
    // The window above is exactly the divergence `checkReadingTimerSafetyNet`
    // reads as "someone else stopped this sitting" — its answer is to null the
    // state and pop the timer screen, which here would be nulling the sitting
    // the reader just started. `isSettling` is the flag it consults; the stop
    // direction has had one since 16 Jul 2026, the start direction had none.
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.hydrated;
    expect(notifier.isSettling, isFalse);

    final pull = db.transaction(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final start = notifier.start('entry-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifier.isSettling, isTrue,
        reason: 'state names an entry key_values does not — that is not a stop');

    await Future.wait<void>([pull, start]);
    expect(notifier.isSettling, isFalse);
  });
}
