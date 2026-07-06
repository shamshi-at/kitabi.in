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

/// Global search (S4) — books, authors, and publishers from the catalog in one
/// request. Returns `{works, authors, publishers}` (each a `List<Map>`); the
/// personal-library section is searched separately on-device (Drift).
final globalSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, query) async {
  if (query.trim().isEmpty) {
    return const {'works': [], 'authors': [], 'publishers': []};
  }
  return ref.watch(apiClientProvider).searchAll(query.trim());
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
