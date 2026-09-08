import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/features/share/presentation/period_share_card.dart';
import 'package:kitabi/l10n/app_localizations.dart';

import 'support/pump_until.dart';

const _editionId = '55555555-5555-5555-5555-555555555555';

/// The daily card's new door (8 Sep 2026).
///
/// The Today card itself has existed since 26 Aug and was never the problem —
/// it had one door, in Insights, three taps from the moment a reader actually
/// finishes reading. So this is asserted through the *real* wax-seal face
/// rather than by calling `shareTodaysReading` directly: what was missing was
/// the door, and a test that skips the screen would pass with no door on it
/// (the 6 Sep lesson — prove the door before touching the rule behind it).
void main() {
  late final void Function(FlutterErrorDetails, String) reportOriginal;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
  });
  tearDownAll(() => reportTestException = reportOriginal);

  testWidgets('the wax-seal face offers today\'s card, and it opens', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId,
        workId: 'w',
        title: 'Khasakkinte Itihasam',
        authorNames: 'O.V. Vijayan',
        pageCount: const Value(240),
      ));
      return id;
    });

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(ApiClient()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/stub',
      routes: [
        GoRoute(
          path: '/stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/reading-timer/$entryId'),
              child: const Text('open the timer'),
            ),
          ),
        ),
        GoRoute(
          path: '/reading-timer/:id',
          builder: (context, state) =>
              ReadingTimerScreen(libraryEntryId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.runAsync(
      () => container.read(activeSessionProvider.notifier).start(entryId!, pageStart: 40),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await pumpUntilFound(tester, find.text('open the timer'));
    await tester.tap(find.text('open the timer'));
    await pumpUntilFound(tester, find.text('Stop & log'), reason: 'the timer to open');
    await tester.tap(find.text('Stop & log'));

    // The door is on the face the reader is standing on.
    final door = find.text("Share today's reading");
    await pumpUntilFound(tester, door, reason: "today's share door on the wax-seal face");

    await tester.tap(door);
    await pumpUntilFound(tester, find.byType(PeriodShareCard), reason: 'the share sheet');

    // ...and it opens the day's card, not an empty sheet. The sitting was
    // logged a moment ago, so the day is never "nothing to send" here.
    expect(find.text("Today's reading"), findsOneWidget);
    expect(find.byType(PeriodShareCard), findsOneWidget);
  });
}
