import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Sends a batch to `POST /buy-clicks`. Injected rather than taking the whole
/// `ApiClient`, so the outbox is tested with a closure instead of a fake HTTP
/// stack.
typedef BuyClickSender = Future<void> Function(List<Map<String, dynamic>> events);

/// The device's outbox for taps on a bookseller link (5 Oct 2026).
///
/// The owner wants to know which books readers go on to look at buying, from
/// which shop. A tap is recorded here first and reported when it can be, so
/// one made on a train with no signal still counts — and the button itself
/// never waits on any of it: the shop opens whether or not this works.
///
/// **Telemetry, not library data.** Like promotion events it stays off the
/// sync queue on purpose: it is append-only, nothing ever edits or deletes
/// one, and a reporting hiccup must never sit in the path of a reader's
/// actual library syncing.
///
/// **Kept in `key_values`, not a table of its own.** A handful of small rows
/// that live for seconds does not earn a schema version — and a Drift
/// migration is the most expensive kind of change this app has (25 Aug 2026).
/// The promotions outbox has a table because the serve logic queries it; this
/// one is only ever read whole.
///
/// **No user id is stored.** The server files a batch under whoever is signed
/// in when it arrives, so `clearForSignOut` is not housekeeping: without it
/// the next reader on this device would be credited with the last one's taps.
class BuyClicksRepository {
  BuyClicksRepository(
    this._db, {
    required this.send,
    Uuid? uuid,
    DateTime Function()? now,
  })  : _uuid = uuid ?? const Uuid(),
        _now = now ?? (() => DateTime.now().toUtc());

  final AppDatabase _db;
  final BuyClickSender send;
  final Uuid _uuid;
  final DateTime Function() _now;

  static const outboxKey = 'buy_click_outbox';

  /// Five tries, then the tap is dropped. A lost count is not worth an outbox
  /// that never empties — the same bargain the promotions outbox makes.
  static const maxEventAttempts = 5;

  /// A ceiling on what is remembered. Nobody taps a buy button two hundred
  /// times offline; a device that somehow has is not owed a bigger queue.
  static const maxQueued = 200;

  /// Reads and writes of the outbox, one at a time. It is a single JSON value,
  /// so two taps in quick succession would otherwise each read the old list
  /// and the second write would erase the first.
  Future<void> _turn = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final done = Completer<T>();
    _turn = _turn.then((_) async {
      try {
        done.complete(await body());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  Future<List<Map<String, dynamic>>> _read() async {
    final raw = await _db.keyValuesDao.getValue(outboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      // Element by element: a value this app wrote in some future shape must
      // cost that one entry, not the whole outbox (21 Jul 2026).
      return [
        for (final item in decoded)
          if (item is Map && item['id'] is String && item['edition_id'] is String)
            Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Map<String, dynamic>> events) => events.isEmpty
      ? _db.keyValuesDao.deleteValue(outboxKey)
      : _db.keyValuesDao.setValue(outboxKey, jsonEncode(events));

  /// The reader opened a bookseller link. Never throws: this sits beside a
  /// button that has already done its job.
  Future<void> record({
    required String editionId,
    required String retailer,
    required bool affiliate,
  }) async {
    if (editionId.isEmpty || retailer.isEmpty) return;
    try {
      await _exclusive(() async {
        final events = await _read();
        events.add({
          'id': _uuid.v4(),
          'edition_id': editionId,
          'retailer': retailer,
          'affiliate': affiliate,
          'occurred_at': _now().toUtc().toIso8601String(),
          'attempts': 0,
        });
        // Oldest out first, if it ever comes to that.
        final kept = events.length > maxQueued ? events.sublist(events.length - maxQueued) : events;
        await _write(kept);
      });
    } catch (_) {
      // A tap we could not write down is a tap we do not count.
    }
  }

  /// What is waiting to be sent — for tests and nothing else.
  Future<List<Map<String, dynamic>>> pending() => _exclusive(_read);

  /// Send whatever is queued. Best-effort: on any failure the events stay,
  /// one attempt older, until they succeed or run out of tries.
  Future<void> drain() async {
    final batch = await _exclusive(_read);
    if (batch.isEmpty) return;
    final ids = {for (final event in batch) event['id'] as String};
    var sent = false;
    try {
      await send([
        for (final event in batch)
          {
            'id': event['id'],
            'edition_id': event['edition_id'],
            'retailer': event['retailer'],
            'affiliate': event['affiliate'] == true,
            'occurred_at': event['occurred_at'],
          },
      ]);
      sent = true;
    } catch (_) {
      // Offline, a 500, a timeout — the events keep, and are tried again.
    }
    try {
      await _exclusive(() async {
        // Read again rather than writing back what was read before the
        // request: a tap made while it was in the air must not be erased.
        final now = await _read();
        final next = <Map<String, dynamic>>[];
        for (final event in now) {
          if (!ids.contains(event['id'])) {
            next.add(event);
          } else if (!sent) {
            final attempts = ((event['attempts'] as num?) ?? 0).toInt() + 1;
            if (attempts < maxEventAttempts) next.add({...event, 'attempts': attempts});
          }
        }
        await _write(next);
      });
    } catch (_) {
      // The worst case is a batch sent twice; the server drops the replay.
    }
  }

  /// Sign-out: the next reader on this device must not be credited with the
  /// last one's taps (the outbox carries no user id — see the class comment).
  Future<void> clearForSignOut() async {
    try {
      await _exclusive(() => _db.keyValuesDao.deleteValue(outboxKey));
    } catch (_) {}
  }
}
