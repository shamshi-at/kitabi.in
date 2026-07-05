import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/home/presentation/home_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/features/recommendations/providers/recommendations_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

void main() {
  testWidgets('home dashboard renders shelf counts from the library', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Two read + one wishlist, no "reading" entries (keeps the render off the
    // live cachedBookProvider path, so the widget-test binding stays timer-free).
    final entries = await tester.runAsync(() async {
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
          libraryEntriesProvider.overrideWith((ref) => Stream.value(entries!)),
          allLendingProvider.overrideWith((ref) => Stream.value(const <LendingWithBook>[])),
          recsOptInProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Owned'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Lent out'), findsOneWidget);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // owned = 3 entries
    expect(find.text('2'), findsOneWidget); // read = 2
  });
}
