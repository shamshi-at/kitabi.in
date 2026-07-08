import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/features/connections/connections_providers.dart';
import 'package:kitabi/features/lending/presentation/lending_ledger_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Seeds a book + entry so a lending record can join through to its cover.
Future<void> _seedBook(AppDatabase db, {String edition = 'ed1', String entry = 'le1'}) async {
  await db.cachedBooksDao.upsert(
    CachedBooksCompanion.insert(
      editionId: edition,
      workId: 'w1',
      title: 'Wuthering Heights',
      authorNames: 'Emily Brontë',
    ),
  );
  await db.libraryEntriesDao.insertOne(
    LibraryEntriesCompanion.insert(id: entry, userId: 'u1', editionId: edition),
  );
}

void main() {
  // Data-layer behaviour is exercised with plain tests (no widget binding), so
  // the live Drift stream never trips the widget-test "pending timer" invariant.
  test('watchAllActive joins each lending record to its book, newest first', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedBook(db);

    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: 'lr1',
        userId: 'u1',
        libraryEntryId: const Value('le1'),
        borrowerName: 'Anu',
        lentDate: DateTime(2026, 6, 2),
      ),
    );
    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: 'lr2',
        userId: 'u1',
        libraryEntryId: const Value('le1'),
        borrowerName: 'Divya',
        lentDate: DateTime(2026, 1, 2),
        returnedDate: Value(DateTime(2026, 2, 9)),
      ),
    );

    final rows = await db.lendingRecordsDao.watchAllActive().first;
    expect(rows, hasLength(2));
    expect(rows.first.record.id, 'lr1'); // newest lent first
    expect(rows.first.book?.title, 'Wuthering Heights');
    expect(rows.where((r) => r.record.returnedDate == null), hasLength(1)); // out now
    expect(rows.where((r) => r.record.returnedDate != null), hasLength(1)); // returned
  });

  test('markReturned closes the record so it leaves the out-now set', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    await _seedBook(db);
    final repo = LendingRepository(db, session);

    final id = await repo.lendOut('le1', borrowerName: 'Faisal', lentDate: DateTime(2026, 5, 18));
    var rows = await db.lendingRecordsDao.watchAllActive().first;
    expect(rows.single.record.returnedDate, isNull);

    await repo.markReturned(id, DateTime(2026, 6, 1));
    rows = await db.lendingRecordsDao.watchAllActive().first;
    expect(rows.single.record.returnedDate, DateTime(2026, 6, 1));

    // The mutation also enqueues a sync op (update).
    final pending = await db.syncQueueDao.pending(limit: 10);
    expect(pending.any((op) => op.entity == 'lending_records' && op.opType == 'update'), isTrue);
  });

  test('lendOut persists a trimmed note and enqueues it', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    await _seedBook(db);
    final repo = LendingRepository(db, session);

    final id = await repo.lendOut(
      'le1',
      borrowerName: 'Anu',
      lentDate: DateTime(2026, 6, 2),
      note: '  signed first edition ',
    );

    final rows = await db.lendingRecordsDao.watchAllActive().first;
    expect(rows.firstWhere((r) => r.record.id == id).record.note, 'signed first edition');

    final pending = await db.syncQueueDao.pending(limit: 10);
    final op = pending.firstWhere((o) => o.entity == 'lending_records');
    expect(op.payload.contains('signed first edition'), isTrue);
  });

  test('logBorrowed records a borrowed row carried by editionId, no library entry', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const session = SessionContext(userId: 'u1', deviceId: 'd1');
    // A borrowed book isn't owned — cache it, but create no library entry.
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: 'ed9',
        workId: 'w9',
        title: 'Aarachar',
        authorNames: 'K.R. Meera',
      ),
    );
    final repo = LendingRepository(db, session);

    final id = await repo.logBorrowed(
      editionId: 'ed9',
      lenderName: 'Divya',
      borrowedDate: DateTime(2026, 7, 2),
      note: 'careful',
    );

    final rows = await db.lendingRecordsDao.watchAllActive().first;
    final rec = rows.firstWhere((r) => r.record.id == id);
    expect(rec.record.direction, 'borrowed');
    expect(rec.record.libraryEntryId, isNull);
    expect(rec.record.editionId, 'ed9');
    expect(rec.record.note, 'careful');
    expect(rec.book?.title, 'Aarachar'); // joined via editionId, not a library entry

    final pending = await db.syncQueueDao.pending(limit: 10);
    final op = pending.firstWhere((o) => o.entity == 'lending_records');
    expect(op.opType, 'create');
  });

  // The screen render is tested against a fixed stream (not a live Drift query),
  // keeping the widget test deterministic and timer-free.
  testWidgets('ledger screen renders out-now and returned sections with stamps', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Drift's async I/O must run outside the widget-test fake-async zone, so all
    // DB work happens in runAsync; the screen then sees a plain closed stream.
    final data = await tester.runAsync(() async {
      await _seedBook(db);
      await db.lendingRecordsDao.insertOne(
        LendingRecordsCompanion.insert(
          id: 'lr1',
          userId: 'u1',
          libraryEntryId: const Value('le1'),
          borrowerName: 'Anu',
          lentDate: DateTime(2026, 6, 2),
          dueDate: Value(DateTime.now().add(const Duration(days: 3))),
        ),
      );
      await db.lendingRecordsDao.insertOne(
        LendingRecordsCompanion.insert(
          id: 'lr2',
          userId: 'u1',
          libraryEntryId: const Value('le1'),
          borrowerName: 'Divya',
          lentDate: DateTime(2026, 1, 2),
          returnedDate: Value(DateTime(2026, 2, 9)),
        ),
      );
      // One returned borrow: the Borrowed tab must count ACTIVE only (0),
      // not history — a returned book isn't "borrowed" anymore.
      await db.lendingRecordsDao.insertOne(
        LendingRecordsCompanion.insert(
          id: 'lr3',
          userId: 'u1',
          direction: const Value('borrowed'),
          editionId: const Value('ed1'),
          borrowerName: 'Meera',
          lentDate: DateTime(2026, 3, 1),
          returnedDate: Value(DateTime(2026, 4, 1)),
        ),
      );
      return db.lendingRecordsDao.watchAllActive().first;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allLendingProvider.overrideWith((ref) => Stream.value(data!)),
          // The ledger now watches connections for the inbox badge; stub it so
          // the real Dio client doesn't leave a pending timer after teardown.
          connectionsProvider.overrideWith(
            (ref) async => ConnectionsData(incoming: [], outgoing: [], accepted: []),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LendingLedgerScreen(),
        ),
      ),
    );
    // pump (not pumpAndSettle): deliver the stream value to move loading -> data.
    // pumpAndSettle would spin forever on the loading spinner's animation.
    await tester.pump();
    await tester.pump();

    expect(find.text('Wuthering Heights'), findsWidgets);
    // The borrower name is now its own tappable "door" (PersonLink) beside a
    // "to" fragment, not part of one subtitle string.
    expect(find.text('Anu'), findsOneWidget);
    expect(find.text('Divya'), findsOneWidget);
    expect(find.text('Due in 3d'), findsOneWidget);
    expect(find.text('Mark returned ✓'), findsOneWidget);
    expect(find.text('Returned ✓'), findsOneWidget);

    // Tab counts are active loans only: one book out, and the returned
    // borrow does NOT count as borrowed (the reported bug).
    expect(find.text('Lent out · 1'), findsOneWidget);
    expect(find.text('Borrowed · 0'), findsOneWidget);
    // The at-a-glance summary chip for the one active loan.
    expect(find.text('1 out'), findsOneWidget);
  });
}
