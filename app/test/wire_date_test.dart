import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/wire_date.dart';

/// A calendar date goes on the wire as the reader's *local* day. Converting to
/// UTC first sent the previous day for anything recorded between 00:00 and
/// 05:30 in IST — a book lent at 01:22 on 13 Oct was stored as lent on 12 Oct
/// for both lender and borrower (emulator, 13 Oct 2026).
///
/// Dart can't change the zone in-process, so these pick local times whose UTC
/// day differs from the local day on any host more than half an hour off UTC:
/// just after midnight bites east of UTC (IST, where this was found), just
/// before midnight bites west of it. On a UTC host both pass either way; run
/// with `TZ=Asia/Kolkata flutter test test/wire_date_test.dart` to see the
/// original failure there.
void main() {
  group('wireDate', () {
    test('is the local day just after midnight (01:22 IST is the previous UTC day)', () {
      final lentAt = DateTime(2026, 10, 13, 1, 22);
      expect(wireDate(lentAt), '2026-10-13');
    });

    test('is the local day just before midnight', () {
      expect(wireDate(DateTime(2026, 10, 13, 23, 40)), '2026-10-13');
    });

    test('is the local day of a UTC instant, not its UTC day', () {
      final instant = DateTime.utc(2026, 10, 12, 19, 52); // 01:22 on the 13th in IST
      final local = instant.toLocal();
      expect(
        wireDate(instant),
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}',
      );
    });

    test('zero-pads month and day', () {
      expect(wireDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('round-trips through the pull parse to the same local day', () {
      // sync_engine's `ts()` reads a pulled date with DateTime.parse, which
      // gives local midnight for a date-only string.
      final pulled = DateTime.parse('2026-10-13');
      expect(pulled.isUtc, isFalse);
      expect((pulled.year, pulled.month, pulled.day), (2026, 10, 13));
      expect(wireDate(pulled), '2026-10-13');
    });
  });

  test('lendOut at 01:22 sends the day the lend sheet showed', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.cachedBooksDao.upsert(
      CachedBooksCompanion.insert(
        editionId: 'ed1',
        workId: 'w1',
        title: 'Aadujeevitham',
        authorNames: 'Benyamin',
      ),
    );
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(id: 'le1', userId: 'u1', editionId: 'ed1'),
    );
    final repo = LendingRepository(db, const SessionContext(userId: 'u1', deviceId: 'd1'));

    final id = await repo.lendOut(
      'le1',
      borrowerName: 'Ben',
      lentDate: DateTime(2026, 10, 13, 1, 22),
      dueDate: DateTime(2026, 10, 27, 0, 30),
    );
    await repo.markReturned(id, DateTime(2026, 10, 20, 2, 0));

    final ops = await db.syncQueueDao.pending(limit: 10);
    final create = jsonDecode(
      ops.singleWhere((o) => o.entity == 'lending_records' && o.opType == 'create').payload,
    ) as Map<String, dynamic>;
    expect(create['lent_date'], '2026-10-13');
    expect(create['due_date'], '2026-10-27');
    final update = jsonDecode(
      ops.singleWhere((o) => o.entity == 'lending_records' && o.opType == 'update').payload,
    ) as Map<String, dynamic>;
    expect(update['returned_date'], '2026-10-20');

    // And what Drift hands back is still that day, for the next push.
    final row = (await db.select(db.lendingRecords).get()).single;
    expect(wireDate(row.lentDate), '2026-10-13');
  });
}
