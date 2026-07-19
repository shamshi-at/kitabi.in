import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/features/library/presentation/book_detail_screen.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/presentation/review_editor_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _work() => {
      'id': _workId,
      'title': 'Chemmeen',
      'subtitle': null,
      'description': 'A sea-salted love story of Kuttanad.',
      'language': 'Malayalam',
      'first_publish_year': 1956,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'Thakazhi Sivasankara Pillai'},
      ],
      'genres': <Map<String, dynamic>>[],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _editionId,
          'isbn': '9788126415419',
          'language': 'Malayalam',
          'page_count': 184,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };

void main() {
  late AppDatabase db;

  late final void Function(FlutterErrorDetails details, String testDescription) reportOriginal;

  setUpAll(() {
    // runAsync lets google_fonts' real HTTP fetch run (and fail) — tests must
    // never touch the network; fall back to the bundled default font. The
    // fallback itself raises an async "font not found in assets" exception
    // (Fraunces isn't bundled), which is cosmetic-only — filter it out.
    GoogleFonts.config.allowRuntimeFetching = false;
    reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
  });

  tearDownAll(() {
    reportTestException = reportOriginal;
  });

  setUp(() {
    // Never closed: db.close() deadlocks between the fake-async test zone and
    // drift's real event loop; an in-memory db per test just gets GC'd.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  List<Override> overrides() => [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        workProvider.overrideWith((ref, id) async => _work()),
      ];

  Widget wrapWithRouter(String initialLocation) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/book/:workId/:editionId',
          builder: (context, state) => BookDetailScreen(
            workId: state.pathParameters['workId']!,
            editionId: state.pathParameters['editionId']!,
          ),
        ),
        GoRoute(
          path: '/review/:workId',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>? ?? const {};
            return ReviewEditorScreen(
              workId: state.pathParameters['workId']!,
              title: args['title'] as String?,
              author: args['author'] as String?,
              coverUrl: args['coverUrl'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/reading-timer/:libraryEntryId',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>? ?? const {};
            return ReadingTimerScreen(
              libraryEntryId: state.pathParameters['libraryEntryId']!,
              title: args['title'] as String?,
              author: args['author'] as String?,
              currentPage: args['currentPage'] as int?,
              pageCount: args['pageCount'] as int?,
            );
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: overrides(),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  /// Real Drift queries resolve on the real event loop, which fake-async test
  /// time never advances — and the await chains alternate between real-async
  /// drift work (needs runAsync) and fake-zone Timer hops (need a *timed*
  /// pump; a bare pump() doesn't advance fake time). Interleave both.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Flush drift's stream-close timers before the binding's end-of-test
  /// pending-timer check — call as the last line of every test.
  Future<void> flushTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('review editor saves rating and review together to Drift', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrapWithRouter('/review/$_workId'));
    await settle(tester);

    // 4th star, then the review text.
    await tester.tap(find.byIcon(Icons.star_border).at(3));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'A sea-salted classic.');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final (rating, review) = await tester.runAsync(() async {
      return (
        await db.ratingsDao.watchForWork(_workId).first,
        await db.reviewsDao.watchForWork(_workId).first,
      );
    }) as (Rating?, Review?);
    expect(rating?.value, 4);
    expect(review?.body, 'A sea-salted classic.');
    expect(review?.visible, false); // default stays private (rule 13)

    await flushTree(tester);
  });

  testWidgets('review card on the book page opens the dedicated editor', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await repo.add(editionId: _editionId);
    });

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    await tester.tap(find.text('No review yet — tap to write one.'));
    await settle(tester);

    expect(find.text('Rate & review'), findsOneWidget);
    // Scoped to the editor — the book page beneath keeps its own star icons.
    expect(
      find.descendant(
        of: find.byType(ReviewEditorScreen),
        matching: find.byIcon(Icons.star_border),
      ),
      findsNWidgets(5),
    );

    await flushTree(tester);
  });

  testWidgets('book page shows the About section with an improve-entry action', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    // About is its own tab now — the Yours tab (status/review/notes/lending)
    // shows by default.
    await tester.tap(find.text('ABOUT'));
    await settle(tester);

    expect(find.text('ABOUT THIS BOOK'), findsOneWidget);
    expect(find.text('A sea-salted love story of Kuttanad.'), findsOneWidget);
    expect(find.text('Improve this entry'), findsOneWidget);

    await flushTree(tester);
  });

  testWidgets('marking a book read prompts a review — but not when one already exists',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await repo.add(editionId: _editionId);
    });

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    // Status + progress are one merged card now: tap "Change" to open the
    // status sheet, then the status label within it.
    Future<void> changeStatus(String label) async {
      await tester.tap(find.text('Change'));
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    await changeStatus('Read');

    expect(find.text('You finished it!'), findsOneWidget);

    // The popup's primary button opens the full editor.
    await tester.tap(find.text('Write a review'));
    await settle(tester);
    expect(find.text('Rate & review'), findsOneWidget);

    // Rate the book, then re-mark read — no prompt the second time.
    await tester.runAsync(() async {
      final ratings = RatingsRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await ratings.setRating(_workId, 5);
    });
    await tester.pageBack();
    await settle(tester);
    // The pop's route transition (the editor sliding away) can still be
    // mid-flight here — its exiting tree briefly overlaps the status card's
    // hit-test region — so give it real time to fully finish before the next
    // tap, same reasoning as the snackbar wait this replaced.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await changeStatus('Reading');
    await changeStatus('Read');

    expect(find.text('You finished it!'), findsNothing);

    await flushTree(tester);
  });

  testWidgets('finished-read popup: tapping a star rates immediately and "Not now" dismisses',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await repo.add(editionId: _editionId);
    });

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    await tester.tap(find.text('Change'));
    await settle(tester);
    await tester.tap(find.text('Read'));
    await settle(tester);

    expect(find.text('You finished it!'), findsOneWidget);

    // Tap the 4th star — saves straight to Drift without leaving the sheet.
    // Scoped by size (32px): the Yours tab's own review card sits underneath
    // the sheet with its own 16px star_border row, so a bare byIcon() finder
    // matches both and .at(3) can land on the wrong one.
    final sheetStars = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.star_border && w.size == 32,
    );
    await tester.tap(sheetStars.at(3));
    await settle(tester);

    final rating = await tester.runAsync(() => db.ratingsDao.watchForWork(_workId).first);
    expect(rating?.value, 4);
    await settle(tester);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    await settle(tester);
    expect(find.text('You finished it!'), findsNothing);

    await flushTree(tester);
  });

  testWidgets('reading timer: start, stop, and the session lands in the log', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await repo.updateProgress(id, currentPage: 50);
    });

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    expect(find.text('Start a session'), findsOneWidget);
    await tester.tap(find.text('Start a session'));
    await settle(tester);

    expect(find.text('Session in Progress'), findsOneWidget);
    await tester.tap(find.text('Stop & log'));
    await settle(tester);
    await settle(tester);

    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle(tester);
    await settle(tester);

    // Back on the book page — a fresh session sits in the log; the card offers
    // "Start a session" again and its footer summarises the sitting.
    expect(find.text('Start a session'), findsOneWidget);
    expect(find.textContaining('Last read'), findsOneWidget);

    final entry = await tester.runAsync(() => db.libraryEntriesDao.getByEditionId(_editionId));
    final sessions = await tester.runAsync(() => db.readingSessionsDao.watchForEntry(entry!.id).first);
    expect(sessions, hasLength(1));
    expect(sessions!.first.pageStart, 50);

    await flushTree(tester);
  });

  testWidgets('reading timer: log manually records a session and shows pages read', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await repo.updateProgress(id, currentPage: 50);
    });

    await tester.pumpWidget(wrapWithRouter('/book/$_workId/$_editionId'));
    await settle(tester);

    // Manual log is the compact ✎ beside "Start a session".
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_note));
    await settle(tester);

    expect(find.text('Log a reading session'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '30');
    // The page field is pre-filled with the current page (50) — replace it
    // with the end page for this session.
    await tester.enterText(find.byType(TextField).at(1), '78');
    await settle(tester);

    await tester.tap(find.text('Save session'));
    await settle(tester);
    await settle(tester);

    // Sheet closed, back on the book page; open the reading log from the footer
    // and the session shows the pages it moved through.
    expect(find.text('Log a reading session'), findsNothing);
    await tester.tap(find.textContaining('1 session'));
    await settle(tester);
    expect(find.text('Reading log'), findsOneWidget);
    expect(find.text('p. 50 → 78'), findsOneWidget);

    final entry = await tester.runAsync(() => db.libraryEntriesDao.getByEditionId(_editionId));
    final sessions = await tester.runAsync(() => db.readingSessionsDao.watchForEntry(entry!.id).first);
    expect(sessions, hasLength(1));
    expect(sessions!.first.durationSeconds, 30 * 60);
    expect(sessions.first.pageStart, 50);
    expect(sessions.first.pageEnd, 78);
    expect(entry!.currentPage, 78);

    await flushTree(tester);
  });

  testWidgets('review card shows rating above the review body; distribution does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final repo = LibraryRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await repo.add(editionId: _editionId);
      final ratings = RatingsRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await ratings.setRating(_workId, 4);
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...overrides(),
        publicReviewsProvider(_workId).overrideWith((ref) async => {
              'reviews': <Map<String, dynamic>>[
                {
                  'reviewer': {'is_public': true, 'display_name': 'Reader One', 'avatar_url': null},
                  'rating': 5,
                  'body': 'Loved it.',
                },
              ],
              // A high count skews maxCount up, which is what pushed the
              // 5-star icon row past the old fixed-width column and produced
              // the RenderFlex overflow this test guards against.
              'rating_average': 4.2,
              'rating_count': 128,
              'rating_distribution': {'1': 2, '2': 3, '3': 10, '4': 40, '5': 73},
            }),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/book/$_workId/$_editionId',
          routes: [
            GoRoute(
              path: '/book/:workId/:editionId',
              builder: (context, state) => BookDetailScreen(
                workId: state.pathParameters['workId']!,
                editionId: state.pathParameters['editionId']!,
              ),
            ),
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle(tester);

    // Rating sits above the review body in the "My review" card, per the
    // approved mockup — not below it.
    final ratingTop = tester.getTopLeft(find.byIcon(Icons.star).first).dy;
    final bodyTop = tester.getTopLeft(find.text('No review yet — tap to write one.')).dy;
    expect(ratingTop, lessThan(bodyTop));

    await tester.tap(find.text('ABOUT'));
    await settle(tester);

    // The rating-distribution column must fit its 5-star row without
    // throwing a RenderFlex overflow. (The hero also shows "4.2", so this
    // just confirms the distribution rendered at all.)
    expect(find.text('4.2'), findsWidgets);
    expect(tester.takeException(), isNull);

    await flushTree(tester);
  });
}
