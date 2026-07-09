import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

const _editionIdA = '44444444-4444-4444-4444-444444444444';
const _editionIdB = '55555555-5555-5555-5555-555555555555';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('start sets active state; stop logs a session and clears it', () async {
    final container = buildContainer();
    final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
    final entryId = await repo.add(editionId: _editionIdA);

    await container.read(activeSessionProvider.notifier).start(entryId, pageStart: 100);
    expect(container.read(activeSessionProvider)?.libraryEntryId, entryId);
    expect(container.read(activeSessionProvider)?.pageStart, 100);

    final logged = await container.read(activeSessionProvider.notifier).stop();
    expect(logged?.libraryEntryId, entryId);
    expect(logged!.durationSeconds, greaterThanOrEqualTo(0));
    expect(container.read(activeSessionProvider), isNull);

    final sessions = await db.readingSessionsDao.watchForEntry(entryId).first;
    expect(sessions, hasLength(1));
    expect(sessions.first.id, logged.sessionId);
    expect(sessions.first.pageStart, 100);
    expect(sessions.first.durationSeconds, logged.durationSeconds);

    // The wax-seal screen's optional page-number edit, a moment later.
    final sessionsRepo = ReadingSessionsRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
    await sessionsRepo.updateSessionPageEnd(logged.sessionId, 142);
    final updated = await db.readingSessionsDao.watchForEntry(entryId).first;
    expect(updated.first.pageEnd, 142);
  });

  test('stop with nothing running returns null', () async {
    final container = buildContainer();
    final logged = await container.read(activeSessionProvider.notifier).stop();
    expect(logged, isNull);
  });

  test('starting the same entry twice is a no-op', () async {
    final container = buildContainer();
    final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
    final entryId = await repo.add(editionId: _editionIdA);

    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.start(entryId);
    final firstStart = container.read(activeSessionProvider)!.startedAt;
    await notifier.start(entryId);
    expect(container.read(activeSessionProvider)!.startedAt, firstStart);

    final sessions = await db.readingSessionsDao.watchForEntry(entryId).first;
    expect(sessions, isEmpty); // never auto-stopped, since it's the same book
  });

  test('starting a different book auto-stops and logs the first', () async {
    final container = buildContainer();
    final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
    final entryA = await repo.add(editionId: _editionIdA);
    final entryB = await repo.add(editionId: _editionIdB);

    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.start(entryA);
    await notifier.start(entryB);

    expect(container.read(activeSessionProvider)?.libraryEntryId, entryB);
    final sessionsA = await db.readingSessionsDao.watchForEntry(entryA).first;
    expect(sessionsA, hasLength(1));
    final sessionsB = await db.readingSessionsDao.watchForEntry(entryB).first;
    expect(sessionsB, isEmpty); // B is still running, not logged yet
  });

  test('an active session survives a fresh controller (restart hydration)', () async {
    final container1 = buildContainer();
    final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
    final entryId = await repo.add(editionId: _editionIdA);
    await container1.read(activeSessionProvider.notifier).start(entryId);
    container1.dispose();

    // A fresh container reading the same (never-disposed) db simulates a
    // cold app restart mid-session — the notifier's build() hydrates from
    // KeyValues rather than starting empty.
    final container2 = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container2.dispose);
    // Force build() to run, then let the async hydration inside it resolve.
    container2.read(activeSessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container2.read(activeSessionProvider)?.libraryEntryId, entryId);
  });
}
