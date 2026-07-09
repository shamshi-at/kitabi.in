import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/home/presentation/home_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/features/profile/providers/profile_providers.dart';
import 'package:kitabi/features/recommendations/providers/recommendations_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

void main() {
  setUpAll(() {
    // The home shelf strip renders typeset covers (Fraunces) — never fetch
    // fonts in tests; the "not in assets" fallback is filtered per-test.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Drift work resolves on the real event loop; fake-zone Timer hops need
  /// *timed* pumps (see test/review_flow_test.dart for the full story).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('home dashboard renders shelf counts, cover shelf, and goal slip',
      (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    // Never closed: db.close() deadlocks between the fake-async test zone and
    // drift's event loop; a per-test in-memory db just gets GC'd.
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final entries = await tester.runAsync(() async {
      // Catalog cache rows so the cover shelf has titles to stand up.
      for (final (edition, title) in [('e1', 'Chemmeen'), ('e2', 'കയർ'), ('e3', 'Aarachar')]) {
        await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
          editionId: edition,
          workId: 'w-$edition',
          title: title,
          authorNames: 'An Author',
        ));
      }
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
            id: '1', userId: 'u1', editionId: 'e1', status: const Value('read')),
      );
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
            id: '2', userId: 'u1', editionId: 'e2', status: const Value('read')),
      );
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
            id: '3', userId: 'u1', editionId: 'e3', status: const Value('wishlist')),
      );
      return db.libraryEntriesDao.watchActive().first;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sessionContextProvider.overrideWith(
            (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
          ),
          syncTriggerProvider.overrideWithValue(() {}),
          libraryEntriesProvider.overrideWith((ref) => Stream.value(entries!)),
          allLendingProvider.overrideWith((ref) => Stream.value(const <LendingWithBook>[])),
          recsOptInProvider.overrideWith((ref) async => false),
          meProvider.overrideWith((ref) async => {'full_name': 'Shamshi K'}),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await settle(tester);

    // The personal greeting carries the reader's first name.
    expect(find.textContaining('Shamshi'), findsOneWidget);
    // Shelf counts — small-caps labels, matching the rest of Home's
    // section-label treatment (FRESH ON YOUR SHELF, READING GOAL).
    expect(find.text('OWNED'), findsOneWidget);
    expect(find.text('READ'), findsOneWidget);
    expect(find.text('LENT OUT'), findsOneWidget);
    expect(find.text('WISHLIST'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // owned = 3 entries
    expect(find.text('2'), findsOneWidget); // read = 2
    // The cover shelf strip labels and its covers (typeset titles render).
    expect(find.text('FRESH ON YOUR SHELF'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
    // The goal slip ties home to insights.
    expect(find.text('READING GOAL'), findsOneWidget);

    // Flush drift stream-close timers before the pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });
}
