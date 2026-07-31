import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/promotions_repository.dart';
import '../../../data/sync/sync_providers.dart';

final promotionsRepositoryProvider = Provider<PromotionsRepository>((ref) {
  return PromotionsRepository(ref.watch(appDatabaseProvider), ref.watch(apiClientProvider));
});

/// Live promotions for this device, straight from Drift.
///
/// A **stream**, not a future: dismissing from the banner has to update Home
/// without the caller remembering to invalidate anything. The same mistake has
/// shipped here three times already (`cachedBookProvider`, `libraryTags`,
/// `libraryEntryProvider`) — a provider whose value can change from a widget
/// that doesn't own it must be reactive.
final promotionsProvider = StreamProvider<List<CachedPromotion>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  // Kick a refresh whenever something starts watching. The repository decides
  // whether it's actually due (and does nothing when offline), so this is
  // cheap on every rebuild but still fetches on a cold start.
  ref.read(promotionsRepositoryProvider)
    ..refresh()
    ..drainEvents();
  return db.promotionsDao.watchServable(DateTime.now().toUtc());
});

/// The banner for the top of Home, or null. At most one, ever — the server
/// already caps per placement, and this is the second belt.
final homeBannerProvider = Provider<CachedPromotion?>((ref) {
  return _pick(ref, 'home_top');
});

/// The card for the Home stream, or null.
final homeCardProvider = Provider<CachedPromotion?>((ref) {
  return _pick(ref, 'home_stream');
});

CachedPromotion? _pick(Ref ref, String placement) {
  final all = ref.watch(promotionsProvider).valueOrNull ?? const <CachedPromotion>[];
  final now = DateTime.now().toUtc();
  for (final promo in all) {
    if (promo.placement != placement) continue;
    if (promo.dismissedAt != null) continue;
    if (promo.expiresAt != null && !promo.expiresAt!.isAfter(now)) continue;
    return promo;
  }
  return null;
}
