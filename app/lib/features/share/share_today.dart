import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../l10n/app_localizations.dart';
import '../insights/period.dart';
import '../insights/period_summary.dart';
import '../insights/share_composition.dart';
import 'presentation/share_period_sheet.dart';

/// Open the share sheet for **today's** reading, from wherever the reader has
/// just finished reading.
///
/// The Today card itself is not new — `composePeriodShare` has built it since
/// the graphical card family landed (26 Aug 2026). What it had was one door:
/// Insights → the Today chip → the wax seal. Apple Books puts its daily card
/// in front of the reader at the moment they stop reading, and that is the
/// moment Kitabi had nothing (owner report, 8 Sep 2026). So the door goes on
/// the surfaces that *end a sitting* — the timer's wax-seal face and the
/// quick-stop sheet — and it goes on **both**, because a feature added to one
/// entry point and not the others is the shape of half this file's history
/// (the 19 Jul four-progress-surfaces lesson).
///
/// Takes a [ProviderContainer] and a context rather than a `WidgetRef` for the
/// same reason [maybePromptForReview] does: the quick-stop sheet closes itself
/// on the way here, and a `ref` belonging to a widget that has unmounted reads
/// nothing at all (19 Jul 2026).
///
/// Reads its data from the repositories directly rather than from the Insights
/// stream providers: those are `autoDispose`, and a read with no listener hands
/// back either nothing or a disposed future on a screen that never watched them.
Future<void> shareTodaysReading(
  BuildContext context,
  ProviderContainer container, {
  DateTime? now,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);

  final PeriodSummary summary;
  try {
    final library = await container.read(libraryRepositoryProvider.future);
    final sessions = await container.read(readingSessionsRepositoryProvider.future);
    final range = rangeFor(InsightsPeriod.today, now: now);
    summary = computePeriodSummary(
      period: InsightsPeriod.today,
      range: range,
      // The whole history, not just today's: the card's lamp row is the last
      // seven days and the streak reaches back further still.
      sessions: await sessions.watchSessionsSince(DateTime(2000)).first,
      hits: await library.watchWithBooks().first,
      // Ratings badge the finished-books strip, which the Today card has no
      // room for — nothing here reads them.
      ratingsByWorkId: const {},
      now: now,
    );
  } catch (_) {
    // Reading the reader's own database failed. Say so rather than opening an
    // empty sheet — a share that silently does nothing is the bug this whole
    // area keeps relearning (6 Sep 2026).
    messenger?.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    return;
  }

  final share = composePeriodShare(
    l10n: l10n,
    period: InsightsPeriod.today,
    range: rangeFor(InsightsPeriod.today, now: now),
    summary: summary,
    now: now,
  );
  // Null means the day holds nothing true to send — the honest-states rule the
  // wax seal already follows by simply not being drawn.
  if (share == null) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.shareTodayNothingYet)));
    return;
  }
  if (!context.mounted) return;
  await showSharePeriodSheet(
    context,
    dataBuilder: share.dataBuilder,
    initialCaption: share.caption,
    recapKey: share.recapKey,
    canNameBooks: share.canNameBooks,
    initialFormat: share.initialFormat,
    title: l10n.shareTodaySheetTitle,
  );
}
