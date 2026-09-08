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
import 'package:kitabi/data/repositories/repository_providers.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

import 'support/pump_until.dart';

const _editionId = '77777777-7777-7777-7777-777777777777';

/// Counts the page saves the screen actually makes.
class _CountingSessionsRepo extends ReadingSessionsRepository {
  _CountingSessionsRepo(super.db, super.session, {super.onMutation});

  int pageEndSaves = 0;

  @override
  Future<void> updateSessionPageEnd(String sessionId, int pageEnd) async {
    pageEndSaves++;
    await super.updateSessionPageEnd(sessionId, pageEnd);
  }
}

/// Leaving the timer must save the page exactly once.
///
/// The `PopScope` on this screen saves on the way out because the back gesture
/// has no other chance to (16 Jul 2026). But `_leave()` pops as well, and
/// `Navigator.pop` invokes that same callback — so every Done and every "I
/// finished the book" ran a *second* `_savePage`, and with it a second review
/// prompt, racing the first through a `ref` and a `context` belonging to a
/// widget already on its way to `dispose` (8 Sep 2026, found by probe while
/// chasing a missing review popup).
///
/// Both halves are asserted, because fixing the first by simply deleting the
/// pop-save would silently undo the 16 Jul fix.
void main() {
  late final void Function(FlutterErrorDetails, String) reportOriginal;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reportOriginal = reportTestException;
    reportTestException = (details, desc) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, desc);
    };
  });
  tearDownAll(() => reportTestException = reportOriginal);

  Future<({_CountingSessionsRepo repo, GoRouter router})> openStoppedTimer(
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final library = LibraryRepository(db, session);
    final sessions = _CountingSessionsRepo(db, session, onMutation: () {});

    final entryId = await tester.runAsync(() async {
      final id = await library.add(editionId: _editionId);
      await library.updateStatus(id, 'reading');
      await library.updateProgress(id, currentPage: 100);
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
      apiClientProvider.overrideWithValue(ApiClient()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
      readingSessionsRepositoryProvider.overrideWith((ref) async => sessions),
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
    await pumpUntilFound(tester, find.text('open the timer'));
    await tester.tap(find.text('open the timer'));
    await pumpUntilFound(tester, find.text('Stop & log'), reason: 'the timer to open');
    await tester.tap(find.text('Stop & log'));
    await pumpUntilFound(tester, find.textContaining('I finished the book'),
        reason: 'the wax-seal face');

    // Move the page, so a save has something real to write.
    await tester.enterText(find.byType(TextField).first, '150');
    await pumpFrames(tester, 3);
    return (repo: sessions, router: router);
  }

  testWidgets('Done saves the page once, not twice', (tester) async {
    final t = await openStoppedTimer(tester);

    await tester.tap(find.text('Done'));
    // The router, not a finder: the stub beneath the push is still in the
    // tree, so a finder for it matches before Done has done anything.
    await pumpUntil(
      tester,
      () => t.router.routerDelegate.currentConfiguration.matches.last.matchedLocation == '/stub',
      reason: 'the timer to be left after Done',
    );

    expect(
      t.repo.pageEndSaves,
      1,
      reason: 'the pop `_leave()` makes must not re-enter the back-gesture save',
    );
  });

  testWidgets('the back gesture still saves the page', (tester) async {
    final t = await openStoppedTimer(tester);

    // The system back button, as the OS delivers it.
    await tester.binding.handlePopRoute();
    await pumpUntil(
      tester,
      () => t.router.routerDelegate.currentConfiguration.matches.last.matchedLocation == '/stub',
      reason: 'the timer to be left by the back gesture',
    );

    expect(
      t.repo.pageEndSaves,
      1,
      reason: 'the wax-seal face has no close button — back is a real save path (16 Jul 2026)',
    );
  });
}
