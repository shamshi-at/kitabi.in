import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/sync/sync_providers.dart';
import 'providers/reading_timer_providers.dart';
import 'presentation/stop_session_sheet.dart';
import 'reading_progress.dart';

/// Stop the running reading session and log it, then offer to note the page
/// reached — the "quick stop" used by every surface that shows a live session
/// outside the full timer screen (the mini-bar, and Home's currently-reading
/// card). Shared rather than duplicated so those surfaces can't drift apart:
/// stopping from one must log exactly what stopping from the other does.
///
/// Quick-stopping used to only show a snackbar, with no way to note the page —
/// unlike the timer screen's wax-seal face, which always asks. This closes
/// that gap with the same field/skip pattern (owner report, 15 Jul 2026), and
/// since 21 Jul 2026 both surfaces render the *same* [SessionPageEntry]: one
/// big number you can tap to overwrite, -/+ for small corrections, an anchor
/// line saying where the sitting began, and a Skip that names what it costs.
/// When the book has no page count it also asks for the total, so progress can
/// become a percentage (owner report, 17 Jul 2026).
Future<void> quickStopSession(BuildContext context, WidgetRef ref) async {
  Haptics.success();
  // The book/page-count come from the active session's own provider, which
  // goes null the instant stop() clears the session — so they must be read
  // before stopping, not after.
  final activeBook = ref.read(activeSessionBookProvider);
  final currentPage = activeBook?.entry.currentPage;
  final pageCount = activeBook?.book?.pageCount;
  // Capture every provider-derived handle we'll need AFTER the stop, up front.
  // stop() clears the session, which unmounts the mini-bar — often this call's
  // caller — and invalidates its `ref`; reads through it after the page dialog
  // silently no-op'd, so a page typed while stopping from the mini-bar never
  // reached the entry (owner report, 19 Jul 2026: the book stayed "Not started"
  // even though the session logged). The captured db/repos outlive the widget.
  final db = ref.read(appDatabaseProvider);
  final api = ref.read(apiClientProvider);
  final notifier = ref.read(activeSessionProvider.notifier);
  final container = ProviderScope.containerOf(context, listen: false);
  final sessionsRepo = await ref.read(readingSessionsRepositoryProvider.future);
  final libraryRepo = await ref.read(libraryRepositoryProvider.future);

  final logged = await notifier.stop();
  container.invalidate(weeklyReadingSecondsProvider);
  if (logged == null || !context.mounted) return;

  // R1/R2 — a sheet, not an AlertDialog whose whole content was one cramped
  // Row. The entry block is shared with the timer's wax-seal face so the two
  // can't drift (CLAUDE.md: the four progress surfaces have drifted before).
  final result = await showStopSessionSheet(
    context,
    libraryEntryId: logged.libraryEntryId,
    loggedSessionId: logged.sessionId,
    duration: Duration(seconds: logged.durationSeconds),
    title: activeBook?.book?.title,
    coverUrl: activeBook?.book?.coverUrl,
    currentPage: currentPage,
    pageCount: pageCount,
    pageStart: logged.pageStart ?? currentPage,
  );
  if (result == null) return; // skipped / dismissed

  // Everything below runs through the captured handles, never `ref` — by now
  // the mini-bar may be gone. The total the reader supplied belongs to the
  // shared Edition (mirror locally + push to the catalog); the edition id comes
  // from the logged entry directly, not a pre-stop snapshot that may be null.
  final total = result.total;
  if (pageCount == null && total != null) {
    final entry = await db.libraryEntriesDao.getById(logged.libraryEntryId);
    if (entry != null) await saveBookTotalPages(db, api, entry.editionId, total);
  }

  final page = result.page;
  if (page == null || page == currentPage) return;
  await sessionsRepo.updateSessionPageEnd(logged.sessionId, page);
  await libraryRepo.updateProgress(logged.libraryEntryId, currentPage: page);
}
