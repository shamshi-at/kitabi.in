import 'package:flutter/material.dart';

import '../../../core/format_duration.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../session_pages.dart';

/// One sitting in a reading log — the row shared by the book page's reading-log
/// sheet and the stop surfaces' sittings log (R3), on the same `card`
/// background, so the two can't drift apart (CLAUDE.md's standing lesson).
///
/// Anatomy: the goldSoft icon circle, the caller's primary line (a day label or
/// a clock span) over the pages the sitting moved through, the duration and the
/// +N gain on the right, and a delete for the stray micro-sessions (soft
/// delete, available from both logs). A sitting with no page noted is greyed,
/// never dropped — the record must not imply the reader failed to do something.
class SessionLogRow extends StatelessWidget {
  const SessionLogRow({
    super.key,
    required this.session,
    required this.primary,
    required this.onDelete,
    this.highlight = false,
    this.divider = true,
  });

  final ReadingSession session;

  /// The row's first line — the caller formats it (a day label in the sittings
  /// log, the clock span in the book page's log).
  final String primary;

  final Future<void> Function() onDelete;

  /// Marks the sitting just logged (goldSoft wash).
  final bool highlight;

  /// Bottom hairline — off for the last row of a clipped card.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ps = session.pageStart;
    final pe = session.pageEnd;
    final noted = ps != null && pe != null;
    final pages = (ps != null && pe != null && pe > ps)
        ? l10n.bookLogPages(ps, pe)
        : l10n.bookLogNoPages;
    final gained = sessionPagesRead(session);

    return Container(
      decoration: BoxDecoration(
        color: highlight ? AppColors.goldSoft : null,
        border: divider ? Border(bottom: BorderSide(color: AppColors.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Opacity(
        opacity: noted ? 1 : .55,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: AppColors.goldSoft, shape: BoxShape.circle),
              child: Icon(Icons.timelapse, size: 15, color: AppColors.gold),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primary,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(pages, style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDuration(Duration(seconds: session.durationSeconds)),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.oxblood,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (gained != null)
                  Semantics(
                    label: l10n.bookLogPagesReadA11y(gained),
                    child: ExcludeSemantics(
                      child: Text(
                        l10n.bookLogPagesRead(gained),
                        style: TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.moss,
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.inkSoft),
              tooltip: l10n.bookLogDelete,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
