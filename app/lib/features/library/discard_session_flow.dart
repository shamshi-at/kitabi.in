import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format_duration.dart';
import '../../core/haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'providers/library_providers.dart';
import 'providers/reading_timer_providers.dart';

/// Throw the running sitting away — the reader started the clock and then
/// didn't read (owner request, 12 Sep 2026). Nothing is logged.
///
/// **One flow, every door**, for the reason every stop surface in this app has
/// eventually taught: the timer's watch face and the mini-bar are written in
/// different files by different hands months apart, and the moment the
/// question is asked in two places the two copies start answering it
/// differently — a confirmation that names the notes on one and not the other,
/// a snackbar here and silence there.
///
/// Returns whether a sitting was actually discarded. [onConfirmed] fires
/// synchronously between the reader saying yes and the discard itself, for a
/// caller that has to brace before the session vanishes — the timer screen
/// leaves on its own when it sees an empty session, so it has to know a
/// deliberate departure is already under way (see `_leaving` there).
Future<bool> discardSessionFlow(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onConfirmed,
}) async {
  final active = ref.read(activeSessionProvider);
  if (active == null) return false;
  final noteCount =
      ref.read(sessionNotesProvider(active.id)).valueOrNull?.length ?? 0;
  final elapsed = DateTime.now().difference(active.startedAt);

  // Every handle captured before the first await. `discard()` clears the
  // session, and the mini-bar is built *only* while one is live — it and its
  // `ref` are gone before this function returns, so a read through them
  // afterwards silently no-ops and a `context.mounted` guard returns in
  // silence (19 Jul, 31 Jul 2026). A root navigator outlives every caller.
  final notifier = ref.read(activeSessionProvider.notifier);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context)!;
  final discardedMessage = l10n.timerDiscarded;

  final confirmed = await _confirm(
    navigator.context,
    l10n: l10n,
    elapsed: elapsed,
    noteCount: noteCount,
  );
  if (confirmed != true) return false;
  onConfirmed?.call();
  Haptics.success();

  final discarded = await notifier.discard();
  // Said out loud, because the alternative is a timer that simply vanishes:
  // the one thing a reader needs to know here is that nothing was filed.
  if (discarded && navigator.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(discardedMessage)));
  }
  return discarded;
}

/// The question itself. Deliberately concrete: the elapsed time, because that
/// is what is being thrown away, and — when the sitting holds notes — the
/// promise that those are not, because a reader who jotted a thought
/// mid-sitting has every reason to fear this button otherwise.
Future<bool?> _confirm(
  BuildContext context, {
  required AppLocalizations l10n,
  required Duration elapsed,
  required int noteCount,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(l10n.timerDiscardTitle, style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.timerDiscardBody(formatDuration(elapsed)),
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
          ),
          if (noteCount > 0) ...[
            const SizedBox(height: 10),
            Text(
              l10n.timerDiscardNotesKept(noteCount),
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.timerDiscardKeep),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            l10n.timerDiscardConfirm,
            style: TextStyle(color: AppColors.oxblood),
          ),
        ),
      ],
    ),
  );
}
