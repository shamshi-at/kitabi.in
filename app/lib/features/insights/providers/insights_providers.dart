import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../reading_pace.dart';

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

/// The same history, watched. Every "time to finish" estimate hangs off this,
/// and sittings are written from four routes that don't own the screens
/// showing the estimate — a one-shot fetch would leave a book page quoting a
/// pace measured before the sitting the reader just logged.
final readingSessionsStreamProvider =
    StreamProvider.autoDispose<List<ReadingSession>>((ref) async* {
  final repo = await ref.watch(readingSessionsRepositoryProvider.future);
  yield* repo.watchSessionsSince(DateTime(2000));
});

/// The reader's own reading pace (Area 13). One computation for the whole app:
/// it depends on the *reader*, not on which book page is open, so every
/// estimate — book page, unowned catalogue page, library filter — watches this
/// single provider rather than re-deriving pace per book.
///
/// Returns [ReadingPace.empty] while either stream is still loading, which the
/// UI renders as the honest "we don't know your pace yet" state rather than a
/// spinner in the middle of a book page.
final readingPaceProvider = Provider.autoDispose<ReadingPace>((ref) {
  final sessions = ref.watch(readingSessionsStreamProvider).valueOrNull;
  final hits = ref.watch(libraryWithBooksProvider).valueOrNull;
  if (sessions == null || hits == null) return ReadingPace.empty;
  return computeReadingPace(sessions: sessions, hits: hits);
});

/// Pace measured on one book alone — the better predictor once a reader has
/// actually sat with it (P2). Null until the book has [minSessionsForPace]
/// sittings that recorded a page range, so a single unusual evening never
/// overrides the reader's own average.
///
/// Carries its own sample count: a sentence about *this book* that quotes the
/// global sitting count is simply false, and it looks plausible enough to ship.
final bookPaceProvider =
    Provider.autoDispose.family<({double pagesPerHour, int sessions})?, String>(
        (ref, libraryEntryId) {
  final sessions = ref.watch(readingSessionsStreamProvider).valueOrNull;
  if (sessions == null) return null;
  final own = sessions.where((s) => s.libraryEntryId == libraryEntryId).toList();
  final measurable = measurableSessions(own);
  if (measurable < minSessionsForPace) return null;
  final pace = pagesPerHourOf(own);
  return pace == null ? null : (pagesPerHour: pace, sessions: measurable);
});
