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

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
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
    await settle(until: find.byType(TextField));
    expect(find.text('stop'), findsNothing); // the caller is gone
    expect(find.byType(TextField), findsWidgets); // the page sheet is up

    // Type the page reached (the big numeral is the first field) and save.
    // The pump between typing and tapping matters: with an empty sheet "Save
    // the page" is disabled (Skip is the exit), and it re-enables on the
    // frame after the first digit lands.
    await tester.enterText(find.byType(TextField).first, '42');
    await settle();
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

  testWidgets('the page sheet still opens when the caller unmounts mid-flow',
      (tester) async {
    // The test above passes by timing luck: stop() only *schedules* the
    // rebuild that removes the caller, so `context.mounted` is still true when
    // the flow checks it. On a device the database reads take long enough for
    // that frame to land first, and the flow then returned silently — the page
    // question simply never appeared (owner report, 31 Jul 2026, "sometimes").
    // Pumping one frame right after the tap makes that ordering deterministic.
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

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

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
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

    await tester.tap(find.text('start'));
    await settle();
    expect(find.text('stop'), findsOneWidget);

    await tester.tap(find.text('stop'));
    await tester.pump(); // ← the caller unmounts here, while the reads are open
    expect(find.text('stop'), findsNothing, reason: 'the caller is already gone');
    await settle(until: find.byType(TextField));

    expect(find.byType(TextField), findsWidgets,
        reason: 'the page question must survive the caller that asked for it');

    // Flush the sheet and drift's stream timers before the binding's
    // pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });

  testWidgets('a sitting that ends on the page already recorded is still logged',
      (tester) async {
    // Owner report, 26 Jul 2026: the first sitting showed "no page noted" in
    // the reading log while the progress bar showed the page. Both writes sat
    // behind one "has the page changed?" guard, so ending on the page the
    // entry already held wrote neither — and setting your page before starting
    // the clock is the normal shape of a first sitting.
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      // The reader had already noted p. 42 before starting the clock.
      await repo.updateProgress(id, currentPage: 42);
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId, workId: 'w', title: 'T', authorNames: 'A',
        pageCount: const Value(200),
      ));
      return id;
    });

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
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

    await tester.tap(find.text('start'));
    await settle();
    await tester.tap(find.text('stop'));
    await settle(until: find.text('Save the page'));

    // Save without changing the number — it is already 42.
    await tester.tap(find.text('Save the page'));
    await settle();

    final sessions = await tester.runAsync(
        () => db.readingSessionsDao.watchForEntry(entryId).first);
    expect(sessions, hasLength(1));
    expect(sessions!.single.pageEnd, 42,
        reason: 'the sitting must record where it ended, unchanged or not');

    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });

  testWidgets('a page count added after the sitting began is not asked for again',
      (tester) async {
    // Owner report, 26 Jul 2026: "despite I added the total page number, every
    // time it asks for the total when I stop reading". The sheet took its page
    // count from a pre-stop provider snapshot; the database is the answer.
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    final repo = LibraryRepository(db, session);

    final entryId = await tester.runAsync(() async {
      final id = await repo.add(editionId: _editionId);
      await repo.updateStatus(id, 'reading');
      // The catalogue does NOT know the length yet.
      await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
        editionId: _editionId, workId: 'w', title: 'T', authorNames: 'A',
      ));
      return id;
    });

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
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

    await tester.tap(find.text('start'));
    await settle();

    // The reader supplies the total while the sitting runs (from the book page,
    // the progress editor — anywhere but here).
    await tester.runAsync(() => db.cachedBooksDao.updatePageCount(_editionId, 320));

    await tester.tap(find.text('stop'));
    await settle(until: find.textContaining('320'));

    expect(find.textContaining('How long is this book'), findsNothing,
        reason: 'the catalogue knows the length — stop asking');
    expect(find.textContaining('320'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });

  testWidgets('the page field falls back to the last sitting that noted a page',
      (tester) async {
    // Owner report, 26 Jul 2026: "even though the page number was noted for the
    // last log, here page number came empty". An entry with no page of its own
    // can still have sittings that recorded where they ended.
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

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
      // A sitting from yesterday that ended on p. 88 — but the entry itself
      // carries no current page.
      final sessions = ReadingSessionsRepository(db, session);
      final sid = await sessions.logSession(
        libraryEntryId: id,
        startedAt: DateTime.now().subtract(const Duration(days: 1, minutes: 30)),
        endedAt: DateTime.now().subtract(const Duration(days: 1)),
        durationSeconds: 1800,
      );
      await sessions.updateSessionPageEnd(sid, 88);
      return id;
    });

    // Waits for asynchronous work to land. [until], when given, is the outcome
    // the next assertion is about: the loop stops as soon as it appears and
    // gives up well past the point a healthy machine needs.
    //
    // It used to be a flat 8 rounds, which is a *time budget*, not a wait — so
    // it encoded how fast this laptop happened to be. Stopping a sitting grew
    // by a few database writes and a plugin teardown, and these tests went red
    // on CI's slower runner while staying green locally (15 Aug 2026). A test
    // that asserts an outcome should wait for the outcome.
    Future<void> settle({Finder? until}) async {
      var graceLeft = 8;
      for (var i = 0; i < (until == null ? 8 : 120); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
        // The outcome appearing ends the *waiting*, not the settling: work the
        // assertion depends on can still be in flight behind it (a sheet is on
        // screen a beat before its fields are seeded). So keep going for a
        // fixed grace, which is what the flat loop gave on a fast machine.
        if (until != null && until.evaluate().isNotEmpty && --graceLeft <= 0) return;
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

    await tester.tap(find.text('start'));
    await settle();
    await tester.tap(find.text('stop'));
    await settle(until: find.text('88'));

    expect(find.text('88'), findsWidgets,
        reason: 'the last noted page is a far better answer than a blank field');

    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });
}
