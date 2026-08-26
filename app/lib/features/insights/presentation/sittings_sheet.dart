import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/format_duration.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_grabber.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../period.dart';
import '../providers/insights_providers.dart';

/// B5 — the sittings behind the number. Opened by the almanac's Time read /
/// Pages turned / Sittings rows (and a crowded day's "and N more"): the same
/// rows the per-book reading log shows, joined *across* books for one
/// window. Titles are doors to the book page; long-press removes a stray
/// sitting with the reading log's own soft delete. Nothing here is a new
/// record type — one query over reading_sessions the app already syncs.
Future<void> showSittingsSheet(
  BuildContext context, {
  required PeriodRange range,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SittingsSheet(range: range, title: title),
  );
}

class _SittingsSheet extends ConsumerWidget {
  const _SittingsSheet({required this.range, required this.title});

  final PeriodRange range;
  final String title;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ReadingSession session) async {
    final l10n = AppLocalizations.of(context)!;
    // Capture before the await — the sheet may be closing while the dialog is
    // up, and a post-await ref on an unmounted element silently no-ops.
    final repo = await ref.read(readingSessionsRepositoryProvider.future);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookLogDeleteConfirmTitle),
        content: Text(
          l10n.bookLogDeleteConfirmBody(formatDuration(Duration(seconds: session.durationSeconds))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.bookLogDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.deleteSession(session.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(readingSessionsStreamProvider).valueOrNull ?? const <ReadingSession>[];
    final hits = ref.watch(libraryWithBooksProvider).valueOrNull ?? const <LibraryHit>[];
    final byEntryId = {for (final h in hits) h.entry.id: h};

    final inRange = sessions
        .where((s) => s.deletedAt == null && range.contains(s.startedAt))
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final books = {for (final s in inRange) s.libraryEntryId}.length;
    final totalSeconds = inRange.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final multiDay = range.lengthInDays > 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetGrabber(),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            l10n.insightsSittingsSummary(
              inRange.length,
              books,
              formatDuration(Duration(seconds: totalSeconds)),
            ),
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: inRange.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        l10n.insightsSittingsEmpty,
                        style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (i, session) in inRange.indexed) ...[
                        if (multiDay &&
                            (i == 0 ||
                                !_sameDay(inRange[i - 1].startedAt, session.startedAt)))
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 2),
                            child: Text(
                              DateFormat('EEEE · d MMM').format(session.startedAt.toLocal()),
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        _SittingRow(
                          session: session,
                          hit: byEntryId[session.libraryEntryId],
                          onLongPress: () => _confirmDelete(context, ref, session),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.insightsSittingsHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _SittingRow extends StatelessWidget {
  const _SittingRow({required this.session, required this.hit, required this.onLongPress});

  final ReadingSession session;
  final LibraryHit? hit;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final span = formatSessionSpan(
      context,
      l10n,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
    );
    final pageLine = switch ((session.pageStart, session.pageEnd)) {
      (final int from?, final int to?) when to > from => 'p. $from → $to · +${to - from}',
      (_, final int to?) => l10n.insightsPageN(to),
      _ => null,
    };
    final book = hit;
    return InkWell(
      onLongPress: onLongPress,
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.book.workId, book.book.editionId)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                span,
                style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book?.book.title ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fraunces(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: book == null ? AppColors.ink : AppColors.oxblood,
                    ),
                  ),
                  if (pageLine != null)
                    Text(pageLine, style: TextStyle(fontSize: 9, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDuration(Duration(seconds: session.durationSeconds)),
              style: GoogleFonts.fraunces(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
