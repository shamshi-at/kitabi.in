import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/core/theme/app_theme.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/catalog/presentation/isbn_scan_screen.dart';
import 'package:kitabi/features/catalog/work_editions.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The scan result (docs/scan-result-mockups.html, direction B).
///
/// These drive the result views directly rather than the screen: the camera
/// can't be pointed at anything in a widget test, and the three complaints
/// this rebuild answers — the result doesn't announce itself, there's no way
/// into the book, "Add" names nothing — are all about what the result *shows*.
///
/// The work carries two printings deliberately, with the scanned one second:
/// `editions.first` is the exact wrong answer (CLAUDE.md, 13 Aug 2026).
const _work = {
  'id': 'w1',
  'title': 'One Indian Girl',
  'language': 'English',
  'form': 'Novel',
  'first_publish_year': 2016,
  'aggregate_rating': 3.9,
  'description': 'A banker’s wedding week, told against everything she has been told to want.',
  'authors': [
    {'id': 'a1', 'name': 'Chetan Bhagat'}
  ],
  'genres': [
    {'id': 'g1', 'name': 'Fiction'}
  ],
  'scanned_edition_id': 'e2',
  'translations': [
    {
      'id': 'w2',
      'title': 'വൺ ഇന്ത്യൻ ഗേൾ',
      'authors': <Map<String, dynamic>>[],
      'edition': {'id': 'e9', 'language': 'Malayalam'},
    }
  ],
  'editions': [
    {
      'id': 'e1',
      'isbn': '9788129148889',
      'page_count': 264,
      'pub_date': '2018-01-01',
      'publisher': {'name': 'Rupa'},
    },
    {
      'id': 'e2',
      'isbn': '9788129142146',
      'page_count': 280,
      'pub_date': '2016-05-01',
      'format': 'Paperback',
      'publisher': {'name': 'Rupa'},
    },
  ],
};

LibraryEntry _entry({String status = 'reading', int? currentPage}) {
  final stamp = DateTime(2026, 8, 1);
  return LibraryEntry(
    id: 'le1',
    userId: 'u1',
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    editionId: 'e2',
    status: status,
    ownership: 'owned',
    startDate: null,
    finishDate: null,
    currentPage: currentPage,
    isFavorite: false,
    notes: null,
  );
}

Future<void> _pump(WidgetTester tester, Widget view, {bool dark = false}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(430, 940);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // buildAppTheme sets the global AppColors.dark, so put it back afterwards.
  addTearDown(() => buildAppTheme(dark: false));
  final theme = buildAppTheme(dark: dark);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      // The result is a book page, not a camera — paper, like the rest of
      // the app (docs/scan-result-mockups.html, Round 2).
      backgroundColor: AppColors.paper,
      body: SafeArea(child: view),
    ),
  ));
  await tester.pump();
}

Future<void> _pumpFound(
  WidgetTester tester, {
  Map<String, dynamic>? edition,
  LibraryEntry? existing,
  bool picking = false,
  bool returnResult = false,
  bool dark = false,
  void Function(Map<String, dynamic>)? onChoose,
  VoidCallback? onOpenBook,
}) =>
    _pump(
      tester,
      ScanFoundView(
        work: _work,
        edition: edition ?? scannedEdition(_work),
        existing: existing,
        detectedIsbn: '9788129142146',
        picking: picking,
        busy: false,
        returnResult: returnResult,
        onPick: () {},
        onChoose: onChoose ?? (_) {},
        onAdd: () async {},
        onWishlist: () async {},
        onUseDetails: () {},
        onOpenBook: onOpenBook ?? () {},
        onOpenOwned: () {},
        onScanAgain: () {},
      ),
      dark: dark,
    );

void main() {
  testWidgets('the result names the printing the barcode resolved to', (tester) async {
    await _pumpFound(tester);

    // The 2016 reprint is what the barcode belongs to; the 2018 printing is
    // what `editions.first` would have shelved.
    expect(find.text('THE PRINTING YOU SCANNED'), findsOneWidget);
    expect(find.text('Rupa · 2016 · 280 pp · Paperback'), findsOneWidget);
    expect(find.text('Rupa · 2018 · 264 pp'), findsNothing);
    // …and the other one is a door, not a secret.
    expect(find.text('1 other'), findsOneWidget);
  });

  testWidgets('the scan announces itself and shows the book, not a strip', (tester) async {
    await _pumpFound(tester);

    expect(find.text('GOT IT · 2 PRINTINGS'), findsOneWidget);
    // Twice: the typeset cover letters the title as art, then the heading.
    expect(find.text('One Indian Girl'), findsWidgets);
    expect(find.text('Chetan Bhagat'), findsOneWidget);
    expect(find.text('Novel · English · 2016'), findsOneWidget);
    expect(find.textContaining('wedding week'), findsOneWidget);
    expect(find.text('Fiction'), findsOneWidget);
    expect(find.text('ISBN 9788129142146'), findsOneWidget);
    // The wedge, from the payload the lookup already returned.
    expect(find.text('Translated into Malayalam'), findsOneWidget);
  });

  testWidgets('the primary names its object — "Add" alone is gone', (tester) async {
    await _pumpFound(tester);

    expect(find.text('Add to my library'), findsOneWidget);
    // The old confirm card's whole label. On a screen titled "Add a book"
    // whose other button adds to the shared catalogue, it meant nothing.
    expect(find.text('Add'), findsNothing);
    // Want vs. have: the contrast is what makes the primary unambiguous.
    expect(find.text('Wishlist'), findsOneWidget);
  });

  testWidgets('the result is a door into the book', (tester) async {
    var opened = false;
    await _pumpFound(tester, onOpenBook: () => opened = true);

    await tester.tap(find.text('Open the full book page'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('the printings open in place, marked and pickable', (tester) async {
    Map<String, dynamic>? chosen;
    await _pumpFound(tester, picking: true, onChoose: (edition) => chosen = edition);

    expect(find.text('WHICH ONE IS IN YOUR HAND?'), findsOneWidget);
    expect(find.text('the barcode you scanned'), findsOneWidget);
    expect(find.textContaining('Page counts differ'), findsOneWidget);
    // While the choice is open, the primary names the choice.
    expect(find.text('Add this printing'), findsOneWidget);
    expect(find.text('Add to my library'), findsNothing);

    await tester.tap(find.text('Rupa · 2018 · 264 pp'));
    await tester.pump();
    expect(chosen?['id'], 'e1');
  });

  testWidgets('a book already on the shelf answers with where you left it', (tester) async {
    await _pumpFound(tester, existing: _entry(currentPage: 88));

    expect(find.text('ALREADY ON YOUR SHELF'), findsOneWidget);
    expect(find.text('READING'), findsOneWidget);
    expect(find.text('p. 88 of 280 · 31%'), findsOneWidget);
    // It stops claiming to add anything — the offer becomes a door.
    expect(find.text('Open it'), findsOneWidget);
    expect(find.text('Add to my library'), findsNothing);
    expect(find.text('Wishlist'), findsNothing);
  });

  testWidgets('form mode carries the details back, never the shelf', (tester) async {
    await _pumpFound(tester, returnResult: true);

    expect(find.text('Use these details'), findsOneWidget);
    expect(find.text('Add to my library'), findsNothing);
    expect(find.text('Wishlist'), findsNothing);
    // No door either: it would push the book page — whose own button shelves
    // the book — on top of the half-filled add form this scan came from.
    expect(find.text('Open the full book page'), findsNothing);
    // Still the same object: the printing is still named.
    expect(find.text('THE PRINTING YOU SCANNED'), findsOneWidget);
  });

  testWidgets('a miss says why, and says the ISBN is already captured', (tester) async {
    var added = false;
    await _pump(
      tester,
      ScanMissView(
        isbn: '9789352994412',
        returnResult: false,
        onAdd: () => added = true,
        onSearch: () {},
        onScanAgain: () {},
      ),
    );

    expect(find.text('NOT FOUND'), findsOneWidget);
    expect(find.text('Nothing catalogued for this barcode'), findsOneWidget);
    expect(find.text('9789352994412'), findsOneWidget);
    expect(find.textContaining('OpenLibrary'), findsOneWidget);
    expect(find.textContaining('first to add it'), findsOneWidget);
    expect(find.textContaining("won't retype it"), findsOneWidget);

    await tester.tap(find.text('Add this book'));
    await tester.pump();
    expect(added, isTrue);
  });

  testWidgets('a failed lookup is not a miss — it never invites a duplicate', (tester) async {
    await _pump(
      tester,
      ScanFailedView(
        onRetry: () async {},
        onScanAgain: () {},
        onTypeItIn: () {},
      ),
    );

    expect(find.text("Couldn't reach the catalogue"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The one thing an offline moment must never say.
    expect(find.textContaining('first to add it'), findsNothing);
    expect(find.text('Nothing catalogued for this barcode'), findsNothing);
  });

  testWidgets('the result wears the app theme, light and dark', (tester) async {
    // The scanner used to be the one screen with a private palette, so it
    // ignored the reader's light/dark setting entirely. Only the camera keeps
    // the night theme now; the result is a book page like any other.
    Color? metaColour() =>
        tester.widget<Text>(find.text('Novel · English · 2016')).style?.color;

    await _pumpFound(tester);
    final light = metaColour();
    expect(light, AppColors.inkSoft);

    await _pumpFound(tester, dark: true);
    final dark = metaColour();
    expect(dark, AppColors.inkSoft);
    expect(dark, isNot(light), reason: 'the token must resolve per theme, not be a constant');
  });
}
