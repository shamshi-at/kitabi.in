import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/presentation/browse_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The catalog bookmark is a toggle (owner request, 14 Oct 2026): one tap
/// wishlists a book that's on none of the reader's shelves, the same tap on
/// the filled bookmark takes it off again — soft-deleted and queued for sync,
/// not quietly turned into "To read" — and the snackbar can undo it. Runs the
/// real repository against an in-memory database.

const _work = {
  'id': 'w-1',
  'title': '400 Days',
  'aggregate_rating': null,
  'authors': [
    {'id': 'a-1', 'name': 'Chetan Bhagat'},
  ],
  'edition': {'id': 'e-1', 'cover_url': null},
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Drift resolves on the real event loop; fake-zone pumps need real time
  /// between them (see home_dashboard_test.dart).
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('bookmark, un-bookmark, undo', (t) async {
    final original = reportTestException;
    reportTestException = (details, description) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      original(details, description);
    };
    // Never closed: closing deadlocks between the fake-async zone and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sessionContextProvider.overrideWith(
            (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
          ),
          syncTriggerProvider.overrideWithValue(() {}),
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
    await settle(t);

    Future<List<LibraryEntry>> live() => t
        .runAsync(() => db.libraryEntriesDao.watchActive().first)
        .then((v) => v!);

    // 1. Wishlist it.
    await t.tap(find.byIcon(Icons.bookmark_add_outlined));
    await settle(t);
    var entries = await live();
    expect(entries.map((e) => e.status), ['wishlist']);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    // 2. The same icon takes it off — gone, not "To read".
    await t.tap(find.byIcon(Icons.bookmark));
    await settle(t);
    expect(await live(), isEmpty);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    expect(find.text('Off your wishlist.'), findsOneWidget);
    final ops = await t.runAsync(() => db.syncQueueDao.pending(limit: 10));
    expect(ops!.map((o) => o.opType), containsAll(['create', 'delete']));

    // 3. Undo puts it back on the wishlist.
    await t.tap(find.text('Undo'));
    await settle(t);
    entries = await live();
    expect(entries.map((e) => e.status), ['wishlist']);

    await t.pumpWidget(const SizedBox());
    await settle(t);
    reportTestException = original;
  });
}
