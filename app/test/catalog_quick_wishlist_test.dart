import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/core/widgets/typeset_cover.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/catalog/presentation/catalog_result_tile.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The leading wishlist bookmark on catalog rows (owner request, 14 Oct 2026):
/// offered for a book that isn't on any of the reader's shelves, filled once
/// it's wishlisted, and absent — but still taking its slot — for a book they
/// already have, so every cover in a list stays on one line.

const _work = {
  'id': 'w-1',
  'title': 'Kaalam',
  'first_publish_year': 1969,
  'aggregate_rating': null,
  'authors': [
    {'id': 'a-1', 'name': 'M. T. Vasudevan Nair'},
  ],
  'edition': {'id': 'e-1', 'cover_url': null, 'publisher': null},
};

LibraryEntry _entry(String status) {
  final stamp = DateTime(2026, 10, 1);
  return LibraryEntry(
    id: 'le-1',
    userId: 'u1',
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    editionId: 'e-1',
    status: status,
    ownership: 'owned',
    startDate: null,
    finishDate: null,
    currentPage: null,
    isFavorite: false,
    circleHidden: false,
    notes: null,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, LibraryEntry? entry) async {
    await tester.pumpWidget(
      ProviderScope(
        // A fresh scope per state: overrides aren't re-read by a live one.
        key: ValueKey(entry?.status),
        overrides: [
          libraryEntryProvider(
            'e-1',
          ).overrideWith((ref) => Stream.value(entry)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CatalogResultTile(work: _work)),
        ),
      ),
    );
    // The entry stream emits on the frame after the first build.
    await tester.pump();
    await tester.pump();
  }

  double coverLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(TypesetCover)).dx;

  testWidgets('not on any shelf: a bookmark to wishlist it, beside the ＋', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
    expect(find.byTooltip('Wishlist'), findsOneWidget);
  });

  testWidgets('wishlisted: the bookmark stays, filled', (tester) async {
    await pump(tester, _entry('wishlist'));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
  });

  testWidgets('already on a shelf: no bookmark, same alignment', (
    tester,
  ) async {
    await pump(tester, null);
    final unshelved = coverLeft(tester);
    await pump(tester, _entry('reading'));
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(coverLeft(tester), unshelved);
  });
}
