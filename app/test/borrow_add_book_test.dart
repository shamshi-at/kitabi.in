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
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/features/lending/presentation/log_borrowed_sheet.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// A book you've borrowed is often exactly the book no catalog knows, so the
/// borrow sheet's search must not dead-end: it offers to add what you typed,
/// carries the title into the add form, and comes back with the new book
/// selected (owner request, 16 Jul 2026).
class _FakeApiClient extends ApiClient {
  List<Map<String, dynamic>> searchResult = const [];
  Map<String, dynamic>? lastCreatePayload;

  @override
  Future<List<Map<String, dynamic>>> searchCatalog(String query) async => searchResult;

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async => const [];

  @override
  Future<Map<String, dynamic>> createWork(Map<String, dynamic> payload) async {
    lastCreatePayload = payload;
    return {
      'id': 'w-new',
      'title': payload['title'],
      'subtitle': null,
      'description': null,
      'language': null,
      'first_publish_year': null,
      'form': payload['form'],
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': <Map<String, dynamic>>[],
      'genres': <Map<String, dynamic>>[],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': 'ed-new',
          'isbn': null,
          'language': null,
          'page_count': null,
          'pub_date': null,
          'format': payload['format'],
          'cover_url': null,
          'back_cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };
  }
}

void main() {
  late AppDatabase db;
  late final void Function(FlutterErrorDetails, String) reportOriginal;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
  });

  tearDownAll(() => reportTestException = reportOriginal);

  setUp(() {
    // Never closed: db.close() deadlocks between the fake-async test zone and
    // drift's real event loop; an in-memory db per test just gets GC'd.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  Widget wrap(_FakeApiClient api) {
    final router = GoRouter(
      initialLocation: '/ledger',
      routes: [
        GoRoute(
          path: '/ledger',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogBorrowedSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: Routes.catalogAdd,
          builder: (context, state) {
            final map = state.extra as Map<String, dynamic>? ?? const {};
            return AddEditBookScreen(
              initialTitle: map['title'] as String?,
              returnCreated: map['returnCreated'] as bool? ?? false,
            );
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  testWidgets('a search with no match offers to add the typed book to the catalog',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApiClient(); // searchResult stays empty — nothing matches
    await tester.pumpWidget(wrap(api));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'test book');
    await tester.pumpAndSettle();

    expect(find.text('＋ Add "test book" to the catalog'), findsOneWidget);
    expect(
      find.text("Not in the catalog yet? Add it — you'll come right back here."),
      findsOneWidget,
    );
  });

  testWidgets('adding from the borrow sheet prefills the title and returns the book selected',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApiClient();
    await tester.pumpWidget(wrap(api));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'test book');
    await tester.pumpAndSettle();

    await tester.tap(find.text('＋ Add "test book" to the catalog'));
    await tester.pumpAndSettle();

    // The add form opened with the typed title already in — never retyped.
    // (Twice: the title field, and the live typeset cover mirroring it.)
    expect(find.text('Add a book'), findsOneWidget);
    expect(find.text('test book'), findsWidgets);

    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(api.lastCreatePayload?['title'], 'test book');
    // Pick mode skips the standalone "Added to the catalog" popup...
    expect(find.text('Add to library'), findsNothing);
    // ...and we're back on the sheet with the new book selected, ready to save.
    expect(find.text('Log a borrowed book'), findsOneWidget);
    expect(find.text('test book'), findsWidgets);
    expect(find.text('Save to my borrowed shelf'), findsOneWidget);
  });

  testWidgets('the add-new row is offered even when the search does match something',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApiClient()
      ..searchResult = [
        {
          'id': 'w1',
          'title': 'Test Book of Poems',
          'first_publish_year': 1990,
          'form': null,
          'aggregate_rating': null,
          'authors': [
            {'id': 'a1', 'name': 'Someone Else'},
          ],
          'edition': {'id': 'ed1', 'cover_url': null},
        },
      ];
    await tester.pumpWidget(wrap(api));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'test book');
    await tester.pumpAndSettle();

    // The near-match may not be the reader's copy — the door stays open, but
    // without the "nothing matched" reassurance line. (The result title shows
    // twice: on its typeset cover and as the tile's text.)
    expect(find.text('Test Book of Poems'), findsWidgets);
    expect(find.text('＋ Add "test book" to the catalog'), findsOneWidget);
    expect(
      find.text("Not in the catalog yet? Add it — you'll come right back here."),
      findsNothing,
    );
  });
}
