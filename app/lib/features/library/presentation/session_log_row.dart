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
/// a clock span, with a slate "Auto-stopped" pill when the safety net rather
/// than the reader closed it) over the pages the sitting moved through, the
/// duration and the +N gain on the right, then an edit (correct the end time
/// and page) and a delete for the stray micro-sessions (soft delete), both
/// available from both logs. A sitting with no page noted is greyed, never
/// dropped — the record must not imply the reader failed to do something.
class SessionLogRow extends StatelessWidget {
  const SessionLogRow({
    super.key,
    required this.session,
    required this.primary,
    required this.onDelete,
    required this.onEdit,
    this.highlight = false,
    this.divider = true,
  });

  final ReadingSession session;

  /// The row's first line — the caller formats it (a day label in the sittings
  /// log, the clock span in the book page's log).
  final String primary;

  final Future<void> Function() onDelete;

  /// Corrects the sitting's end time (and the page it noted) — the fix for a
  /// sitting the auto-stop safety net closed while the reader kept reading
  /// unnoticed (owner report, 23 Aug 2026). The caller recomputes duration
  /// from [session.startedAt], since only it has the repository in hand.
  final Future<void> Function(DateTime endedAt, int? pageEnd) onEdit;

  /// Marks the sitting just logged (goldSoft wash).
  final bool highlight;

  /// Bottom hairline — off for the last row of a clipped card.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ps = session.pageStart;
    final pe = session.pageEnd;
    // What the reader noted is the *end* page — where they got to. A start page
    // is context the app supplies (the entry's progress when the clock began),
    // and the first sitting on a book with no recorded progress simply has
    // none. Requiring both to show anything meant that first sitting read as
    // "Page not noted" while the progress bar showed the very page the reader
    // had just typed (owner report, 31 Jul 2026) — and so did a sitting that
    // ended where it began, whose page the 26 Jul fix had just made sure to
    // record. The range is the richer line when there is one; the end page
    // alone is still the fact this row exists to carry.
    final noted = pe != null;
    final pages = pe == null
        ? l10n.bookLogNoPages
        : (ps != null && pe > ps)
            ? l10n.bookLogPages(ps, pe)
            : l10n.bookLogPageEnded(pe);
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          primary,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      // Flags a sitting the safety net closed rather than the
                      // reader tapping Stop — its end time (and so its page)
                      // may not be where the reader actually stopped, which is
                      // exactly what the edit button beside this row is for.
                      if (session.autoStopped) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.slate.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            l10n.bookLogAutoStopped.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .4,
                              color: AppColors.slate,
                            ),
                          ),
                        ),
                      ],
                    ],
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
              icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.inkSoft),
              tooltip: l10n.bookLogEdit,
              onPressed: () => _editSession(context, l10n),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.inkSoft),
              tooltip: l10n.bookLogDelete,
              // Confirm here, in the shared row, so every log surface gets the
              // guard — a per-caller dialog would drift (CLAUDE.md, 19 Jul 2026).
              onPressed: () => _confirmDelete(context, l10n, noted ? pages : null),
            ),
          ],
        ),
      ),
    );
  }

  /// A sitting is synced history, not a draft — deleting one deserves a pause.
  /// The body names what goes ("30m · p. 244 → 269"), so a mis-tap on the
  /// wrong row is catchable before it happens.
  Future<void> _confirmDelete(
      BuildContext context, AppLocalizations l10n, String? pages) async {
    final summary = [
      formatDuration(Duration(seconds: session.durationSeconds)),
      ?pages,
    ].join(' · ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(l10n.bookLogDeleteConfirmTitle, style: const TextStyle(fontSize: 16)),
        content: Text(
          l10n.bookLogDeleteConfirmBody(summary),
          style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.bookLogDelete, style: TextStyle(color: AppColors.oxblood)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onDelete();
  }

  /// Lets the reader correct a sitting's end time and end page — the fix for
  /// one the safety net auto-stopped while they kept reading unnoticed, but
  /// offered on every row since a fat-fingered page or a stop tapped a few
  /// minutes late is just as real a mistake (owner report, 23 Aug 2026).
  Future<void> _editSession(BuildContext context, AppLocalizations l10n) async {
    final start = session.startedAt.toLocal();
    var ended = session.endedAt.toLocal();
    if (ended.isBefore(start)) ended = start;
    final pageController =
        TextEditingController(text: session.pageEnd?.toString() ?? '');

    final result = await showDialog<(DateTime, int?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final tooEarly = !ended.isAfter(start);
          final tooLate = ended.isAfter(DateTime.now());
          final error = tooEarly
              ? l10n.bookLogEditEndBeforeStart
              : tooLate
                  ? l10n.bookLogEditEndInFuture
                  : null;
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: Text(l10n.bookLogEditTitle, style: const TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session.autoStopped)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      l10n.bookLogAutoStoppedHint,
                      style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final now = DateTime.now();
                    final pickedDate = await showDatePicker(
                      context: ctx,
                      initialDate: ended,
                      firstDate: start,
                      lastDate: now,
                    );
                    if (pickedDate == null || !ctx.mounted) return;
                    final pickedTime = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(ended),
                    );
                    if (pickedTime == null) return;
                    setDialogState(() => ended = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        ));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: AppColors.inkSoft),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.bookLogEditEndedAt(_fmtDateTime(ended)),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          l10n.bookChangeDate,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.oxblood,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      error,
                      style: TextStyle(fontSize: 11.5, color: AppColors.oxbloodDeep),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: pageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.bookLogEditPageLabel),
                  onTap: () => pageController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: pageController.text.length,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
              TextButton(
                onPressed: error != null
                    ? null
                    : () => Navigator.pop(
                          ctx,
                          (ended, int.tryParse(pageController.text.trim())),
                        ),
                child: Text(l10n.bookSave),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final (newEndedAt, newPageEnd) = result;
    await onEdit(newEndedAt, newPageEnd);
  }
}

String _fmtDateTime(DateTime local) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day} ${months[local.month - 1]}, $hour12:$minute $period';
}
