import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';

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

// ─── Search idle state (S4h) ────────────────────────────────────────────────
// What the search page shows before you type. Everything here is real data:
// the reader's own history, the newest catalogue rows in their languages, and
// authors ranked by how many works they actually have. Deliberately no
// "trending" — nothing counts reads or views yet (docs/screen-design.md).

/// Recent searches, newest first. Device-local (`key_values`), never synced,
/// and dropped on account switch (`AppDatabase.clearUserData`) — a search
/// history is personal, so it must not follow the device to the next reader.
final recentSearchesProvider =
    NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);

class RecentSearches extends Notifier<List<String>> {
  static const _key = 'recent_searches';
  static const _max = 8;

  /// Queries can contain spaces, so the stored list is newline-delimited —
  /// a search is a single line by definition.
  static const _separator = '\n';

  @override
  List<String> build() {
    // Notifier.build is synchronous; load in the background and publish when
    // it arrives. Empty-until-loaded is correct here — the section simply
    // doesn't render on the first frame.
    _load();
    return const [];
  }

  Future<void> _load() async {
    final raw = await ref.read(appDatabaseProvider).keyValuesDao.getValue(_key);
    if (raw == null || raw.isEmpty) return;
    state = raw.split(_separator).where((s) => s.isNotEmpty).toList();
  }

  /// Record a query the reader actually committed to (submitted, or followed
  /// through to a result) — never a debounced keystroke, or the list fills up
  /// with the prefixes of one search.
  Future<void> record(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [
      q,
      ...state.where((s) => s.toLowerCase() != q.toLowerCase()),
    ].take(_max).toList();
    state = next;
    await ref.read(appDatabaseProvider).keyValuesDao.setValue(_key, next.join(_separator));
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(appDatabaseProvider).keyValuesDao.setValue(_key, '');
  }
}

/// Newest catalogue arrivals in one language — the regional angle on the idle
/// page. The caller skips the row entirely when the reader has set no profile
/// languages, rather than showing a global "newest" that means little.
final newInLanguageProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, language) {
  return ref.watch(apiClientProvider).browseWorks(
        limit: 12,
        language: language,
        sort: 'year_desc',
      );
});

/// Authors with the most works in the catalogue — the one popularity signal
/// that genuinely exists today (`sort=popular` counts works, not readers).
final popularAuthorsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(apiClientProvider).browseAuthors(limit: 8, sort: 'popular');
});
