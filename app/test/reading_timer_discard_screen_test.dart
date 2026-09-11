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
import 'package:kitabi/l10n/app_localizations.dart';

import 'support/pump_until.dart';

const _editionId = '55555555-5555-5555-5555-555555555555';

/// Taking the sitting off the account is a network round trip on a real phone,
/// not an instant local write — and the discard fires it unawaited, so frames
/// render while it is in the air. That window is exactly where this screen has
/// lost the reader before (14 Aug 2026).
class _SlowApi extends ApiClient {
  int deletes = 0;

  @override
  Future<void> deleteActiveSession({String? deviceId}) async {
    deletes++;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// The timer's way out for a sitting that was never reading (owner request,
  /// 12 Sep 2026). Two things it has to get right, and they pull in opposite
  /// directions: it must not throw a sitting away without asking, and once
  /// asked and answered it must leave *once* — the discard clears the session,
  /// which this screen's own "stopped somewhere else" guard reads as a reason
  /// to leave on its own, so an unguarded discard exits twice and takes the
  /// book page with it.
  testWidgets('Discard asks first, then leaves once with nothing logged',
      (tester) async {
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
        title: 'Naalukettu',
        authorNames: 'M. T. Vasudevan Nair',
        pageCount: const Value(180),
      ));
      return id;
    });

    final api = _SlowApi();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // Three deep on purpose. With only the timer's parent beneath it, a second
    // exit is a `canPop()` that comes back false and does nothing — the bug
    // hides. The page the reader should land on has to have a page *under* it
    // for a double-pop to be visible at all.
    final router = GoRouter(
      initialLocation: '/stub',
      routes: [
        GoRoute(
          path: '/stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/book'),
              child: const Text('open the book'),
            ),
          ),
        ),
        GoRoute(
          path: '/book',
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
      () => container.read(activeSessionProvider.notifier).start(entryId!, pageStart: 30),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await pumpUntilFound(tester, find.text('open the book'));
    await tester.tap(find.text('open the book'));
    await pumpUntilFound(tester, find.text('open the timer'));
    await tester.tap(find.text('open the timer'));
    await pumpUntilFound(tester, find.text('Stop & log'), reason: 'the timer to open');

    // 1 — the sitting is never thrown away without a question.
    await tester.tap(find.text('Discard this sitting'));
    await pumpUntilFound(tester, find.text('Discard this sitting?'),
        reason: 'the confirmation, which is the whole point of the control');
    expect(find.text('Keep timing'), findsOneWidget);

    // 2 — backing out of the question leaves the sitting exactly as it was.
    await tester.tap(find.text('Keep timing'));
    await pumpUntil(tester, () => find.text('Discard this sitting?').evaluate().isEmpty,
        reason: 'the dialog to close');
    expect(container.read(activeSessionProvider), isNotNull,
        reason: '"Keep timing" means the clock keeps running');
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/reading-timer/$entryId',
    );

    // 3 — and answering it ends the sitting with nothing filed.
    await tester.tap(find.text('Discard this sitting'));
    await pumpUntilFound(tester, find.text('Discard this sitting?'));
    await tester.tap(find.text('Discard'));
    await pumpUntil(
      tester,
      () =>
          router.routerDelegate.currentConfiguration.matches.last.matchedLocation !=
          '/reading-timer/$entryId',
      reason: 'the timer to close',
    );
    // …and then keep pumping. A second exit does not arrive on the same frame
    // as the first — it comes from whichever of the two paths finishes last,
    // several frames later. A test that asserts the moment the timer closes
    // reads the location *between* the two pops and is green either way; this
    // is the wait that makes the assertion below mean something (probed:
    // remove `_leaving = true` from `_discard` and it fails here).
    await pumpFrames(tester, 15);

    // Assert on the router, not on rendering: a popped route stays in the tree
    // while its transition plays (26 Jul 2026).
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/book',
      reason: 'one tap, one exit — a second one would strand the reader a page '
          'further back than they ever asked to go',
    );
    expect(container.read(activeSessionProvider), isNull);
    final sessions = await tester.runAsync(
      () => db.readingSessionsDao.watchForEntry(entryId!).first,
    );
    expect(sessions, isEmpty,
        reason: 'the reader said they did not read — nothing may be logged');
    expect(await tester.runAsync(() => db.keyValuesDao.getValue(activeSessionEntryKey)),
        isNull);

    // And the account is told the timer is off, the same way a stop tells it.
    await pumpUntil(tester, () => api.deletes > 0,
        reason: 'the sitting to be taken off the account');

    await tester.pumpWidget(const SizedBox());
    await drainPendingTimers(tester);
    reportTestException = reportOriginal;
  });

  /// The watch face is a fixed slab — cover, 220px dial, zone badge — and the
  /// discard button is one more thing stacked under it. On a short screen it
  /// cannot all fit, and a `Center` answers that by overflowing: an
  /// unmissable yellow-and-black bar straight across the dial. This is the
  /// case the 800x600 harness caught by six pixels when the button went in.
  testWidgets('the running face survives a short screen', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);
    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId,
        workId: 'w',
        title: 'Naalukettu',
        authorNames: 'M. T. Vasudevan Nair',
        pageCount: const Value(180),
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

    await tester.runAsync(
      () => container.read(activeSessionProvider.notifier).start(entryId!, pageStart: 30),
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReadingTimerScreen(libraryEntryId: entryId!),
      ),
    ));
    // An overflow is reported as a test exception, so simply getting here
    // with both controls on screen is the assertion.
    await pumpUntilFound(tester, find.text('Stop & log'));
    expect(find.text('Discard this sitting'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await drainPendingTimers(tester);
    reportTestException = reportOriginal;
  });
}
