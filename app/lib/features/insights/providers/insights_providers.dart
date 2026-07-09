import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';

/// All library entries joined to their books — the raw data the insights screen
/// (S10) reduces into stats.
final libraryWithBooksProvider = FutureProvider.autoDispose<List<LibraryHit>>((ref) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.allWithBooks();
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
