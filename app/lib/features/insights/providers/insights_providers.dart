import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';

/// All library entries joined to their books — the raw data the insights screen
/// (S10) reduces into stats.
///
/// Reactive (17 Jul 2026): this was a one-shot fetch, so finishing a book or
/// filling in a page count left Insights showing stale numbers until the tab
/// was rebuilt — and Insights is an always-alive shell branch that rarely is.
/// Watching the joined stream makes the write its own refresh.
final libraryWithBooksProvider = StreamProvider.autoDispose<List<LibraryHit>>((ref) async* {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  yield* repo.watchWithBooks();
});

/// The personal reading goal (books/year), device-local for now.
final readingGoalProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.readingGoal();
});

/// Every reading session ever logged — small enough a dataset (minutes-long
/// sessions, not one per page) that computing weekly/narrative stats client
/// side over the full history beats adding a second, date-scoped fetch path.
final allReadingSessionsProvider = FutureProvider.autoDispose<List<ReadingSession>>((ref) async {
  final repo = await ref.watch(readingSessionsRepositoryProvider.future);
  return repo.sessionsSince(DateTime(2000));
});
