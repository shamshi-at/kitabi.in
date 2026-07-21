import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/features/library/stop_session_flow.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _editionId = '44444444-4444-4444-4444-444444444444';

class _FakeApi extends ApiClient {}

/// A stand-in for the persistent mini-bar: a child that the parent *only*
/// renders while a session is live, so stopping unmounts it — and with it the
/// `ref` quickStopSession was called with. This is the exact lifecycle that
/// silently dropped the page a reader typed while stopping from the mini-bar
/// (owner report, 19 Jul 2026).
class _FakeMiniBar extends ConsumerWidget {
  const _FakeMiniBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () => quickStopSession(context, ref),
      child: const Text('stop'),
    );
  }
}

class _Host extends ConsumerWidget {
  const _Host({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => ref.read(activeSessionProvider.notifier).start(entryId),
            child: const Text('start'),
          ),
          if (active != null) const _FakeMiniBar(),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('quick-stop from a caller that unmounts still saves the page', (tester) async {
    // The stop sheet shows the book's cover, and TypesetCover typesets its
    // fallback in Fraunces — runAsync surfaces google_fonts' async font-miss.
    // Cosmetic, filter it (same setup as catalog_screens_test.dart).
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    // Never closed: db.close() deadlocks between the fake-async zone and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId, workId: 'w', title: 'T', authorNames: 'A',
        pageCount: const Value(200),
      ));
      return id;
    });

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(_FakeApi()),
        sessionContextProvider.overrideWith((ref) async => session),
        syncTriggerProvider.overrideWithValue(() {}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Host(entryId: entryId!),
      ),
    ));
    await settle();

    // Start a session → the mini-bar appears.
    await tester.tap(find.text('start'));
    await settle();
    expect(find.text('stop'), findsOneWidget);

    // Stop → the mini-bar unmounts, the quick-stop sheet opens.
    await tester.tap(find.text('stop'));
    await settle();
    expect(find.text('stop'), findsNothing); // the caller is gone
    expect(find.byType(TextField), findsWidgets); // the page sheet is up

    // Type the page reached (the big numeral is the first field) and save.
    await tester.enterText(find.byType(TextField).first, '42');
    await tester.tap(find.text('Save the page'));
    await settle();

    // The page must have landed on the entry even though the caller unmounted.
    final entry = await tester.runAsync(() => db.libraryEntriesDao.getById(entryId));
    expect(entry?.currentPage, 42);

    await tester.pumpWidget(const SizedBox());
    await settle();

    // Restore inline, not in a tearDown — the binding asserts the hook is back
    // to its original value at the end of the test *body*.
    reportTestException = reportOriginal;
  });
}
