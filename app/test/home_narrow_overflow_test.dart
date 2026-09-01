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

/// Home's goal slip and username card each set a big glyph beside a label in a
/// baseline [Row]. The label was a bare [Text], so it took its natural width
/// and the Row had nothing to give: on a 320dp phone at a 1.5x font scale the
/// goal slip striped over itself and clipped "…books this ye" (reproduced on
/// the emulator, 2 Sep 2026 — NOT reproducible at 411dp, which is why no
/// existing test at the default 800x600 surface ever saw it).
///
/// The narrow surface alone is enough to fail this in the test font; the text
/// scaler is what makes it fail on a real device too. Both are set so the test
/// keeps its teeth whichever font the harness picks up.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('Home lays out on a 320dp phone at a 1.5x font scale', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);

    // Never closed: db.close() deadlocks between the fake-async test zone and
    // drift's event loop (see home_dashboard_test.dart).
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final entries = await tester.runAsync(() async {
      for (final (edition, title) in [('e1', 'Chemmeen'), ('e2', 'കയർ'), ('e3', 'Aarachar')]) {
        await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
          editionId: edition, workId: 'w-$edition', title: title, authorNames: 'An Author'));
      }
      // Two finished this year, so the goal slip renders its hero number —
      // the `read > 0` branch is the one that overflowed.
      for (final (id, ed) in [('1', 'e1'), ('2', 'e2'), ('3', 'e3')]) {
        await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
          id: id, userId: 'u1', editionId: ed, status: const Value('read')));
      }
      return db.libraryEntriesDao.watchActive().first;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
            (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1')),
        syncTriggerProvider.overrideWithValue(() {}),
        libraryEntriesProvider.overrideWith((ref) => Stream.value(entries!)),
        allLendingProvider.overrideWith((ref) => Stream.value(const <LendingWithBook>[])),
        recsOptInProvider.overrideWith((ref) async => false),
        // No `username` key → the claim-your-username card renders too.
        meProvider.overrideWith((ref) async => {'full_name': 'Asha Menon'}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    ));
    await settle(tester);

    final overflow = tester.takeException();

    // Unmount inside the test body: disposing the ProviderScope makes drift
    // schedule a zero-duration timer as it closes its query streams, and a
    // timer still pending at teardown trips the binding's own invariant. Let
    // it fire here, where the settle pumps can drain it.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);

    // Restored inside the body, not via addTearDown — the binding asserts the
    // hook is back to its default before the test body returns.
    reportTestException = reportOriginal;

    expect(overflow, isNull,
        reason: 'Home overflowed on a narrow phone at an accessible font scale');
  });
}
