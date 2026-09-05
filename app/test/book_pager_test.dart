import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/features/library/book_browse_context.dart';
import 'package:kitabi/features/library/presentation/book_detail_screen.dart';
import 'package:kitabi/features/library/presentation/book_pager.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Swiping the book page through the shelf it was opened from (owner request,
/// 6 Sep 2026): left for the next book, right for the previous, and a pull
/// past either end closes the page.
const _w = ['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000003'];
const _e = ['bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000003'];
const _titles = ['Alpha Book', 'Beta Book', 'Gamma Book'];

Map<String, dynamic> _work(int i) => {
      'id': _w[i],
      'title': _titles[i],
      'subtitle': null,
      'description': null,
      'language': 'English',
      'first_publish_year': 2000 + i,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'Some Author'},
      ],
      'genres': <Map<String, dynamic>>[],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _e[i],
          'isbn': null,
          'language': 'English',
          'page_count': 200,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };

final _shelf = BookBrowseContext([
  for (var i = 0; i < 3; i++) BookRef(workId: _w[i], editionId: _e[i]),
]);

void main() {
  late AppDatabase db;
  late final void Function(FlutterErrorDetails details, String testDescription) reportOriginal;

  setUpAll(() {
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

  Future<void> settle(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> flushTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester, 6);
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  /// A stub root with the book route on top of it, as in the app — the pager
  /// has to have something to pop *to* for "closes the page" to mean anything.
  Future<GoRouter> open(
    WidgetTester tester, {
    required int at,
    Object? extra = 'shelf',
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/stub',
      routes: [
        GoRoute(
          path: '/stub',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(
                '/book/${_w[at]}/${_e[at]}',
                extra: extra == 'shelf' ? _shelf : extra,
              ),
              child: const Text('open the book'),
            ),
          ),
        ),
        GoRoute(path: '/book/:workId/:editionId', builder: buildBookRoute),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        workProvider.overrideWith((ref, id) async => _work(_w.indexOf(id))),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle(tester, 6);
    await tester.tap(find.text('open the book'));
    await settle(tester);
    return router;
  }

  group('the book page opened from a shelf', () {
    testWidgets('opens on the tapped book and swipes to its neighbours', (tester) async {
      final router = await open(tester, at: 1);
      expect(find.byType(BookPager), findsOneWidget);
      expect(find.text('Beta Book'), findsWidgets);
      expect(find.text('Gamma Book'), findsNothing);

      // Left: the next book on the shelf.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await settle(tester, 60);
      expect(find.text('Gamma Book'), findsWidgets);
      expect(find.text('Beta Book'), findsNothing);

      // Right, twice: back past the one we started on to the first.
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1500);
      await settle(tester, 60);
      expect(find.text('Beta Book'), findsWidgets);
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1500);
      await settle(tester, 60);
      expect(find.text('Alpha Book'), findsWidgets);

      // Still the one route the whole time.
      expect(location(router), '/book/${_w[1]}/${_e[1]}');
      await flushTree(tester);
    });

    testWidgets('pulling past the last book closes the page', (tester) async {
      final router = await open(tester, at: 2);
      expect(find.text('Gamma Book'), findsWidgets);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester);

      expect(location(router), '/stub', reason: 'past the end there is only the shelf');
      await flushTree(tester);
    });

    testWidgets('pulling before the first book closes the page', (tester) async {
      final router = await open(tester, at: 0);
      expect(find.text('Alpha Book'), findsWidgets);

      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await settle(tester);

      expect(location(router), '/stub');
      await flushTree(tester);
    });

    testWidgets('a small pull at the end is a bounce, not an exit', (tester) async {
      final router = await open(tester, at: 2);

      // Under the threshold: the reader nudged the page, they did not leave it.
      await tester.drag(find.byType(PageView), const Offset(-40, 0));
      await settle(tester);

      expect(location(router), '/book/${_w[2]}/${_e[2]}');
      expect(find.text('Gamma Book'), findsWidgets);
      await flushTree(tester);
    });

    testWidgets('closes on iOS too, where the ends bounce instead of clamping',
        (tester) async {
      // Bouncing physics report the pull through the position itself rather
      // than as overscroll notifications — the pager reads both.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final router = await open(tester, at: 2);
        expect(find.text('Gamma Book'), findsWidgets);

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await settle(tester);

        expect(location(router), '/stub');
        await flushTree(tester);
      } finally {
        // flutter_test checks this before tearDowns run, so reset it here.
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a shelf that does not hold the tapped book gets the plain page',
        (tester) async {
      // A stale or mismatched list must never make the pager guess.
      final other = BookBrowseContext([BookRef(workId: _w[0], editionId: _e[0])]);
      await open(tester, at: 2, extra: other);
      expect(find.byType(BookPager), findsNothing);
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('Gamma Book'), findsWidgets);
      await flushTree(tester);
    });
  });

  testWidgets('a book opened on its own (share link, Home, catalogue) does not swipe',
      (tester) async {
    final router = await open(tester, at: 1, extra: null);
    expect(find.byType(BookPager), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('Beta Book'), findsWidgets);

    await tester.drag(find.byType(BookDetailScreen), const Offset(-300, 0));
    await settle(tester);
    expect(location(router), '/book/${_w[1]}/${_e[1]}');
    expect(find.text('Beta Book'), findsWidgets);
    await flushTree(tester);
  });

  test('BookBrowseContext finds a book by its edition, not its work', () {
    // Two printings of one Work are two covers on the shelf.
    final shelf = BookBrowseContext([
      BookRef(workId: 'w', editionId: 'e1'),
      BookRef(workId: 'w', editionId: 'e2'),
    ]);
    expect(shelf.indexOf('e2'), 1);
    expect(shelf.indexOf('e9'), -1);
  });
}
