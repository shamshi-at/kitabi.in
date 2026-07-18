import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';

/// Riverpod providers for the personal library — library entries, ratings, and
/// derived lists — reading from the Drift-backed repositories (offline-first,
/// CLAUDE.md rule 1). Shared across the grid, book detail, lending, and insights.
final libraryEntryProvider =
    FutureProvider.autoDispose.family<LibraryEntry?, String>((ref, editionId) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.getByEditionId(editionId);
});

final ratingProvider = FutureProvider.autoDispose.family<Rating?, String>((ref, workId) async {
  final repo = await ref.watch(ratingsRepositoryProvider.future);
  return repo.watchForWork(workId).first;
});

final reviewProvider = FutureProvider.autoDispose.family<Review?, String>((ref, workId) async {
  final repo = await ref.watch(reviewsRepositoryProvider.future);
  return repo.watchForWork(workId).first;
});

final lendingRecordsProvider =
    FutureProvider.autoDispose.family<List<LendingRecord>, String>((ref, libraryEntryId) async {
  final repo = await ref.watch(lendingRepositoryProvider.future);
  return repo.watchForEntry(libraryEntryId).first;
});

/// The whole lending ledger (S8) — reactive so a lend/return on any screen
/// updates the ledger live.
final allLendingProvider = StreamProvider.autoDispose<List<LendingWithBook>>((ref) async* {
  final repo = await ref.watch(lendingRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Reactive entries-with-books for the library grid (S5) — lets the grid filter
/// by book metadata (language) and stay live as books are added/edited.
final libraryHitsProvider = StreamProvider.autoDispose<List<LibraryHit>>((ref) async* {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  yield* repo.watchWithBooks();
});

/// Every lending record that touches one book, newest first — lent copies
/// hang off the owned library entry, borrowed ones off the catalog edition,
/// so both directions land in one history (the book page's ledger view).
/// Derived from the reactive [allLendingProvider], so a lend/return anywhere
/// updates the open book page live.
final bookLendingHistoryProvider = Provider.autoDispose
    .family<AsyncValue<List<LendingRecord>>, ({String? entryId, String editionId})>((ref, key) {
  return ref.watch(allLendingProvider).whenData((all) {
    final records = all
        .map((r) => r.record)
        .where((r) =>
            (key.entryId != null && r.libraryEntryId == key.entryId) ||
            r.editionId == key.editionId)
        .toList()
      ..sort((a, b) => b.lentDate.compareTo(a.lentDate));
    return records;
  });
});

/// Maps a borrowed LibraryEntry's id to its lending record (owner request,
/// 15 Jul 2026: borrowed books are unified into the library grid, banded by
/// this lookup, instead of living in a separate lending-sourced section).
/// Only ever holds `direction == 'borrowed'` records that are linked to a
/// LibraryEntry — the unified shape every borrow gets now; a handful of
/// pre-unification rows without a link just won't band (see
/// LendingRecord.libraryEntryId's docstring).
final lendingByLibraryEntryIdProvider = Provider.autoDispose<Map<String, LendingRecord>>((ref) {
  final all = ref.watch(allLendingProvider).valueOrNull ?? const <LendingWithBook>[];
  final map = <String, LendingRecord>{};
  for (final r in all) {
    final entryId = r.record.libraryEntryId;
    if (r.record.direction == 'borrowed' && entryId != null) {
      map[entryId] = r.record;
    }
  }
  return map;
});

/// Global search over the personal library (S4) — the "in your library" section.
final librarySearchProvider =
    FutureProvider.autoDispose.family<List<LibraryHit>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.search(query);
});

final libraryTagsProvider =
    FutureProvider.autoDispose.family<List<LibraryEntryTag>, String>((ref, libraryEntryId) async {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  return repo.watchForEntry(libraryEntryId).first;
});

final allTagsProvider = FutureProvider.autoDispose<List<PersonalTag>>((ref) async {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  return repo.watchAll().first;
});

/// The reader's shelves (personal tags), reactive — a shelf created anywhere
/// (the book page's "Add to a shelf", the shelves view's "New shelf") appears
/// in the shelves view without a hand-rolled invalidate.
final personalShelvesProvider = StreamProvider.autoDispose<List<PersonalTag>>((ref) async* {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  yield* repo.watchAll();
});

/// entryId → the shelf (tag) ids on it, across the whole library — one map
/// instead of a per-entry lookup, so shelf tiles get counts/covers and the
/// shelf filter can match entries in a plain `where`.
final entryShelvesProvider = StreamProvider.autoDispose<Map<String, Set<String>>>((ref) async* {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  yield* repo.watchAssignments().map((rows) {
    final map = <String, Set<String>>{};
    for (final row in rows) {
      map.putIfAbsent(row.libraryEntryId, () => {}).add(row.tagId);
    }
    return map;
  });
});

/// Whether the Library tab opens on the shelves view — a reader who thinks in
/// shelves shouldn't have to re-toggle every launch. Device-local (KeyValues).
final libraryShelvesViewProvider = FutureProvider.autoDispose<bool>((ref) async {
  final value =
      await ref.watch(appDatabaseProvider).keyValuesDao.getValue('library_shelves_view');
  return value == 'true';
});

/// Active (non-deleted) library entries — feeds the library grid (S5) and the
/// home screen. A reactive stream (not a one-shot snapshot) so a book added on
/// any screen surfaces immediately on the always-alive home route, without
/// hand-invalidating from every mutation site.
final libraryEntriesProvider = StreamProvider.autoDispose<List<LibraryEntry>>((ref) async* {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  yield* repo.watchActive();
});

/// Offline-capable display data for one edition — populated the moment a
/// book is added to the library (data/db/catalog_cache.dart).
///
/// Reactive (17 Jul 2026): this was a one-shot FutureProvider, so anything
/// that changed a cached book — a Type edit mirrored back, a cover upload, a
/// page count supplied from the reading timer — wrote the row and left every
/// live screen showing the old value until it happened to be rebuilt. Home
/// especially never rebuilt: it's an always-alive shell branch, so the
/// provider was never re-subscribed. Watching the row means the write itself
/// is the refresh.
final cachedBookProvider =
    StreamProvider.autoDispose.family<CachedBook?, String>((ref, editionId) {
  return ref.watch(appDatabaseProvider).cachedBooksDao.watchByEditionId(editionId);
});
