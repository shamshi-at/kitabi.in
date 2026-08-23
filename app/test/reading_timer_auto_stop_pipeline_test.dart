import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

const _editionId = '55555555-5555-5555-5555-555555555555';

class _FakeApi extends ApiClient {}

/// The full production pipeline the reading-timer screen's per-second tick
/// drives — [checkReadingTimerSafetyNet] → [ActiveSessionController.stop] →
/// [stopAndLogActiveSession] → [ReadingSessionsRepository.logSession] — run
/// through the real Riverpod providers rather than calling any one link of
/// that chain directly. This is the "reduce the wait and watch it auto-stop"
/// check from the owner's report (23 Aug 2026), done by backdating the
/// sitting's start past the real 90-minute deadline instead of shortening
/// [readingCheckInDelay]/[readingCheckInGrace] themselves, which a widget
/// test can't safely do without racing every other test that reads those
/// same top-level constants.
void main() {
  testWidgets('a sitting left running past the deadline is auto-stopped and flagged',
      (tester) async {
    // Never closed: db.close() deadlocks between fake-async and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final library = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await library.add(editionId: _editionId);
      await library.updateStatus(id, 'reading');
      return id;
    });

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    await tester.runAsync(
        () => container.read(activeSessionProvider.notifier).start(entryId!));

    // The reader kept reading well past the 90-minute deadline without ever
    // answering the check-in — exactly the reported scenario, compressed to
    // an instant by backdating the start rather than waiting or shrinking
    // the real constants.
    final overdueStart = DateTime.now().subtract(
      readingCheckInDelay + readingCheckInGrace + const Duration(minutes: 5),
    );
    await tester.runAsync(() async {
      await db.keyValuesDao.setValue(activeSessionStartedKey, overdueStart.toIso8601String());
      // checkReadingTimerSafetyNet reads the in-memory ActiveSession, not the
      // database directly — re-hydrate it so the backdated start actually
      // takes effect, the same as a foreground resume would.
      await container.read(activeSessionProvider.notifier).hydrate();
    });

    // A minimal harness that hands us a genuine WidgetRef — the same type
    // the real timer screen's per-second tick calls checkReadingTimerSafetyNet
    // with — rather than a ProviderContainer standing in for one.
    late WidgetRef capturedRef;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return const SizedBox();
        }),
      ),
    ));
    await tester.pump();

    final logged = await tester.runAsync(() => checkReadingTimerSafetyNet(capturedRef));

    expect(logged, isNotNull, reason: 'the overdue sitting must be closed, not left running');
    expect(container.read(activeSessionProvider), isNull,
        reason: 'the in-app state must catch up with the auto-stop');

    final row = await tester.runAsync(() => db.readingSessionsDao.getById(logged!.sessionId));
    expect(row?.autoStopped, isTrue,
        reason: 'a sitting the safety net closes must be flagged for the reading log');
  });
}
