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
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/features/library/presentation/book_detail_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Series in the app.
///
/// The book page had never shown a series at all, and the add form took one as
/// free text — which is how one ordering became several rows. The line under
/// test is the reader's only door into a series, and it must read the position
/// off the **work**: it moved there in API migration 000043 because a position
/// belongs to the story, not to a printing or a language.
const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';
const _seriesId = '55555555-5555-5555-5555-555555555555';

Map<String, dynamic> _work({
  Map<String, dynamic>? series,
  int? seriesNumber,
  Map<String, dynamic>? editionSeries,
  int? editionSeriesNumber,
}) =>
    {
      'id': _workId,
      'title': 'Sulathirai',
      'subtitle': null,
      'description': null,
      'language': 'Tamil',
      'first_publish_year': 1952,
      'aggregate_rating': null,
      'translation_group_id': null,
      'series': series,
      'series_number': seriesNumber,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'Kalki'},
      ],
      'genres': <Map<String, dynamic>>[],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _editionId,
          'isbn': null,
          'language': 'Tamil',
          'page_count': null,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': editionSeriesNumber,
          'publisher': null,
          'series': editionSeries,
        },
      ],
    };

void main() {
  // ------------------------------------------------------------------
  // The list parser
  // ------------------------------------------------------------------

  group('parseRows', () {
    test('decodes rows eagerly, at the boundary', () {
      final rows = ApiClient.parseRows([
        {'id': _seriesId, 'name': 'Ponniyin Selvan', 'book_count': 5},
      ]);
      expect(rows, hasLength(1));
      expect(rows.first['book_count'], 5);
    });

    test('a non-list body throws here rather than inside a build()', () {
      expect(() => ApiClient.parseRows({'detail': 'nope'}), throwsA(isA<TypeError>()));
    });

    test('skips a row that is not an object instead of crashing the list', () {
      expect(ApiClient.parseRows(['junk']), isEmpty);
    });
  });

  // ------------------------------------------------------------------
  // The book page's series line
  // ------------------------------------------------------------------

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
    // Never closed — see book_detail_byline_test for why.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

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

  testWidgets('a book in a series says which one, and where', (tester) async {
    await pumpBook(
      tester,
      _work(series: {'id': _seriesId, 'name': 'Ponniyin Selvan'}, seriesNumber: 2),
    );

    expect(find.text('Book 2 of Ponniyin Selvan'), findsOneWidget);
    await flushTree(tester);
  });

  testWidgets('an unnumbered book still names its series', (tester) async {
    await pumpBook(tester, _work(series: {'id': _seriesId, 'name': 'Malgudi'}));

    // "Part of", never "Book null of" — and never a number invented from the
    // book's position in a list.
    expect(find.text('Part of Malgudi'), findsOneWidget);
    await flushTree(tester);
  });

  testWidgets('a book in no series shows no series line', (tester) async {
    await pumpBook(tester, _work());

    expect(find.textContaining('Book '), findsNothing);
    expect(find.textContaining('Part of'), findsNothing);
    await flushTree(tester);
  });

  testWidgets('an older API that only carries series on the edition still renders', (tester) async {
    // The app ships ahead of the API sometimes; before migration 000043 the
    // series lived on the edition, and a build talking to that API must not
    // lose the line.
    await pumpBook(
      tester,
      _work(
        editionSeries: {'id': _seriesId, 'name': 'Ponniyin Selvan'},
        editionSeriesNumber: 3,
      ),
    );

    expect(find.text('Book 3 of Ponniyin Selvan'), findsOneWidget);
    await flushTree(tester);
  });
}
