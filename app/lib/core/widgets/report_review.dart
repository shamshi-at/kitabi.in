import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../theme/app_theme.dart';

/// The small flag beside another reader's public review — one shared widget so
/// the three surfaces that show public reviews (book page, series card, public
/// profile) can't drift apart (CLAUDE.md: a feature added to one entry point
/// must be added to all of them). Renders nothing for the reader's own review:
/// editing or deleting it is the tool there, and the server refuses
/// self-reports anyway.
class ReportReviewButton extends ConsumerWidget {
  const ReportReviewButton({super.key, required this.reviewId, required this.reviewerId});

  final String reviewId;
  final String? reviewerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(sessionContextProvider).valueOrNull?.userId;
    // Own review — or identity not yet known, in which case showing a button
    // the server would refuse is worse than showing it a frame late.
    if (myId == null || reviewerId == null || reviewerId == myId) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.reportReviewTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showReportReviewSheet(context, ref, reviewId),
        child: Padding(
          // A generous invisible hit target around a deliberately quiet icon.
          padding: const EdgeInsets.fromLTRB(8, 2, 0, 8),
          child: Icon(Icons.flag_outlined, size: 14, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// One reason choice: the label the reader sees is localized, the value that
/// goes on the wire is a fixed English token so the moderation queue reads the
/// same word whatever locale the reporter used.
class _Reason {
  const _Reason(this.wire, this.label);

  final String wire;
  final String label;
}

/// Ask why, then file the report. Online-only and best-effort: the server
/// dedupes repeat reports, so failure handling is just an honest snackbar —
/// offline distinguished from a real error (CLAUDE.md, 15 Aug 2026).
Future<void> showReportReviewSheet(BuildContext context, WidgetRef ref, String reviewId) async {
  final l10n = AppLocalizations.of(context)!;
  // Captured before any await: the sheet outlives taps, but the row this was
  // launched from may not (CLAUDE.md, the quick-stop lesson).
  final api = ref.read(apiClientProvider);
  final messenger = ScaffoldMessenger.of(context);
  final reasons = [
    _Reason('Spam', l10n.reportReasonSpam),
    _Reason('Offensive', l10n.reportReasonOffensive),
    _Reason('Spoilers', l10n.reportReasonSpoilers),
    _Reason('Off-topic', l10n.reportReasonOffTopic),
    _Reason('Other', l10n.reportReasonOther),
  ];

  final chosen = await showModalBottomSheet<_Reason>(
    context: context,
    backgroundColor: AppColors.paper,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reportReviewTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.reportReviewSubtitle,
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 8),
            for (final reason in reasons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag_outlined, size: 18, color: AppColors.oxblood),
                title: Text(reason.label, style: const TextStyle(fontSize: 13.5)),
                onTap: () => Navigator.of(sheetContext).pop(reason),
              ),
          ],
        ),
      ),
    ),
  );
  if (chosen == null) return;

  Haptics.selection();
  try {
    await api.reportReview(reviewId, reason: chosen.wire);
    messenger.showSnackBar(SnackBar(content: Text(l10n.reportReviewThanks)));
  } catch (err) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(isOfflineError(err) ? l10n.reportReviewOffline : l10n.reportReviewFailed),
      ),
    );
  }
}
