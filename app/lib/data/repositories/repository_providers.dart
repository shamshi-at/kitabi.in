import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_providers.dart';
import 'repositories.dart';

final libraryRepositoryProvider = FutureProvider<LibraryRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return LibraryRepository(ref.watch(appDatabaseProvider), session);
});

final ratingsRepositoryProvider = FutureProvider<RatingsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return RatingsRepository(ref.watch(appDatabaseProvider), session);
});

final reviewsRepositoryProvider = FutureProvider<ReviewsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return ReviewsRepository(ref.watch(appDatabaseProvider), session);
});

final tagsRepositoryProvider = FutureProvider<TagsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return TagsRepository(ref.watch(appDatabaseProvider), session);
});

final lendingRepositoryProvider = FutureProvider<LendingRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return LendingRepository(ref.watch(appDatabaseProvider), session);
});
