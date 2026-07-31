import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/promotions_repository.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/home/presentation/home_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/features/profile/providers/profile_providers.dart';
import 'package:kitabi/features/recommendations/providers/recommendations_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// In-app promotions on Home.
///
/// The states worth pinning are the two extremes: **nothing published**, which
/// must leave Home byte-for-byte the page it was, and a live campaign, which
/// must render its label and disappear the instant it's dismissed — from the
/// database, with no network in the path.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late void Function(FlutterErrorDetails, String) reportOriginal;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  }

  CachedPromotionsCompanion banner({
    String id = 'p1',
    String? sponsor,
    bool dismissible = true,
    DateTime? expiresAt,
  }) =>
      CachedPromotionsCompanion.insert(
        id: id,
        kind: 'banner',
        placement: 'home_top',
        headline: 'Trivandrum Book Fair — 5 to 9 August',
        sponsor: Value(sponsor),
        dismissible: Value(dismissible),
        expiresAt: Value(expiresAt),
      );

  CachedPromotionsCompanion card({String id = 'c1'}) => CachedPromotionsCompanion.insert(
        id: id,
        kind: 'card',
        cardStyle: const Value('text'),
        placement: 'home_stream',
        headline: 'Kitabi is on Android now',
        body: const Value('Same library, same shelf, same lending.'),
        ctaLabel: const Value('Tell a friend'),
      );

  /// Home with a real Drift database behind it. `db` is never closed —
  /// db.close() deadlocks between the fake-async test zone and drift's loop.
  Future<AppDatabase> pumpHome(
    WidgetTester tester, {
    List<CachedPromotionsCompanion> promotions = const [],
  }) async {
    // Restored by finish(), NOT addTearDown: the binding verifies this hook is
    // back to normal at the end of the test *body*, before tearDowns run.
    reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final entries = await tester.runAsync(() async {
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: 'e1',
        workId: 'w1',
        title: 'Chemmeen',
        authorNames: 'Thakazhi',
      ));
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
            id: '1', userId: 'u1', editionId: 'e1', status: const Value('read')),
      );
      for (final promo in promotions) {
        await db.promotionsDao.replaceAll([promo]);
      }
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
          // No API in a widget test — the repository swallows the failure, so
          // the cached rows are what render. That IS the offline path.
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await settle(tester);
    return db;
  }

  testWidgets('with nothing published, Home builds no promotion widgets at all',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('FROM KITABI'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    // And the page it was still is: the shelf strip and counts are untouched.
    expect(find.text('FRESH ON YOUR SHELF'), findsOneWidget);
    expect(find.text('OWNED'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('a live banner renders with the derived "From Kitabi" label',
      (tester) async {
    await pumpHome(tester, promotions: [banner()]);
    expect(find.text('Trivandrum Book Fair — 5 to 9 August'), findsOneWidget);
    expect(find.text('FROM KITABI'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('a sponsor turns the label into "Sponsored · name"', (tester) async {
    await pumpHome(tester, promotions: [banner(sponsor: 'DC Books')]);
    // Derived from the sponsor field — never typed by the campaign author, so
    // the disclosure can't be forgotten.
    expect(find.text('SPONSORED · DC BOOKS'), findsOneWidget);
    expect(find.text('FROM KITABI'), findsNothing);

    await finish(tester);
  });

  testWidgets('dismissing removes it from Home without any network', (tester) async {
    final db = await pumpHome(tester, promotions: [banner()]);
    expect(find.text('Trivandrum Book Fair — 5 to 9 August'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);

    // Gone from the page…
    expect(find.text('Trivandrum Book Fair — 5 to 9 August'), findsNothing);
    // …and gone because the *database* says so, not because a widget hid it.
    final rows = await tester.runAsync(() => db.promotionsDao.all());
    expect(rows!.single.dismissedAt, isNotNull);
    // The dismissal is queued for the server so it holds on other devices too.
    final queued = await tester.runAsync(() => db.promotionsDao.pending());
    expect(queued!.map((e) => e.kind), contains('dismiss'));

    await finish(tester);
  });

  testWidgets('a non-dismissible promotion has no close button', (tester) async {
    await pumpHome(tester, promotions: [banner(dismissible: false)]);
    expect(find.text('Trivandrum Book Fair — 5 to 9 August'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    await finish(tester);
  });

  testWidgets('an expired campaign disappears offline, with no fetch', (tester) async {
    await pumpHome(
      tester,
      promotions: [banner(expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)))],
    );
    // expires_at rides along in the cached row precisely so a finished
    // campaign dies on the device rather than waiting for the next poll.
    expect(find.text('Trivandrum Book Fair — 5 to 9 August'), findsNothing);

    await finish(tester);
  });

  testWidgets('banner and card can both show — the maximum Home ever gets',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.promotionsDao.replaceAll([banner(), card()]);
    final rows = await db.promotionsDao.all();
    expect(rows.length, 2);
    // One per placement is enforced server-side; this pins that the two
    // placements are distinct so they can't collide into one slot.
    expect(rows.map((r) => r.placement).toSet(), {'home_top', 'home_stream'});
  });

  test('replaceAll keeps this device\'s dismissal across a refresh', () async {
    // A re-fetch must not resurrect something the reader closed: dismissedAt
    // is local memory, and the server payload has no opinion about it.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.promotionsDao.replaceAll([banner()]);
    await db.promotionsDao.markDismissed('p1', DateTime.now().toUtc());
    await db.promotionsDao.replaceAll([banner()]); // same campaign, fresh copy
    final row = await db.promotionsDao.getById('p1');
    expect(row!.dismissedAt, isNotNull);
  });

  test('replaceAll drops campaigns the server no longer sends', () async {
    // How a paused or ended campaign vanishes.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.promotionsDao.replaceAll([banner(), card()]);
    await db.promotionsDao.replaceAll([card()]);
    expect(await db.promotionsDao.getById('p1'), isNull);
    expect(await db.promotionsDao.getById('c1'), isNotNull);
  });

  test('exhausted events are dropped rather than retried forever', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.promotionsDao.enqueue(PromotionEventQueueCompanion.insert(
      id: 'e1',
      promotionId: 'p1',
      kind: 'impression',
      occurredAt: DateTime.now().toUtc(),
      attempts: const Value(PromotionsRepository.maxEventAttempts),
    ));
    await db.promotionsDao.dropExhausted(PromotionsRepository.maxEventAttempts);
    expect(await db.promotionsDao.pending(), isEmpty);
  });

  test('signing out clears campaigns and unsent events', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.promotionsDao.replaceAll([banner()]);
    await db.promotionsDao.enqueue(PromotionEventQueueCompanion.insert(
      id: 'e1',
      promotionId: 'p1',
      kind: 'impression',
      occurredAt: DateTime.now().toUtc(),
    ));
    await db.promotionsDao.clearAll();
    expect(await db.promotionsDao.all(), isEmpty);
    expect(await db.promotionsDao.pending(), isEmpty);
  });
}
