import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';

/// Catalog-only search results (title / author / exact ISBN). The personal
/// library merge ("in your library" vs "in the catalog") lands once Phase 3's
/// Drift-backed library entries exist — for now every result is a catalog
/// work and the app can only offer "add".
final catalogSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  return ref.watch(apiClientProvider).searchCatalog(query.trim());
});

const _emptySearch = {
  'works': <Map<String, dynamic>>[],
  'authors': <Map<String, dynamic>>[],
  'publishers': <Map<String, dynamic>>[],
};

/// Global search (S4) — books, authors, and publishers from the catalog in
/// one request, fuzzy/typo-tolerant and ranked server-side (pg_trgm). Returns
/// `{works, authors, publishers}`; the personal-library section is searched
/// separately on-device (Drift). Successful results are kept alive per query
/// string, so backspacing through earlier queries re-renders instantly from
/// cache instead of re-fetching.
final globalSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, query) async {
  final q = query.trim();
  // A single character matches half the catalog and trigram noise — wait for 2.
  if (q.length < 2) return _emptySearch;
  final result = await ref.watch(apiClientProvider).searchAll(q);
  ref.keepAlive();
  return result;
});

final authorWorksProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, authorId) {
  return ref.watch(apiClientProvider).getAuthorWorks(authorId);
});

final publisherWorksProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, publisherId) {
  return ref.watch(apiClientProvider).getPublisherWorks(publisherId);
});

/// Full Work detail — used by the add/edit form when editing an existing
/// catalog entry (create passes no id and skips this entirely).
final workProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, workId) {
  return ref.watch(apiClientProvider).getWork(workId);
});

/// Public reviews for a book plus the community rating picture (average,
/// count, 1-5 distribution) — one call powers both the book page hero's
/// rating row and the About tab's reviews section. Sorting/pagination for
/// display are handled client-side over the fetched `reviews` list; the
/// server always returns newest-first. Reviewer identity is resolved
/// server-side on every fetch, so re-opening the book page always reflects
/// the reviewer's current profile visibility.
final publicReviewsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, workId) {
  return ref.watch(apiClientProvider).getWorkReviews(workId);
});
