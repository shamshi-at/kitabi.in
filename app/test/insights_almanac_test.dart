import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/presentation/almanac_widgets.dart';
import 'package:kitabi/features/insights/presentation/insights_screen.dart';
import 'package:kitabi/features/insights/providers/insights_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The almanac Insights page (Direction B). Rendering-level coverage: the
/// ledger rows and their values, the In hand section, and the wax seal's
/// honest-state rule (drawn only when the window holds something true).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  ReadingSession session(
    DateTime startedAt, {
    required String entryId,
    int durationSeconds = 1800,
  }) {
    return ReadingSession(
      id: 'id-${startedAt.microsecondsSinceEpoch}-$entryId',
      userId: 'u1',
      createdAt: startedAt,
      updatedAt: startedAt,
      deletedAt: null,
      syncStatus: 'synced',
      lastSyncedAt: null,
      serverSeq: null,
      libraryEntryId: entryId,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSeconds)),
      durationSeconds: durationSeconds,
      pageStart: null,
      pageEnd: null,
      autoStopped: false,
    );
  }

  Future<List<LibraryHit>> seededHits(WidgetTester tester, AppDatabase db) async {
    return (await tester.runAsync(() async {
      for (final (ed, title, pages) in [('e1', 'Naalukettu', 384), ('e2', 'Aarachar', 724)]) {
        await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
          editionId: ed,
          workId: 'w-$ed',
          title: title,
          authorNames: 'An Author',
          pageCount: Value(pages),
        ));
        await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
          id: 'le-$ed',
          userId: 'u1',
          editionId: ed,
          status: const Value('reading'),
          currentPage: const Value(120),
        ));
      }
      return db.libraryEntriesDao.allWithBooks();
    }))!;
  }

  Widget app(List<LibraryHit> hits, List<ReadingSession> sessions) {
    return ProviderScope(
      overrides: [
        libraryWithBooksProvider.overrideWith((ref) => Stream.value(hits)),
        readingSessionsStreamProvider.overrideWith((ref) => Stream.value(sessions)),
        ratingsByWorkIdProvider.overrideWith((ref) => Stream.value(const <String, int>{})),
        readingGoalProvider.overrideWith((ref) async => 30),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: InsightsScreen(),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a day with two books renders the ledger, the In hand section, and the seal',
      (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    // Never closed: db.close() deadlocks between the fake-async test zone
    // and drift's event loop; the in-memory db just gets GC'd.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final hits = await seededHits(tester, db);
    final today = DateTime.now();
    final sessions = [
      session(DateTime(today.year, today.month, today.day, 8), entryId: 'le-e1'),
      session(DateTime(today.year, today.month, today.day, 20),
          entryId: 'le-e2', durationSeconds: 600),
    ];

    await tester.pumpWidget(app(hits, sessions));
    await settle(tester);

    // The ledger rows, with the day's totals.
    expect(find.text('Time read'), findsOneWidget);
    expect(find.text('40m'), findsOneWidget); // 1800s + 600s
    expect(find.text('Sittings'), findsOneWidget);

    // Two books in hand → the section, one titled row per book, titles as
    // doors (rendered; navigation is the router's test, not this one's).
    expect(find.text('IN HAND · 2 BOOKS'), findsOneWidget);
    expect(find.text('Naalukettu'), findsOneWidget);
    expect(find.text('Aarachar'), findsOneWidget);

    // Something true to send → the seal is drawn.
    expect(find.byType(WaxSeal), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });

  testWidgets('an empty today draws no seal and no shareable zero', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final hits = await seededHits(tester, db);

    await tester.pumpWidget(app(hits, const []));
    await settle(tester);

    // The nudge headline, not a zero — and no send affordance at all.
    expect(find.textContaining('No sitting yet today'), findsOneWidget);
    expect(find.byType(WaxSeal), findsNothing);
    expect(find.text('Time read'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    reportTestException = reportOriginal;
  });
}
