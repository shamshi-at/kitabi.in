import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/buy_clicks_repository.dart';

/// The outbox for taps on a bookseller link (5 Oct 2026).
///
/// What matters about it is all in the failure paths, because the happy one is
/// a single POST: a tap made offline must still be counted later, a tap made
/// while a batch is in the air must not be erased by that batch finishing, a
/// report that keeps failing must eventually stop being retried, and one
/// reader's unsent taps must never be sent under the next reader's name.
void main() {
  late AppDatabase db;
  late List<List<Map<String, dynamic>>> sent;
  var failing = false;

  final clock = DateTime.utc(2026, 10, 5, 9, 30);

  BuyClicksRepository repo({BuyClickSender? send}) => BuyClicksRepository(
        db,
        now: () => clock,
        send: send ??
            (events) async {
              if (failing) throw StateError('offline');
              sent.add(events);
            },
      );

  Future<void> tap(BuyClicksRepository r, {String edition = 'ed-1'}) =>
      r.record(editionId: edition, retailer: 'Amazon', affiliate: true);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sent = [];
    failing = false;
  });

  tearDown(() => db.close());

  test('a tap is sent with which printing, which shop, and when', () async {
    final r = repo();
    await tap(r);
    await r.drain();

    expect(sent, hasLength(1));
    final event = sent.single.single;
    expect(event['edition_id'], 'ed-1');
    expect(event['retailer'], 'Amazon');
    expect(event['affiliate'], true);
    expect(event['occurred_at'], '2026-10-05T09:30:00.000Z');
    expect(event['id'], isA<String>());
    expect(event.containsKey('attempts'), isFalse, reason: 'bookkeeping stays on the device');
    expect(await r.pending(), isEmpty);
  });

  test('a tap made offline is kept, and sent once there is a connection', () async {
    final r = repo();
    failing = true;
    await tap(r);
    await r.drain();
    expect(sent, isEmpty);
    expect(await r.pending(), hasLength(1), reason: 'the tap must outlive the failed report');

    failing = false;
    await r.drain();
    expect(sent.single, hasLength(1));
    expect(await r.pending(), isEmpty);
  });

  test('the same tap keeps its id across retries, so the server can drop a replay', () async {
    final r = repo();
    failing = true;
    await tap(r);
    final id = (await r.pending()).single['id'];
    await r.drain();
    await r.drain();
    failing = false;
    await r.drain();
    expect(sent.single.single['id'], id);
  });

  test('a report that keeps failing is given up on, not retried for ever', () async {
    final r = repo();
    failing = true;
    await tap(r);
    for (var i = 0; i < BuyClicksRepository.maxEventAttempts - 1; i++) {
      await r.drain();
      expect(await r.pending(), hasLength(1), reason: 'still owed a try after ${i + 1}');
    }
    await r.drain();
    expect(await r.pending(), isEmpty);
  });

  test('a tap made while a batch is in the air is not erased when it lands', () async {
    final gate = Completer<void>();
    late BuyClicksRepository r;
    r = repo(
      send: (events) async {
        sent.add(events);
        await gate.future;
      },
    );
    await tap(r, edition: 'ed-1');
    final draining = r.drain();
    await Future<void>.delayed(Duration.zero);
    await tap(r, edition: 'ed-2');
    gate.complete();
    await draining;

    final left = await r.pending();
    expect(left.map((e) => e['edition_id']), ['ed-2']);
  });

  test('two taps in quick succession are both kept', () async {
    final r = repo();
    await Future.wait([tap(r, edition: 'ed-1'), tap(r, edition: 'ed-2'), tap(r, edition: 'ed-3')]);
    expect((await r.pending()).map((e) => e['edition_id']).toSet(), {'ed-1', 'ed-2', 'ed-3'});
  });

  test('signing out discards unsent taps — they carry no name of their own', () async {
    final r = repo();
    failing = true;
    await tap(r);
    await r.clearForSignOut();
    failing = false;
    await r.drain();
    expect(sent, isEmpty, reason: 'the next reader must not be credited with these');
  });

  test('a tap with nothing to say is not recorded', () async {
    final r = repo();
    await r.record(editionId: '', retailer: 'Amazon', affiliate: false);
    await r.record(editionId: 'ed-1', retailer: '', affiliate: false);
    expect(await r.pending(), isEmpty);
  });

  test('a damaged outbox costs its contents, not the next tap', () async {
    await db.keyValuesDao.setValue(BuyClicksRepository.outboxKey, '{not json');
    final r = repo();
    expect(await r.pending(), isEmpty);
    await tap(r);
    expect(await r.pending(), hasLength(1));

    await db.keyValuesDao.setValue(
      BuyClicksRepository.outboxKey,
      '[{"id":"a","edition_id":"ed-9","retailer":"Amazon"},"junk",{"id":7}]',
    );
    expect((await r.pending()).map((e) => e['edition_id']), ['ed-9']);
  });

  test('the outbox has a ceiling, and keeps the newest', () async {
    final r = repo();
    for (var i = 0; i < BuyClicksRepository.maxQueued + 5; i++) {
      await tap(r, edition: 'ed-$i');
    }
    final left = await r.pending();
    expect(left, hasLength(BuyClicksRepository.maxQueued));
    expect(left.last['edition_id'], 'ed-${BuyClicksRepository.maxQueued + 4}');
    expect(left.first['edition_id'], 'ed-5');
  });

  test('nothing queued means nothing sent', () async {
    await repo().drain();
    expect(sent, isEmpty);
  });
}
