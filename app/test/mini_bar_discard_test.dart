import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/core/router/shell_scaffold.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/connections/connections_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

import 'support/pump_until.dart';

const _editionId = '66666666-6666-6666-6666-666666666666';

class _FakeApi extends ApiClient {
  int deletes = 0;

  @override
  Future<void> deleteActiveSession({String? deviceId}) async => deletes++;

  @override
  Future<void> putActiveSession(Map<String, dynamic> body) async {}
}

/// How long the platform takes to answer in this test, on the test's own
/// clock.
const _platformDelay = Duration(milliseconds: 400);

/// Room for everything behind a discard to finish when each platform call in
/// it takes [_platformDelay] — about sixty frames of waiting, so the default
/// ten seconds would do, but nothing is gained by cutting it fine.
const _slowTeardownTimeout = Duration(seconds: 30);

/// Make every platform call slow to answer. The answer itself is unchanged —
/// whatever a mock or the engine would have said, only later.
///
/// Why: discarding a sitting takes down the lock-screen clock, a notification
/// and a background task before it tells the account, and the app waits for
/// each. How long that takes depends on the machine. On a Mac every one of
/// them is a channel nobody is listening on, which fails within the frame. On
/// Linux — which is what CI runs — `flutter test` registers the notification
/// plugin's Dart implementation, and its `cancel` reads files before it
/// answers. A test that only ever meets the fast case can be right by luck;
/// this one was. So it runs against the slow case on every machine, and a
/// wait that is merely *long enough here* now fails here too.
void _slowPlatform(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.allMessagesHandler = (channel, handler, message) async {
    await Future<void>.delayed(_platformDelay);
    return handler != null ? handler(message) : messenger.delegate.send(channel, message);
  };
  addTearDown(() => messenger.allMessagesHandler = null);
}

/// The mini-bar's own way out of a sitting that was never reading (owner
/// request, 12 Sep 2026). It is the door that matters most in practice — a
/// reader who left a timer running meets this bar before they meet anything
/// else — and it is also the hardest one to write, because the bar is built
/// *only while a session is live*: the moment the discard lands, the widget
/// that asked for it and its `ref` are gone. Every read afterwards has to go
/// through a handle captured beforehand, or it silently does nothing (the
/// 19 Jul and 31 Jul 2026 reports, against this exact widget).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the mini-bar discards a sitting, asking first', (tester) async {
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

    final api = _FakeApi();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
      syncErrorCountProvider.overrideWith((ref) => Stream.value(0)),
      connectionsProvider.overrideWith(
        (ref) async => ConnectionsData(incoming: [], outgoing: [], accepted: []),
      ),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => ShellScaffold(navigationShell: shell),
          branches: [
            for (final path in ['/home', '/library', '/lending', '/insights'])
              StatefulShellBranch(routes: [
                GoRoute(path: path, builder: (_, _) => const SizedBox()),
              ]),
          ],
        ),
        GoRoute(
          path: '/reading-timer/:id',
          builder: (_, _) => const Scaffold(body: Text('THE TIMER')),
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
    // The ✕ is the anchor for the whole test: it exists nowhere else in the
    // shell, and the bar that carries it is built *only* while a sitting runs
    // — so finding it is the same statement as "a sitting is live and the
    // reader can see it". (The book's title is not usable for that: the
    // typeset cover fallback renders it too, so it matches twice.)
    final discard = find.byIcon(Icons.close_rounded);
    await pumpUntilFound(tester, discard,
        reason: 'the mini-bar, which only exists while a sitting runs');
    // The book resolves a beat later (two composed streams behind
    // `activeSessionBookProvider`); until then the bar draws placeholders of
    // the same footprint, which is a legitimate state and not what is being
    // tested — so wait for the title rather than assert it on arrival.
    await pumpUntilFound(tester, find.text('Naalukettu').first,
        reason: 'the bar to name the book it is timing');

    await tester.tap(discard);
    await pumpUntilFound(tester, find.text('Discard this sitting?'),
        reason: 'the confirmation — the mini-bar must not throw a sitting away '
            'on one tap of a small glyph');

    // Backing out leaves everything exactly as it was.
    await tester.tap(find.text('Keep timing'));
    await pumpUntil(tester, () => find.text('Discard this sitting?').evaluate().isEmpty);
    expect(container.read(activeSessionProvider), isNotNull);
    expect(discard, findsOneWidget, reason: 'the bar is still there');

    // And answering it ends the sitting with nothing filed — from a caller
    // that is unmounted by its own success.
    await tester.tap(discard);
    await pumpUntilFound(tester, find.text('Discard this sitting?'));
    // From here the platform is slow to answer, on every machine — see
    // [_slowPlatform]. It is what makes the waits below mean something.
    _slowPlatform(tester);
    await tester.tap(find.text('Discard'));
    await pumpUntil(tester, () => container.read(activeSessionProvider) == null,
        reason: 'the sitting to end');
    await pumpUntil(tester, () => discard.evaluate().isEmpty,
        reason: 'the bar — the caller — to go with it');

    // The clock stops the moment the reader says so: `state` is cleared before
    // the first await. Everything behind that — the rows, the three takedowns
    // and only then the account being told — is still in flight when the bar
    // disappears, and nothing on screen waits for it. So each fact below is
    // waited *for*, never waited *out*.
    //
    // This was `pumpFrames(tester, 10)` followed by the assertions, which is a
    // budget rather than a condition: plenty on a laptop, where the whole
    // chain lands within one frame, and not enough on the CI runner. `app-ci`
    // was red on this one assertion from 14 Sep to 5 Oct 2026 while the test
    // passed locally every time. The sitting was always discarded correctly;
    // the test asked too soon.
    await pumpUntil(tester, () => api.deletes > 0,
        reason: 'the account to be told — until then it still believes a timer is running',
        timeout: _slowTeardownTimeout);

    // The snackbar is the whole feedback for this door: there is no wax-seal
    // face to land on, so without it the timer simply vanishes and the reader
    // has to guess whether the time was filed. It has to survive the caller's
    // unmounting, which is what the captured messenger is for.
    await pumpUntilFound(tester, find.text('Sitting discarded — nothing was logged'),
        reason: 'the snackbar that says nothing was filed', timeout: _slowTeardownTimeout);

    final sessions = await tester.runAsync(
      () => db.readingSessionsDao.watchForEntry(entryId!).first,
    );
    expect(sessions, isEmpty,
        reason: 'the reader said they did not read — nothing may be logged');
    expect(await tester.runAsync(() => db.keyValuesDao.getValue(activeSessionEntryKey)),
        isNull);

    // Back to an ordinary platform before the teardown, so the drain below
    // is not left waiting on a slow answer of its own.
    tester.binding.defaultBinaryMessenger.allMessagesHandler = null;
    await tester.pumpWidget(const SizedBox());
    await drainPendingTimers(tester);
    reportTestException = reportOriginal;
  });
}
