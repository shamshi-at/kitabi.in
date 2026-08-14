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
import 'package:kitabi/features/library/presentation/session_page_entry.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _editionId = '44444444-4444-4444-4444-444444444444';

/// The API as it behaves on a real phone: taking the sitting off the account
/// is a network round trip, not an instant local write.
class _SlowApi extends ApiClient {
  @override
  Future<void> deleteActiveSession({String? deviceId}) =>
      Future<void>.delayed(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Stop & log on the timer screen must land on the wax-seal face, which is
  /// where the page question lives.
  ///
  /// The regression it guards (owner report, 14 Aug 2026): stopping now
  /// publishes the stop to the reader's other devices, so `stop()` clears the
  /// session and *then* waits on the network. Frames render in that window —
  /// the screen animates a sweeping hand, so they certainly do — and the
  /// screen's "this sitting was stopped somewhere else" guard read the empty
  /// session as exactly that and popped the route. The reader was returned to
  /// the book page with no chance to say where they'd got to.
  testWidgets('Stop & log opens the page question, not the way out', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    // Never closed: db.close() deadlocks between the fake-async zone and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId,
        workId: 'w',
        title: 'Aadujeevitham',
        authorNames: 'Benyamin',
        pageCount: const Value(212),
      ));
      return id;
    });

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_SlowApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    // Pushed onto a stack, as it is in the app — with nothing beneath it the
    // guard's `canPop()` is false and the bug cannot show itself.
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
      () => container.read(activeSessionProvider.notifier).start(entryId!, pageStart: 100),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await settle();
    await tester.tap(find.text('open the timer'));
    await settle();
    expect(find.text('Stop & log'), findsOneWidget);

    await tester.tap(find.text('Stop & log'));
    await settle();

    // Assert on the router, not on rendering: a popped route stays in the tree
    // while its transition plays, so `find.byType` still turns the screen up
    // for a few frames after it has actually been left (the same trap the
    // 26 Jul duplicate-route guard fell into).
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/reading-timer/$entryId',
      reason: 'the stop must not send the reader back out of the timer',
    );
    // And the face that is showing is the one with the page question on it.
    expect(find.byType(ReadingTimerScreen), findsOneWidget);
    expect(find.byType(SessionPageEntry), findsOneWidget);

    // And the sitting really was logged — the face is the confirmation of a
    // stop that happened, not a screen left running.
    final sessions = await tester.runAsync(
      () => db.readingSessionsDao.watchForEntry(entryId!).first,
    );
    expect(sessions, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });
}
