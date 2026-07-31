import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'promotions_dao.g.dart';

/// DAO for the promotion cache and its event outbox.
///
/// Everything Home reads goes through [watchServable], which is a *stream* on
/// purpose: dismissing from the banner has to update Home without the caller
/// remembering to invalidate anything. A one-shot future here would reproduce
/// the bug this repo has already shipped three times (`cachedBookProvider`,
/// `libraryTags`, `libraryEntryProvider`).
@DriftAccessor(tables: [CachedPromotions, PromotionEventQueue])
class PromotionsDao extends DatabaseAccessor<AppDatabase> with _$PromotionsDaoMixin {
  PromotionsDao(super.db);

  /// Promotions this device may actually draw right now: not dismissed, not
  /// expired. Expiry is checked here rather than trusted to the next fetch, so
  /// a campaign that ends while the reader is offline still disappears.
  Stream<List<CachedPromotion>> watchServable(DateTime now) {
    return (select(cachedPromotions)
          ..where((t) => t.dismissedAt.isNull())
          ..where((t) => t.expiresAt.isNull() | t.expiresAt.isBiggerThanValue(now))
          ..orderBy([(t) => OrderingTerm.desc(t.priority)]))
        .watch();
  }

  Future<List<CachedPromotion>> all() => select(cachedPromotions).get();

  Future<CachedPromotion?> getById(String id) =>
      (select(cachedPromotions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Replace the cached set with what the server just resolved for this reader.
  ///
  /// Local-only columns ([dismissedAt], [impressionCount], [lastShownAt]) are
  /// carried across for ids that survive: they're this device's memory, and the
  /// server's payload has no opinion about them. Ids the server no longer sends
  /// are dropped — that's how a paused campaign vanishes.
  Future<void> replaceAll(List<CachedPromotionsCompanion> rows) async {
    await transaction(() async {
      final existing = {for (final row in await all()) row.id: row};
      final incoming = rows.map((r) => r.id.value).toSet();
      await (delete(cachedPromotions)..where((t) => t.id.isNotIn(incoming.toList()))).go();
      for (final row in rows) {
        final previous = existing[row.id.value];
        await into(cachedPromotions).insertOnConflictUpdate(
          row.copyWith(
            dismissedAt: Value(previous?.dismissedAt),
            impressionCount: Value(previous?.impressionCount ?? 0),
            lastShownAt: Value(previous?.lastShownAt),
          ),
        );
      }
    });
  }

  Future<void> markDismissed(String id, DateTime at) =>
      (update(cachedPromotions)..where((t) => t.id.equals(id)))
          .write(CachedPromotionsCompanion(dismissedAt: Value(at)));

  Future<void> undismiss(String id) =>
      (update(cachedPromotions)..where((t) => t.id.equals(id)))
          .write(const CachedPromotionsCompanion(dismissedAt: Value(null)));

  Future<void> recordShown(String id, DateTime at, int count) =>
      (update(cachedPromotions)..where((t) => t.id.equals(id))).write(
        CachedPromotionsCompanion(lastShownAt: Value(at), impressionCount: Value(count)),
      );

  // ---- the event outbox ----

  Future<void> enqueue(PromotionEventQueueCompanion row) =>
      into(promotionEventQueue).insertOnConflictUpdate(row);

  Future<List<PromotionEventQueueData>> pending({int limit = 100}) =>
      (select(promotionEventQueue)
            ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)])
            ..limit(limit))
          .get();

  Future<void> clearEvents(List<String> ids) =>
      (delete(promotionEventQueue)..where((t) => t.id.isIn(ids))).go();

  Future<void> bumpAttempts(List<String> ids) async {
    for (final id in ids) {
      final row = await (select(promotionEventQueue)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) continue;
      await (update(promotionEventQueue)..where((t) => t.id.equals(id)))
          .write(PromotionEventQueueCompanion(attempts: Value(row.attempts + 1)));
    }
  }

  /// Give up on events that have failed too often. A lost impression count is
  /// not worth a queue that never empties.
  Future<void> dropExhausted(int maxAttempts) =>
      (delete(promotionEventQueue)..where((t) => t.attempts.isBiggerOrEqualValue(maxAttempts)))
          .go();

  /// Signing out wipes the reader-specific cache — the next reader on this
  /// device must not inherit the last one's campaigns or their dismissals.
  Future<void> clearAll() async {
    await delete(cachedPromotions).go();
    await delete(promotionEventQueue).go();
  }
}
