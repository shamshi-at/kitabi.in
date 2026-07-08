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
import 'package:kitabi/features/library/presentation/review_editor_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _work() => {
      'id': _workId,
      'title': 'Chemmeen',
      'subtitle': null,
      'description': null,
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

    await tester.tap(find.text('Read'));
    await settle(tester);

    expect(find.text('Finished! What did you think?'), findsOneWidget);

    // The snackbar action opens the editor.
    await tester.tap(find.text('Review'));
    await settle(tester);
    expect(find.text('Rate & review'), findsOneWidget);

    // Rate the book, then re-mark read — no prompt the second time.
    await tester.runAsync(() async {
      final ratings = RatingsRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));
      await ratings.setRating(_workId, 5);
    });
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Reading'));
    await settle(tester);
    await tester.tap(find.text('Read'));
    await settle(tester);

    expect(find.text('Finished! What did you think?'), findsNothing);

    await flushTree(tester);
  });
}
