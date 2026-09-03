import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';

/// What "I finished this book" actually changed — [pagesFilledTo] is the total
/// the progress was snapped to, and null when there was nothing to snap (no
/// page count, or the reader was already on the last page).
class FinishedBookResult {
  const FinishedBookResult({this.pagesFilledTo, this.justFinished = false});

  final int? pagesFilledTo;

  /// Whether *this* call is what turned the book Read.
  ///
  /// Every one of the surfaces below can be reached again on a book that is
  /// already finished, and this call is deliberately idempotent — but "the
  /// reader has just finished a book" is a one-time event, and the review
  /// nudge hangs off it. Without the distinction the nudge would have to be
  /// re-derived by each caller from an entry it read before calling, which is
  /// exactly the kind of duplicated rule this file exists to prevent.
  final bool justFinished;
}

/// Everything finishing a book means, in one place: the status, the date it
/// was finished, and the progress that has to agree with both.
///
/// Three surfaces call this — the book page's status row, the reading timer's
/// wax-seal face, and the shared stop sheet the mini-bar and Home card use.
/// That is exactly the shape of drift CLAUDE.md keeps warning about (the four
/// progress surfaces, the total-pages field), so the rules live here rather
/// than in whichever screen was written first.
///
/// Takes handles, not a `WidgetRef`: the mini-bar unmounts the moment a sitting
/// stops, and a `ref` read after that silently no-ops (19 Jul 2026). It also
/// reads the entry straight from the database rather than a stream provider,
/// for the same reason the timer's total-pages save had to — a provider that
/// hasn't emitted on this route hands back nothing.
Future<FinishedBookResult> markBookFinished({
  required AppDatabase db,
  required LibraryRepository repo,
  required String libraryEntryId,
}) async {
  final entry = await db.libraryEntriesDao.getById(libraryEntryId);
  if (entry == null) return const FinishedBookResult();

  final justFinished = entry.status != 'read';
  if (justFinished) {
    await repo.updateStatus(libraryEntryId, 'read');
  }
  // Never re-stamp a book that was already finished once — the original date
  // is the true one, and this can be reached again from any of the three
  // surfaces.
  if (entry.finishDate == null) {
    await repo.updateProgress(libraryEntryId, finishDate: DateTime.now());
  }

  // Finishing a book means you read all of it: leaving progress at p. 27 of
  // 200 on a book marked Read is a contradiction the reader would have to go
  // and fix by hand.
  final book = await db.cachedBooksDao.getByEditionId(entry.editionId);
  final total = book?.pageCount;
  if (total != null && total > 0 && (entry.currentPage ?? 0) < total) {
    await repo.updateProgress(libraryEntryId, currentPage: total);
    return FinishedBookResult(pagesFilledTo: total, justFinished: justFinished);
  }
  return FinishedBookResult(justFinished: justFinished);
}

/// Reaching the last page and tapping "Read" ought to mean the same thing.
/// Call this right after any plain page-number write (timer, quick-stop,
/// manual-log, pencil) — if progress now sits at or past the book's known
/// total and the entry isn't already Read, this finishes it exactly the way
/// [markBookFinished] does for an explicit "I finished this book" tap. A no-op
/// when the total isn't known yet: silence, not a guess, is the only honest
/// answer to "did they finish?" when the catalogue can't say how long the
/// book is.
Future<bool> autoFinishIfOnLastPage({
  required AppDatabase db,
  required LibraryRepository repo,
  required String libraryEntryId,
}) async {
  final entry = await db.libraryEntriesDao.getById(libraryEntryId);
  if (entry == null || entry.status == 'read') return false;
  final page = entry.currentPage;
  if (page == null) return false;
  final book = await db.cachedBooksDao.getByEditionId(entry.editionId);
  final total = book?.pageCount;
  if (total == null || total <= 0 || page < total) return false;
  await markBookFinished(db: db, repo: repo, libraryEntryId: libraryEntryId);
  return true;
}
