import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';

/// Rating and reviewing a series on-device.
///
/// The rule: a series and its volumes are separate subjects. The reader can
/// hold both opinions at once — five stars for the saga, two for volume three —
/// and neither row may stand in for the other. On this side that means a
/// distinct Drift row per subject and a push payload naming exactly one, since
/// the server rejects an op naming both or neither.
void main() {
  late AppDatabase db;
  const session = SessionContext(userId: 'u1', deviceId: 'd1');

  setUp(() {
    // Never closed — db.close() deadlocks between the fake-async test zone and
    // drift's real event loop; an in-memory db per test just gets GC'd.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  Future<List<Map<String, dynamic>>> queuedOps() async {
    final rows = await db.syncQueueDao.pending(limit: 50);
    return [
      for (final row in rows)
        {
          'entity': row.entity,
          'op_type': row.opType,
          'payload': jsonDecode(row.payload) as Map<String, dynamic>,
        },
    ];
  }

  test('a series rating and a book rating are separate rows', () async {
    final ratings = RatingsRepository(db, session);
    await ratings.setRating('work-1', 2);
    await ratings.setSeriesRating('series-1', 5);

    expect((await ratings.watchForWork('work-1').first)?.value, 2);
    expect((await ratings.watchForSeries('series-1').first)?.value, 5);

    // …and neither lookup can see the other's row.
    expect(await ratings.watchForSeries('work-1').first, isNull);
    expect(await ratings.watchForWork('series-1').first, isNull);
  });

  test('a series rating names only series_id on the wire', () async {
    await RatingsRepository(db, session).setSeriesRating('series-1', 5);

    final op = (await queuedOps()).single;
    expect(op['entity'], 'ratings');
    expect(op['payload'], {'series_id': 'series-1', 'value': 5});
    expect(
      op['payload'].containsKey('work_id'),
      isFalse,
      reason: 'the server rejects an op naming both subjects',
    );
  });

  test('a book rating still names only work_id', () async {
    await RatingsRepository(db, session).setRating('work-1', 4);
    expect((await queuedOps()).single['payload'], {'work_id': 'work-1', 'value': 4});
  });

  test('rating a series again updates the row rather than stacking a second',
      () async {
    final ratings = RatingsRepository(db, session);
    await ratings.setSeriesRating('series-1', 3);
    await ratings.setSeriesRating('series-1', 5);

    expect((await ratings.watchForSeries('series-1').first)?.value, 5);
    final ops = await queuedOps();
    expect(ops.map((o) => o['op_type']), ['create', 'update']);
  });

  test('clearing a series rating leaves the book rating alone', () async {
    final ratings = RatingsRepository(db, session);
    await ratings.setRating('work-1', 2);
    await ratings.setSeriesRating('series-1', 5);

    await ratings.clearSeriesRating('series-1');

    expect(await ratings.watchForSeries('series-1').first, isNull);
    expect((await ratings.watchForWork('work-1').first)?.value, 2,
        reason: 'taking back the series rating is not a statement about the book');
  });

  test('the insights map of book ratings excludes series ratings', () async {
    final ratings = RatingsRepository(db, session);
    await ratings.setRating('work-1', 4);
    await ratings.setSeriesRating('series-1', 5);

    // That strip is about books on a shelf; a series has no cover to sit under.
    expect(await ratings.watchAllByWorkId().first, {'work-1': 4});
  });

  test('a series review is its own row and names only series_id', () async {
    final reviews = ReviewsRepository(db, session);
    await reviews.upsert('work-1', body: 'This volume drags.', visible: true);
    await reviews.upsertForSeries('series-1', body: 'A monumental saga.', visible: true);

    expect((await reviews.watchForWork('work-1').first)?.body, 'This volume drags.');
    expect((await reviews.watchForSeries('series-1').first)?.body, 'A monumental saga.');

    final seriesOp = (await queuedOps()).last;
    expect(seriesOp['payload'], {
      'series_id': 'series-1',
      'body': 'A monumental saga.',
      'visible': true,
    });
  });

  test('removing a series review leaves the book review standing', () async {
    final reviews = ReviewsRepository(db, session);
    await reviews.upsert('work-1', body: 'This volume drags.', visible: true);
    await reviews.upsertForSeries('series-1', body: 'A monumental saga.', visible: true);

    await reviews.removeForSeries('series-1');

    expect(await reviews.watchForSeries('series-1').first, isNull);
    expect((await reviews.watchForWork('work-1').first)?.body, 'This volume drags.');
  });
}
