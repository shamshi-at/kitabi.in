import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/core/router/tab_reset.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/presentation/library_grid_screen.dart';
import 'package:kitabi/features/library/presentation/shelf_sheets.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The library's shelves view (S1, owner pick 17 Jul 2026) and its expanding
/// floating control: built-in shelves from statuses/favourites, personal
/// shelves from tags, tap-to-open as a filtered grid, and search/filter/sort
/// living on the fab now that the header scrolls away.
class _FakeApiClient extends ApiClient {
  @override
  Future<Map<String, dynamic>> getWork(String workId) async => {'editions': []};
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

  setUp(() async {
    // Never closed: db.close() deadlocks between the fake-async test zone and
    // drift's real event loop; an in-memory db per test just gets GC'd.
    db = AppDatabase.forTesting(NativeDatabase.memory());

    Future<void> book(String ed, String title, String author, String status,
        {bool favourite = false}) async {
      // No coverUrl: a real URL would pull in the disk image cache, whose
      // path_provider channel doesn't exist under flutter_test — the typeset
      // fallback renders the same titles without touching the platform.
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: ed,
        workId: 'w-$ed',
        title: title,
        authorNames: author,
      ));
      await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
        id: 'le-$ed',
        userId: 'u1',
        editionId: ed,
        status: Value(status),
        isFavorite: Value(favourite),
      ));
    }

    await book('e1', 'Khasakkinte Itihasam', 'O.V. Vijayan', 'reading', favourite: true);
    await book('e2', 'Randamoozham', 'M.T. Vasudevan Nair', 'read');
    await book('e3', 'Ente Katha', 'Kamala Das', 'pending');
    // One personal shelf, holding just Randamoozham.
    await db.tagsDao.insertTag(
      PersonalTagsCompanion.insert(id: 'tag1', userId: 'u1', name: 'Classics'),
    );
    await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
      id: 'a1',
      userId: 'u1',
      libraryEntryId: 'le-e2',
      tagId: 'tag1',
    ));
  });

  Widget wrap() {
    final router = GoRouter(
      initialLocation: '/library',
      routes: [
        GoRoute(path: '/library', builder: (_, _) => const LibraryGridScreen()),
        GoRoute(path: '/search', builder: (_, _) => const Scaffold(body: Text('search'))),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(_FakeApiClient()),
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

  /// Real Drift queries resolve on the real event loop, which fake-async test
  /// time never advances — interleave runAsync with timed pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> flushTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets('shelves view lists built-in and personal shelves; a tile opens its books',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await settle(tester);

    // Starts on the flat grid; the toggle offers the shelves face.
    expect(find.text('My Library'), findsOneWidget);
    await tester.tap(find.text('Shelves'));
    await settle(tester);

    // Built-ins from real state: one reading, one to-read, one read, one
    // favourite — plus the personal shelf and the door to a new one.
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('To read'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Classics'), findsOneWidget);
    expect(find.text('New shelf'), findsOneWidget);

    // Open the personal shelf: heading becomes the shelf, list narrows to it.
    await tester.tap(find.text('Classics'));
    await settle(tester);
    expect(find.text('1 book'), findsOneWidget);
    expect(find.text('My Library'), findsNothing);
    // Only Randamoozham's cover remains (its title renders on the typeset cover).
    expect(find.textContaining('Khasakkinte'), findsNothing);

    // Back returns to the shelves overview, filter cleared.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('Classics'), findsOneWidget);

    await flushTree(tester);
  });

  testWidgets('a Library footer tap resets from an opened shelf to a fresh All books',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await settle(tester);

    // Drill into the shelves view and open a shelf.
    await tester.tap(find.text('Shelves'));
    await settle(tester);
    await tester.tap(find.text('Classics'));
    await settle(tester);
    expect(find.text('1 book'), findsOneWidget); // an opened shelf, not the grid
    expect(find.text('All books'), findsNothing);

    // Tapping the Library footer tab bumps this — the screen must land back on
    // the fresh "All books" grid, not the shelf it was left on.
    final container = ProviderScope.containerOf(tester.element(find.byType(LibraryGridScreen)));
    container.read(libraryTabResetProvider.notifier).state++;
    await settle(tester);

    expect(find.text('My Library'), findsOneWidget);
    expect(find.text('All books'), findsOneWidget); // the grid's view toggle is back
    expect(find.text('1 book'), findsNothing); // the shelf is closed

    await flushTree(tester);
  });

  testWidgets('the floating control fans out into Search / Filter / Sort', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await settle(tester);

    // Collapsed: one tune circle; no labels on screen.
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.text('Sort'), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Sort'), findsOneWidget);

    // Sort opens its sheet with the three orders, current one checked.
    await tester.tap(find.text('Sort'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Title A–Z'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    await tester.tap(find.text('Title A–Z'));
    await tester.pumpAndSettle();

    await flushTree(tester);
  });

  testWidgets('the filter sheet gained a Shelf row with the personal shelves', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('SHELF'), findsOneWidget);
    // Narrow to the shelf: the live count drops to its one book.
    await tester.tap(find.text('Classics'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Show 1'), findsOneWidget);

    await flushTree(tester);
  });

  // A host with a button that opens one of the shelf sheets — the sheets need
  // a Navigator/Overlay, and testing them directly beats driving the whole
  // book page.
  Widget host(void Function(BuildContext) onTap) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(_FakeApiClient()),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(onPressed: () => onTap(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
  }

  Future<List<LibraryEntryTag>> tagsOf(WidgetTester tester, String entryId) async {
    return (await tester.runAsync(() => db.tagsDao.watchForEntry(entryId).first))!;
  }

  testWidgets('the book shelf picker is single-select, exclusive, and closes on pick',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // e1 starts on a second shelf, 'Loved'.
    await tester.runAsync(() async {
      await db.tagsDao.insertTag(
        PersonalTagsCompanion.insert(id: 'tag2', userId: 'u1', name: 'Loved'),
      );
      await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
        id: 'a2', userId: 'u1', libraryEntryId: 'le-e1', tagId: 'tag2',
      ));
    });

    await tester.pumpWidget(host((c) => showShelfPickerSheet(c, entryId: 'le-e1')));
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);

    // The reader's real shelves are offered (this is the fix — the old dialog
    // never showed them).
    expect(find.text('Add to a shelf'), findsOneWidget);
    expect(find.text('Classics'), findsOneWidget);
    expect((await tagsOf(tester, 'le-e1')).map((t) => t.tagId), contains('tag2'));

    // Picking a shelf moves the book there exclusively (drops 'Loved') and
    // closes the sheet at once — one book, one shelf.
    await tester.tap(find.text('Classics'));
    await settle(tester);
    expect(find.text('Add to a shelf'), findsNothing);
    final tags = (await tagsOf(tester, 'le-e1')).map((t) => t.tagId).toList();
    expect(tags, contains('tag1'));
    expect(tags, isNot(contains('tag2')));

    await flushTree(tester);
  });

  testWidgets('add-books-to-shelf shelves an existing library book', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host((c) => showAddBooksToShelfSheet(c, tagId: 'tag1', shelfName: 'Classics')),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);

    // Titled for the shelf; every library book is listed (Randamoozham/le-e2 is
    // already on it, the others are not).
    expect(find.text('Add to Classics'), findsOneWidget);
    // Title shows twice per row (once on the typeset cover, once as the tile
    // title), so both point at the one ListTile.
    expect(find.widgetWithText(ListTile, 'Khasakkinte Itihasam'), findsWidgets);
    expect(await tagsOf(tester, 'le-e1'), isEmpty);

    // Tap a not-yet-shelved book to shelve it.
    await tester.tap(find.widgetWithText(ListTile, 'Khasakkinte Itihasam').first);
    await settle(tester);
    expect((await tagsOf(tester, 'le-e1')).where((t) => t.tagId == 'tag1').length, 1);

    await flushTree(tester);
  });

  testWidgets('add-books search filters the library and shows each book\'s shelves',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // e1 (Khasakkinte) sits on a second shelf 'Loved' — so the picker for
    // 'Classics' can show where a book already lives.
    await tester.runAsync(() async {
      await db.tagsDao.insertTag(
        PersonalTagsCompanion.insert(id: 'tag2', userId: 'u1', name: 'Loved'),
      );
      await db.tagsDao.insertAssignment(LibraryEntryTagsCompanion.insert(
        id: 'a2', userId: 'u1', libraryEntryId: 'le-e1', tagId: 'tag2',
      ));
    });

    await tester.pumpWidget(
      host((c) => showAddBooksToShelfSheet(c, tagId: 'tag1', shelfName: 'Classics')),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);

    // Khasakkinte's row surfaces its current shelf, 'Loved'.
    expect(find.text('Loved'), findsOneWidget);

    // Searching narrows the library to the match; the others drop out.
    await tester.enterText(find.byType(TextField), 'Rand');
    await settle(tester);
    expect(find.widgetWithText(ListTile, 'Randamoozham'), findsWidgets);
    expect(find.textContaining('Khasakkinte'), findsNothing);
    expect(find.text('Loved'), findsNothing);

    await flushTree(tester);
  });

  testWidgets('add-books nudges to the catalogue when the library has no match',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host((c) => showAddBooksToShelfSheet(c, tagId: 'tag1', shelfName: 'Classics')),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);

    // A search that matches nothing in the library explains why and points at
    // the catalogue, rather than a bare "no matches".
    await tester.enterText(find.byType(TextField), 'zzznothere');
    await settle(tester);
    expect(find.text('Not in your library'), findsOneWidget);
    expect(find.text('Browse the catalogue'), findsOneWidget);

    await flushTree(tester);
  });
}
