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
import 'package:kitabi/features/library/presentation/finished_review_prompt.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

import 'support/pump_until.dart';

const _editionId = '66666666-6666-6666-6666-666666666666';

class _SlowApi extends ApiClient {
  @override
  Future<void> deleteActiveSession({String? deviceId}) =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  @override
  Future<Map<String, dynamic>> updateEdition(
          String editionId, Map<String, dynamic> patch) async =>
      {};
}

/// Finishing a book on a timer that was opened **from the live notification**.
///
/// The nudge is asserted from the wax-seal face already, but every one of
/// those cases *pushes* the timer from a stub, so `canPop()` is true and the
/// screen leaves by popping. A tap on the ongoing notification or the iOS Live
/// Activity does not push: the engine delivers it as a navigation that
/// **replaces** the stack, so the timer is the whole stack, `canPop()` is
/// false and `_leave()` takes its `context.go(home)` branch instead (the same
/// asymmetry behind the 26 Jul, 14 Aug and 29 Aug reports). The reader
/// finished a book and no sheet followed (owner report, 8 Sep 2026).
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

  testWidgets('finishing from a notification-opened timer still asks for a review',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await repo.updateProgress(id, currentPage: 100);
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

    // The notification's shape: the timer IS the stack. Nothing beneath it, so
    // `canPop()` is false — with a stub underneath, the bug cannot appear.
    final router = GoRouter(
      initialLocation: '/reading-timer/$entryId',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home'))),
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
    await pumpUntilFound(tester, find.text('Stop & log'),
        reason: 'the notification to open the timer');

    await tester.tap(find.text('Stop & log'));
    await pumpUntilFound(tester, find.textContaining('I finished the book'),
        reason: 'the wax-seal face');

    await tester.tap(find.textContaining('I finished the book'));
    await pumpUntilFound(tester, find.byType(FinishedReviewSheet),
        reason: 'the review nudge');

    // The timer has been left — by `go`, since there was nothing to pop.
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/home',
    );
    // The book really is finished…
    final entry = await tester.runAsync(() => db.libraryEntriesDao.getById(entryId!));
    expect(entry!.status, 'read');
    // …and the reader is asked for a review, exactly as they are when the
    // timer was reached from the book page.
    expect(find.byType(FinishedReviewSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await drainPendingTimers(tester);
  });
}
