import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';

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

final libraryTagsProvider =
    FutureProvider.autoDispose.family<List<LibraryEntryTag>, String>((ref, libraryEntryId) async {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  return repo.watchForEntry(libraryEntryId).first;
});

final allTagsProvider = FutureProvider.autoDispose<List<PersonalTag>>((ref) async {
  final repo = await ref.watch(tagsRepositoryProvider.future);
  return repo.watchAll().first;
});

/// The library grid (S5) — active (non-deleted) entries, refreshed via
/// manual invalidation after mutations (same pattern as profile_providers.dart:
/// simplest correct thing for a V1 shell).
final libraryEntriesProvider = FutureProvider.autoDispose<List<LibraryEntry>>((ref) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.watchActive().first;
});

/// Offline-capable display data for one edition — populated the moment a
/// book is added to the library (data/db/catalog_cache.dart).
final cachedBookProvider =
    FutureProvider.autoDispose.family<CachedBook?, String>((ref, editionId) {
  return ref.watch(appDatabaseProvider).cachedBooksDao.getByEditionId(editionId);
});
