import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../sync/sync_providers.dart';
import 'buy_clicks_repository.dart';
import 'repositories.dart';

/// Riverpod providers exposing each repository, bound to the current
/// [SessionContext] and the local Drift database. Providers/screens depend on
/// these — never on DAOs directly (CLAUDE.md: providers talk to repositories).
/// Each repository gets the sync trigger as its onMutation hook, so every
/// local write pushes to the server immediately instead of waiting for the
/// next periodic/lifecycle sync.
final libraryRepositoryProvider = FutureProvider<LibraryRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return LibraryRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final ratingsRepositoryProvider = FutureProvider<RatingsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return RatingsRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final readingSessionsRepositoryProvider = FutureProvider<ReadingSessionsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return ReadingSessionsRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final readingNotesRepositoryProvider = FutureProvider<ReadingNotesRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return ReadingNotesRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final reviewsRepositoryProvider = FutureProvider<ReviewsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return ReviewsRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final tagsRepositoryProvider = FutureProvider<TagsRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return TagsRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

final lendingRepositoryProvider = FutureProvider<LendingRepository>((ref) async {
  final session = await ref.watch(sessionContextProvider.future);
  return LendingRepository(
    ref.watch(appDatabaseProvider),
    session,
    onMutation: ref.watch(syncTriggerProvider),
  );
});

/// The outbox for taps on a bookseller link. Not session-bound like the
/// repositories above: it stores no user id (the server files a batch under
/// whoever is signed in when it arrives), which is why sign-out clears it.
final buyClicksRepositoryProvider = Provider<BuyClicksRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return BuyClicksRepository(ref.watch(appDatabaseProvider), send: api.postBuyClicks);
});
