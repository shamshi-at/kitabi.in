import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../db/daos/promotions_dao.dart';
import '../db/database.dart';

/// The device's side of in-app promotions (docs/promotions-plan.md §7).
///
/// Fetches what the server has already resolved for this reader, caches it in
/// Drift, and reports impressions/clicks/dismisses through a small outbox.
/// Everything the UI reads comes from Drift, so Home works offline and a
/// dismissal takes effect on the next frame with no network in the path.
class PromotionsRepository {
  PromotionsRepository(this._db, this._api, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final ApiClient _api;
  final Uuid _uuid;

  /// Where the last ETag lives, so a poll that changed nothing costs a few
  /// bytes. Kept in KeyValues rather than memory so it survives a cold start.
  static const _etagKey = 'promotions_etag';

  /// At most one fetch this often. Promotions are not time-critical; a reader
  /// who reopens the app six times an hour should not cost six round trips.
  static const minFetchInterval = Duration(minutes: 30);
  static const _lastFetchKey = 'promotions_last_fetch';

  /// Five attempts, then the event is dropped. A lost impression count is not
  /// worth an outbox that never empties.
  static const maxEventAttempts = 5;

  PromotionsDao get _dao => _db.promotionsDao;

  /// Pull the resolved list for this reader and cache it.
  ///
  /// Never throws: a promotion is the least important thing on the screen, and
  /// a failed fetch must leave the cached set (and Home) exactly as they were.
  Future<void> refresh({bool force = false}) async {
    try {
      if (!force && !await _dueForFetch()) return;
      final etag = await _db.keyValuesDao.getValue(_etagKey);
      final payload = await _api.getPromotions(etag: etag);
      await _db.keyValuesDao.setValue(
        _lastFetchKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      if (payload == null) return; // 304 — the cache is already right
      if (payload.etag != null) {
        await _db.keyValuesDao.setValue(_etagKey, payload.etag!);
      }
      await _dao.replaceAll([for (final row in payload.promotions) _toCompanion(row)]);
    } catch (_) {
      // Offline, 500, a garbled row — keep what's cached and try again later.
    }
  }

  Future<bool> _dueForFetch() async {
    final raw = await _db.keyValuesDao.getValue(_lastFetchKey);
    if (raw == null) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().toUtc().difference(last) >= minFetchInterval;
  }

  static CachedPromotionsCompanion _toCompanion(Map<String, dynamic> row) {
    DateTime? parseDate(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;
    return CachedPromotionsCompanion.insert(
      id: row['id'] as String,
      kind: row['kind'] as String? ?? 'banner',
      cardStyle: Value(row['card_style'] as String?),
      placement: row['placement'] as String? ?? 'home_top',
      sponsor: Value(row['sponsor'] as String?),
      language: Value(row['language'] as String?),
      headline: row['headline'] as String? ?? '',
      body: Value(row['body'] as String?),
      ctaLabel: Value(row['cta_label'] as String?),
      imageUrl: Value(row['image_url'] as String?),
      actionType: Value(row['action_type'] as String? ?? 'none'),
      actionValue: Value(row['action_value'] as String?),
      workId: Value(row['work_id'] as String?),
      editionId: Value(row['edition_id'] as String?),
      bookTitle: Value(row['book_title'] as String?),
      bookAuthors: Value(row['book_authors'] as String?),
      bookCoverUrl: Value(row['book_cover_url'] as String?),
      dismissible: Value(row['dismissible'] as bool? ?? true),
      priority: Value((row['priority'] as num?)?.toInt() ?? 5),
      expiresAt: Value(parseDate(row['expires_at'])),
      fetchedAt: Value(DateTime.now().toUtc()),
    );
  }

  /// The reader tapped ✕. Written locally first and immediately — the one
  /// thing worse than an unwanted promotion is one that won't close on a bad
  /// connection — then queued so the server stops serving it everywhere.
  Future<void> dismiss(CachedPromotion promo) async {
    final now = DateTime.now().toUtc();
    await _dao.markDismissed(promo.id, now);
    await _enqueue(promo, 'dismiss', now);
  }

  /// Undo, from the toast. Clears the local flag; the queued dismiss is
  /// dropped if it hasn't gone out yet, so a fast undo costs nothing.
  Future<void> undoDismiss(CachedPromotion promo) async {
    await _dao.undismiss(promo.id);
    for (final event in await _dao.pending(limit: 200)) {
      if (event.promotionId == promo.id && event.kind == 'dismiss') {
        await _dao.clearEvents([event.id]);
      }
    }
  }

  /// Counted when the widget is actually on screen, never on fetch — a card
  /// below the fold that nobody scrolled to never happened, and counting it
  /// would make every rate in the console a lie.
  Future<void> recordImpression(CachedPromotion promo) async {
    final now = DateTime.now().toUtc();
    await _dao.recordShown(promo.id, now, promo.impressionCount + 1);
    await _enqueue(promo, 'impression', now);
  }

  Future<void> recordClick(CachedPromotion promo) async {
    await _enqueue(promo, 'click', DateTime.now().toUtc());
  }

  Future<void> _enqueue(CachedPromotion promo, String kind, DateTime at) async {
    await _dao.enqueue(
      PromotionEventQueueCompanion.insert(
        id: _uuid.v4(),
        promotionId: promo.id,
        kind: kind,
        language: Value(promo.language),
        occurredAt: at,
      ),
    );
  }

  /// Send whatever is queued. Best-effort by design: this is telemetry, and it
  /// deliberately does not share the sync engine's retry path, where a promo
  /// server hiccup could stall a reader's actual library.
  Future<void> drainEvents() async {
    await _dao.dropExhausted(maxEventAttempts);
    final pending = await _dao.pending();
    if (pending.isEmpty) return;
    try {
      await _api.postPromotionEvents([
        for (final event in pending)
          {
            'id': event.id,
            'promotion_id': event.promotionId,
            'kind': event.kind,
            if (event.language != null) 'language': event.language,
            'occurred_at': event.occurredAt.toUtc().toIso8601String(),
          },
      ]);
      await _dao.clearEvents([for (final event in pending) event.id]);
    } catch (_) {
      await _dao.bumpAttempts([for (final event in pending) event.id]);
    }
  }

  /// Sign-out: the next reader on this device must not inherit the last one's
  /// campaigns, their dismissals, or their unsent events.
  Future<void> clearForSignOut() async {
    await _dao.clearAll();
    await _db.keyValuesDao.setValue(_etagKey, '');
    await _db.keyValuesDao.setValue(_lastFetchKey, '');
  }
}
