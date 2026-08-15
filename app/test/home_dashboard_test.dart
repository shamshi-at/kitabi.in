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
          meProvider.overrideWith((ref) async => {'full_name': 'Asha Menon'}),
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
    expect(find.textContaining('Asha'), findsOneWidget);
    // Shelf counts — small-caps labels, matching the rest of Home's
    // section-label treatment (FRESH ON YOUR SHELF, READING GOAL).
    expect(find.text('OWNED'), findsOneWidget);
    expect(find.text('READ'), findsOneWidget);
    expect(find.text('LENT OUT'), findsOneWidget);
    expect(find.text('WISHLIST'), findsOneWidget);
    // Owned excludes the wishlisted book — it's a book you don't have, and it
    // already has its own column one over (owner report, 31 Jul 2026). Three
    // "2"s: OWNED (2 of the 3 entries), the shelf READ count, and the goal
    // ring — the two read books (no finish date) count toward the goal via the
    // updatedAt fallback, where they used to be invisible to it (17 Jul 2026).
    expect(find.text('2'), findsNWidgets(3));
    expect(find.text('3'), findsNothing);
    // The cover shelf strip labels and its covers (typeset titles render).
    expect(find.text('FRESH ON YOUR SHELF'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
    // ...and the wishlisted book is not standing on that shelf.
    expect(find.text('Aarachar'), findsNothing);
    // The goal slip ties home to insights, and now reflects the finished books.
    expect(find.text('READING GOAL'), findsOneWidget);
    expect(find.textContaining('of 30 books'), findsOneWidget);

    // Flush drift stream-close timers before the pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });

  /// The claim-a-username nudge. A username is the one bit of setup nothing
  /// else in the app forces — you can shelve, read and lend for months without
  /// one, and then a friend cannot find you. Profile has always offered it;
  /// a reader with no reason to open Profile never saw the offer.
  ///
  /// Three states, because the interesting one is the third: "we have not
  /// asked yet" must not look like "no username". That conflation is what used
  /// to flash the language picker at signed-in readers (CLAUDE.md, 15 Jul
  /// 2026), and an invitation that appears on every cold start — or on a phone
  /// with no signal — reads as a bug rather than a prompt.
  Future<void> pumpHomeWithProfile(
    WidgetTester tester,
    AppDatabase db,
    Override meOverride,
  ) async {
    // A book on the shelf, because an empty library renders the "add your
    // first book" screen instead of the dashboard — and that reader is served
    // by the dot on the profile icon, not by this card.
    final entries = await tester.runAsync(() async {
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(id: '1', userId: 'u1', editionId: 'e1'),
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
          meOverride,
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('home invites a reader with no username to claim one', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await pumpHomeWithProfile(
      tester,
      db,
      meProvider.overrideWith((ref) async => {'full_name': 'Asha Menon'}),
    );

    expect(find.text('YOUR HANDLE'), findsOneWidget);
    expect(find.text('Claim your username'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('the invitation is gone once a username exists', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await pumpHomeWithProfile(
      tester,
      db,
      meProvider.overrideWith(
        (ref) async => {'full_name': 'Asha Menon', 'username': 'midnight_reader'},
      ),
    );

    expect(find.text('YOUR HANDLE'), findsNothing,
        reason: 'acting on it is the only ending this card needs');

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('a profile that never loaded shows no invitation at all', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    // Offline at cold start: /me never answers. "We have not been told" is not
    // "there is no username", and only an answer that arrived may put this on
    // screen.
    await pumpHomeWithProfile(
      tester,
      db,
      meProvider.overrideWith((ref) async => throw Exception('offline')),
    );

    expect(find.text('YOUR HANDLE'), findsNothing,
        reason: 'a prompt that appears whenever the network is down is a bug');

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });
}
