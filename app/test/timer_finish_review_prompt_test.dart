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

const _editionId = '44444444-4444-4444-4444-444444444444';

/// The API as it behaves on a real phone: taking the sitting off the account
/// is a network round trip, not an instant local write.
class _SlowApi extends ApiClient {
  @override
  Future<void> deleteActiveSession({String? deviceId}) =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  @override
  Future<Map<String, dynamic>> updateEdition(
          String editionId, Map<String, dynamic> patch) async =>
      {};
}

/// Finishing a book from the timer's wax-seal face must ask for a review.
///
/// The nudge was moved beside `markBookFinished` on 3 Sep 2026 so that every
/// door onto "the reader has just finished a book" shows it — and the owner
/// reported on 6 Sep 2026 that the timer's own "I finished the book" still
/// finished the book in silence. This drives the *real* screen end to end:
/// start a sitting, Stop & log, tap the finish, and look for the sheet.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<({AppDatabase db, ProviderContainer container, GoRouter router, String entryId})>
      openTimer(
    WidgetTester tester, {
    required int currentPage,
    Future<void> Function(AppDatabase db, SessionContext session)? seed,
  }) async {
    // Never closed: db.close() deadlocks between the fake-async zone and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await repo.updateProgress(id, currentPage: currentPage);
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId,
        workId: 'w',
        title: 'Aadujeevitham',
        authorNames: 'Benyamin',
        pageCount: const Value(212),
      ));
      await seed?.call(db, session);
      return id;
    });

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_SlowApi()),
      sessionContextProvider.overrideWith((ref) async => session),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // Pushed onto a stack, as it is in the app: the timer is left for the
    // book page beneath it, and the sheet has to appear over *that*.
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
      () => container
          .read(activeSessionProvider.notifier)
          .start(entryId!, pageStart: currentPage),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await _settle(tester);
    await tester.tap(find.text('open the timer'));
    await _settle(tester);
    expect(find.text('Stop & log'), findsOneWidget);

    await tester.tap(find.text('Stop & log'));
    await _settle(tester);
    expect(find.textContaining('I finished the book'), findsOneWidget);

    return (db: db, container: container, router: router, entryId: entryId!);
  }

  testWidgets('"I finished the book" on the wax-seal face asks for a review',
      (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final t = await openTimer(tester, currentPage: 100);

    await tester.tap(find.textContaining('I finished the book'));
    await _settle(tester);

    // The timer has been left…
    expect(
      t.router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/stub',
    );
    // …the book is Read…
    final entry = await tester.runAsync(() => t.db.libraryEntriesDao.getById(t.entryId));
    expect(entry!.status, 'read');
    // …and the review nudge is on screen.
    expect(find.byType(FinishedReviewSheet), findsOneWidget);
    expect(find.text('You finished it!'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('typing the last page and tapping Done asks for a review too',
      (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final t = await openTimer(tester, currentPage: 200);

    // The page field is the one editable number on the face.
    final field = find.byType(TextField).first;
    await tester.enterText(field, '212');
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester);

    final entry = await tester.runAsync(() => t.db.libraryEntriesDao.getById(t.entryId));
    expect(entry!.status, 'read');
    expect(find.byType(FinishedReviewSheet), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('a book rated while reading still gets the sheet, its stars lit',
      (tester) async {
    // The rule used to be "silent once a rating OR review exists" — and a
    // reader who rates a book halfway through is exactly the reader you want
    // to ask for the words. Owner report, 6 Sep 2026: finished from the timer,
    // "Marked as Read", no question.
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    await openTimer(
      tester,
      currentPage: 100,
      seed: (db, session) => RatingsRepository(db, session).setRating('w', 4),
    );

    await tester.tap(find.textContaining('I finished the book'));
    await _settle(tester);

    expect(find.byType(FinishedReviewSheet), findsOneWidget);
    expect(find.text('You finished it!'), findsOneWidget);
    // Four lit, one open: the rating they already gave, not a fresh ask.
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.textContaining('You rated it ★★★★'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('a book already reviewed is finished in peace', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final t = await openTimer(
      tester,
      currentPage: 100,
      seed: (db, session) =>
          ReviewsRepository(db, session).upsert('w', body: 'Said my piece.', visible: true),
    );

    await tester.tap(find.textContaining('I finished the book'));
    await _settle(tester);

    final entry = await tester.runAsync(() => t.db.libraryEntriesDao.getById(t.entryId));
    expect(entry!.status, 'read');
    expect(find.byType(FinishedReviewSheet), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    reportTestException = reportOriginal;
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}
