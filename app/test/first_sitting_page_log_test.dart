import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/presentation/session_log_row.dart';
import 'package:kitabi/features/library/presentation/session_page_entry.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _editionId = '44444444-4444-4444-4444-444444444444';

class _FakeApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> updateEdition(
      String editionId, Map<String, dynamic> patch) async => {};
}

ReadingSession _session({int? pageStart, int? pageEnd, bool autoStopped = false}) {
  final at = DateTime(2026, 7, 31, 9);
  return ReadingSession(
    id: 's1',
    userId: 'u1',
    libraryEntryId: 'e1',
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 40)),
    durationSeconds: 2400,
    pageStart: pageStart,
    pageEnd: pageEnd,
    createdAt: at,
    updatedAt: at,
    syncStatus: 'synced',
    autoStopped: autoStopped,
  );
}

Future<void> _pumpRow(
  WidgetTester tester,
  ReadingSession session, {
  Future<void> Function()? onDelete,
  Future<void> Function(DateTime endedAt, int? pageEnd)? onEdit,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SessionLogRow(
        session: session,
        primary: '9:00 – 9:40',
        onDelete: onDelete ?? () async {},
        onEdit: onEdit ?? (_, _) async {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('the reading log renders the page a sitting reached', () {
    testWidgets('a first sitting with no start page still shows where it ended',
        (tester) async {
      // Owner report, 31 Jul 2026: a book with no page count, the total and the
      // page typed on the very first sitting — the progress bar showed the page
      // but the reading log said "Page not noted". Nothing knows where that
      // first sitting *began* (the shelf entry had no page), so the row can
      // never draw a range — but it knows exactly where the reader got to.
      await _pumpRow(tester, _session(pageEnd: 120));

      expect(find.text('Page not noted'), findsNothing);
      expect(find.textContaining('120'), findsOneWidget);
    });

    testWidgets('a sitting that ended where it began shows that page too',
        (tester) async {
      // The 26 Jul fix made the *data* right (pageEnd is written even when
      // progress doesn't move); the row still called it "Page not noted".
      await _pumpRow(tester, _session(pageStart: 42, pageEnd: 42));

      expect(find.text('Page not noted'), findsNothing);
      expect(find.textContaining('42'), findsOneWidget);
    });

    testWidgets('a sitting that recorded nothing is still greyed and honest',
        (tester) async {
      await _pumpRow(tester, _session(pageStart: 42));

      expect(find.text('Page not noted'), findsOneWidget);
    });

    testWidgets('a full range still reads as a range', (tester) async {
      await _pumpRow(tester, _session(pageStart: 42, pageEnd: 96));

      expect(find.text('p. 42 → 96'), findsOneWidget);
      expect(find.text('+54'), findsOneWidget);
    });
  });

  group('the auto-stopped indicator', () {
    testWidgets('shows on a sitting the safety net closed', (tester) async {
      await _pumpRow(tester, _session(pageEnd: 120, autoStopped: true));
      expect(find.text('AUTO-STOPPED'), findsOneWidget);
    });

    testWidgets('is absent from an ordinary manual stop', (tester) async {
      await _pumpRow(tester, _session(pageEnd: 120));
      expect(find.text('AUTO-STOPPED'), findsNothing);
    });

    testWidgets('the edit icon opens a correction dialog naming the page field',
        (tester) async {
      await _pumpRow(tester, _session(pageEnd: 120, autoStopped: true));

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Correct this sitting'), findsOneWidget);
      expect(find.text('Page reached'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Correct this sitting'), findsNothing);
    });

    testWidgets('saving the corrected page calls onEdit', (tester) async {
      DateTime? gotEndedAt;
      int? gotPageEnd;
      await _pumpRow(
        tester,
        _session(pageEnd: 120, autoStopped: true),
        onEdit: (endedAt, pageEnd) async {
          gotEndedAt = endedAt;
          gotPageEnd = pageEnd;
        },
      );

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '244');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(gotEndedAt, isNotNull);
      expect(gotPageEnd, 244);
    });
  });

  group('deleting a sitting asks first', () {
    testWidgets('the trash icon opens a confirmation naming the sitting',
        (tester) async {
      // Owner request, 12 Aug 2026: a logged sitting is synced history —
      // one mis-tap on the trash icon must not silently erase it.
      var deleted = false;
      await _pumpRow(tester, _session(pageStart: 42, pageEnd: 96),
          onDelete: () async => deleted = true);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete this sitting?'), findsOneWidget);
      expect(find.textContaining('p. 42 → 96'), findsWidgets);
      expect(deleted, isFalse, reason: 'nothing may be deleted before the answer');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
      expect(find.text('Delete this sitting?'), findsNothing);
    });

    testWidgets('confirming actually deletes', (tester) async {
      var deleted = false;
      await _pumpRow(tester, _session(pageEnd: 120),
          onDelete: () async => deleted = true);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });

  group("the stop sheet's \"last time\" line", () {
    late AppLocalizations l10n;
    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    String? line({int? pageStart, int? pageEnd}) => formatLastSessionLine(
          l10n,
          endedAt: DateTime(2026, 7, 30, 22),
          durationSeconds: 2400,
          pageStart: pageStart,
          pageEnd: pageEnd,
        );

    test('falls back to the end page when there is no start to measure from', () {
      // Same blind spot as the log row: dropping the line entirely hid the one
      // fact the next sitting needs — where the reader got to last time.
      expect(line(pageEnd: 120), contains('ended on p. 120'));
    });

    test('still prefers the range when there is one', () {
      expect(line(pageStart: 42, pageEnd: 96), contains('p. 42 → 96'));
    });

    test('is null when the sitting noted no page at all', () {
      expect(line(pageStart: 42), isNull);
      expect(line(), isNull);
    });
  });

  testWidgets('the timer logs the page reached on a first sitting with a total',
      (tester) async {
    // The whole reported path, through the real screen: an untotalled book,
    // never read before, the page *and* the total typed on the wax-seal face.
    GoogleFonts.config.allowRuntimeFetching = false;
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
      // No page count in the catalogue, and no progress on the shelf entry —
      // so the sitting starts with nothing to anchor to.
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId, workId: 'w', title: 'Untotalled', authorNames: 'A'));
      return id;
    });

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
      }
    }

    await tester.runAsync(
        () => container.read(activeSessionProvider.notifier).start(entryId!));

    final router = GoRouter(
      initialLocation: Routes.readingTimerPath(entryId!),
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: Routes.readingTimer,
          builder: (_, state) => ReadingTimerScreen(
            libraryEntryId: state.pathParameters['libraryEntryId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle();

    await tester.tap(find.text('Stop & log'));
    await settle(until: find.byType(TextField));

    // The page reached, and the book's length — the field only the untotalled
    // case shows.
    await tester.enterText(find.byType(TextField).at(0), '120');
    await settle();
    await tester.enterText(find.byType(TextField).at(1), '300');
    await settle();

    await tester.tap(find.text('Done'));
    await settle();

    final sessions =
        await tester.runAsync(() => db.readingSessionsDao.watchForEntry(entryId).first);
    expect(sessions, hasLength(1));
    expect(sessions!.single.pageEnd, 120,
        reason: 'the sitting must record the page the reader typed');

    final entry = await tester.runAsync(() => db.libraryEntriesDao.getById(entryId));
    expect(entry?.currentPage, 120);
    final book = await tester.runAsync(() => db.cachedBooksDao.getByEditionId(_editionId));
    expect(book?.pageCount, 300);

    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });
}
