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
import 'package:kitabi/l10n/app_localizations.dart';

/// The branded Amazon buy button (owner decision, 9 Aug 2026): the book page
/// renders ONE recognisable button from the API's single Amazon link, with
/// the affiliate disclosure only when the link actually pays.
const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';

Map<String, dynamic> _work({List<Map<String, dynamic>>? buyLinks}) => {
      'id': _workId,
      'title': 'Naalukettu',
      'subtitle': null,
      'description': null,
      'language': 'Malayalam',
      'first_publish_year': 1958,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'M.T. Vasudevan Nair'},
      ],
      'genres': <Map<String, dynamic>>[],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _editionId,
          'isbn': '9788126403455',
          'language': 'Malayalam',
          'page_count': null,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
          // Written from the API schema (BuyLinkOut via services/buy_links.py):
          // Amazon-only — one entry, affiliate when the tag is configured.
          'buy_links': ?buyLinks,
        },
      ],
    };

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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  // Replace the tree and drain its timers before the binding's teardown
  // check — a stream-backed page torn down mid-flight leaves a pending timer
  // that fails the whole test after it passed.
  Future<void> flushTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> pumpBook(WidgetTester tester, Map<String, dynamic> work) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
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
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        workProvider.overrideWith((ref, id) async => work),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await settle(tester);
  }

  testWidgets('an affiliate Amazon link renders the branded button + disclosure',
      (tester) async {
    await pumpBook(
      tester,
      _work(buyLinks: [
        {
          'retailer': 'Amazon',
          'url': 'https://www.amazon.in/dp/8126403454?tag=kitabi0f-21',
          'affiliate': true,
        },
      ]),
    );

    expect(find.text('Buy on Amazon.in', skipOffstage: false), findsOneWidget);
    expect(find.text('amazon', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Kitabi may earn a commission from these links.', skipOffstage: false),
      findsOneWidget,
    );
    await flushTree(tester);
  });

  testWidgets('an unpaid link renders the button but no disclosure', (tester) async {
    await pumpBook(
      tester,
      _work(buyLinks: [
        {'retailer': 'Amazon', 'url': 'https://www.amazon.in/dp/8126403454', 'affiliate': false},
      ]),
    );

    expect(find.text('Buy on Amazon.in', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Kitabi may earn a commission from these links.', skipOffstage: false),
      findsNothing,
    );
    await flushTree(tester);
  });

  testWidgets('no links, no button', (tester) async {
    await pumpBook(tester, _work());
    expect(find.text('Buy on Amazon.in', skipOffstage: false), findsNothing);
    await flushTree(tester);
  });

  testWidgets('an older API still sending several links yields ONE button', (tester) async {
    await pumpBook(
      tester,
      _work(buyLinks: [
        {'retailer': 'Amazon', 'url': 'https://www.amazon.in/dp/x', 'affiliate': false},
        {'retailer': 'Flipkart', 'url': 'https://www.flipkart.com/y', 'affiliate': false},
      ]),
    );
    expect(find.text('Buy on Amazon.in', skipOffstage: false), findsOneWidget);
    await flushTree(tester);
  });
}
