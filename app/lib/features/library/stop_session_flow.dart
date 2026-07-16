import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/haptics.dart';
import '../../data/repositories/repository_providers.dart';
import '../../l10n/app_localizations.dart';
import 'providers/reading_timer_providers.dart';

/// Stop the running reading session and log it, then offer to note the page
/// reached — the "quick stop" used by every surface that shows a live session
/// outside the full timer screen (the mini-bar, and Home's currently-reading
/// card). Shared rather than duplicated so those surfaces can't drift apart:
/// stopping from one must log exactly what stopping from the other does.
///
/// Quick-stopping used to only show a snackbar, with no way to note the page —
/// unlike the timer screen's wax-seal face, which always asks. This closes
/// that gap with the same field/skip pattern (owner report, 15 Jul 2026): the
/// dialog title doubles as the "session logged" confirmation, and "Skip"
/// leaves progress untouched.
Future<void> quickStopSession(BuildContext context, WidgetRef ref) async {
  Haptics.success();
  // The book/page-count come from the active session's own provider, which
  // goes null the instant stop() clears the session — so they must be read
  // before stopping, not after.
  final activeBook = ref.read(activeSessionBookProvider);
  final currentPage = activeBook?.entry.currentPage;
  final pageCount = activeBook?.book?.pageCount;
  final logged = await ref.read(activeSessionProvider.notifier).stop();
  ref.invalidate(weeklyReadingSecondsProvider);
  if (logged == null || !context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: currentPage?.toString() ?? '');
  final page = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        l10n.timerMiniBarStopped(formatDuration(Duration(seconds: logged.durationSeconds))),
      ),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.timerPageFieldLabel),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              decoration: InputDecoration(hintText: l10n.timerPageFieldHint),
            ),
          ),
          if (pageCount != null) ...[
            const SizedBox(width: 8),
            Text(l10n.timerPageFieldOf(pageCount)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.timerPageDialogSkip),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())),
          child: Text(l10n.bookSave),
        ),
      ],
    ),
  );
  if (page == null || page == currentPage || !context.mounted) return;
  final sessionsRepo = await ref.read(readingSessionsRepositoryProvider.future);
  await sessionsRepo.updateSessionPageEnd(logged.sessionId, page);
  final libraryRepo = await ref.read(libraryRepositoryProvider.future);
  await libraryRepo.updateProgress(logged.libraryEntryId, currentPage: page);
}
