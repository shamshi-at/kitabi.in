import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/catalog/presentation/browse_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The wishlist badge on the Browse grid (owner report, 14 Oct 2026: "I can't
/// find the wishlist icon" — it was only on the list rows, and Browse is a
/// grid). It mirrors the "＋" badge: top-left where "＋" is top-right.

const _work = {
  'id': 'w-1',
  'title': '400 Days',
  'aggregate_rating': null,
  'authors': [
    {'id': 'a-1', 'name': 'Chetan Bhagat'},
  ],
  'edition': {'id': 'e-1', 'cover_url': null},
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

  Future<void> pump(WidgetTester t, LibraryEntry? entry) async {
    final original = reportTestException;
    reportTestException = (details, description) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      original(details, description);
    };
    await t.pumpWidget(
      ProviderScope(
        key: ValueKey(entry?.status),
        overrides: [
          libraryEntryProvider(
            'e-1',
          ).overrideWith((ref) => Stream.value(entry)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 220,
                child: CatalogGridCell(work: _work),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    reportTestException = original;
  }

  testWidgets(
    'not on any shelf: a bookmark top-left, mirroring the ＋ top-right',
    (t) async {
      await pump(t, null);
      final bookmark = find.byIcon(Icons.bookmark_add_outlined);
      final plus = find.byIcon(Icons.add);
      expect(bookmark, findsOneWidget);
      expect(plus, findsOneWidget);
      expect(t.getCenter(bookmark).dx, lessThan(t.getCenter(plus).dx));
      expect(t.getCenter(bookmark).dy, closeTo(t.getCenter(plus).dy, 0.5));
    },
  );

  testWidgets('wishlisted: a filled bookmark', (t) async {
    await pump(t, _entry('wishlist'));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
  });

  testWidgets('already on a shelf: no bookmark, the check speaks for it', (
    t,
  ) async {
    await pump(t, _entry('reading'));
    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
