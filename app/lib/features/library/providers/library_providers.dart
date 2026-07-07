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

/// Books currently borrowed from others (active, not returned) — their own
/// section in the library. Derived from the lending ledger; each carries the
/// cached book (once hydrated) and the lender's name on the record.
final borrowedBooksProvider = Provider.autoDispose<List<LendingWithBook>>((ref) {
  final all = ref.watch(allLendingProvider).valueOrNull ?? const <LendingWithBook>[];
  return all
      .where((r) => r.record.direction == 'borrowed' && r.record.returnedDate == null)
      .toList();
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
final cachedBookProvider =
    FutureProvider.autoDispose.family<CachedBook?, String>((ref, editionId) {
  return ref.watch(appDatabaseProvider).cachedBooksDao.getByEditionId(editionId);
});
