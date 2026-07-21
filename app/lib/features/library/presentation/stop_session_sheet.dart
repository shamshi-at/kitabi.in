import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format_duration.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/sync/sync_providers.dart';
import '../providers/library_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'note_page.dart';
import 'session_page_entry.dart';

/// What the reader entered before the sheet closed.
class StopSessionResult {
  const StopSessionResult({this.page, this.total});

  final int? page;

  /// Only set when the book had no page count and the reader supplied one.
  final int? total;
}

/// Sittings for one book, newest first — powers R3's log. No new query: the
/// DAO already orders by startedAt and the book page reads the same stream.
final stopSessionsProvider =
    StreamProvider.autoDispose.family<List<ReadingSession>, String>((ref, entryId) {
  return ref.watch(appDatabaseProvider).readingSessionsDao.watchForEntry(entryId);
});

/// R1/R2/R3 — the sheet shown the moment a session stops, from every surface
/// that isn't the full timer screen (the mini-bar and Home's currently-reading
/// card). Replaces an `AlertDialog` whose whole content was one cramped `Row`.
///
/// Returns null when the reader skips or dismisses — the session is already
/// logged by then, so skipping costs nothing but the page.
Future<StopSessionResult?> showStopSessionSheet(
  BuildContext context, {
  required String libraryEntryId,
  required String loggedSessionId,
  required Duration duration,
  required String? title,
  required String? coverUrl,
  required int? currentPage,
  required int? pageCount,
  required int? pageStart,
}) {
  return showModalBottomSheet<StopSessionResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _StopSessionSheet(
      libraryEntryId: libraryEntryId,
      loggedSessionId: loggedSessionId,
      duration: duration,
      title: title,
      coverUrl: coverUrl,
      currentPage: currentPage,
      pageCount: pageCount,
      pageStart: pageStart,
    ),
  );
}

class _StopSessionSheet extends ConsumerStatefulWidget {
  const _StopSessionSheet({
    required this.libraryEntryId,
    required this.loggedSessionId,
    required this.duration,
    required this.title,
    required this.coverUrl,
    required this.currentPage,
    required this.pageCount,
    required this.pageStart,
  });

  final String libraryEntryId;

  /// The sitting that just ended — excluded from the "last time" line.
  final String loggedSessionId;
  final Duration duration;
  final String? title;
  final String? coverUrl;
  final int? currentPage;
  final int? pageCount;
  final int? pageStart;

  @override
  ConsumerState<_StopSessionSheet> createState() => _StopSessionSheetState();
}

class _StopSessionSheetState extends ConsumerState<_StopSessionSheet> {
  late final _pageController =
      TextEditingController(text: widget.currentPage?.toString() ?? '');
  final _totalController = TextEditingController();
  final _pageFocusNode = FocusNode();
  PageEntryError? _error;
  bool _showingLog = false;

  @override
  void dispose() {
    _pageController.dispose();
    _totalController.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      StopSessionResult(
        page: int.tryParse(_pageController.text.trim()),
        total: int.tryParse(_totalController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(stopSessionsProvider(widget.libraryEntryId)).valueOrNull ??
        const <ReadingSession>[];
    final sessionNotes =
        ref.watch(sessionNotesProvider(widget.loggedSessionId)).valueOrNull ??
            const <ReadingNote>[];

    if (_showingLog) {
      return SessionsLog(
        title: widget.title,
        sessions: sessions,
        onBack: () => setState(() => _showingLog = false),
      );
    }

    // The most recent *previous* sitting. The one just logged is already in the
    // stream (newest first) and must be excluded by id — filtering on "has a
    // page" would work today only because its page is written after this sheet
    // closes, which is exactly the kind of assumption that breaks later.
    final last = sessions
        .where((s) => s.id != widget.loggedSessionId && s.pageEnd != null)
        .firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TypesetCover(
                  title: widget.title ?? '',
                  coverUrl: widget.coverUrl,
                  width: 30,
                  height: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check, size: 12, color: AppColors.moss),
                          const SizedBox(width: 4),
                          Text(
                            l10n.stopSessionLogged.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.moss,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatDuration(widget.duration)} · ${widget.title ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Divider(height: 1, color: AppColors.line),
            ),
            SessionPageEntry(
              pageController: _pageController,
              totalController: _totalController,
              pageFocusNode: _pageFocusNode,
              pageCount: widget.pageCount,
              pageStart: widget.pageStart,
              duration: widget.duration,
              onValidityChanged: (err) => setState(() => _error = err),
              onOpenLog:
                  sessions.isEmpty ? null : () => setState(() => _showingLog = true),
              lastSessionLine: last == null
                  ? null
                  : formatLastSessionLine(
                      l10n,
                      endedAt: last.endedAt,
                      durationSeconds: last.durationSeconds,
                      pageStart: last.pageStart,
                      pageEnd: last.pageEnd,
                    ),
            ),
            // N3 — what this sitting already holds. They were saved as they
            // were written, so nothing here is at stake; Skip says so below.
            if (sessionNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.notesSectionThisSitting(sessionNotes.length).toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EEDC),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFE8DCC0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final note in sessionNotes)
                      _StopNoteRow(note: note, entryId: widget.libraryEntryId),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<bool>(
                          builder: (_) => NotePage(
                            libraryEntryId: widget.libraryEntryId,
                            bookTitle: widget.title,
                            sessionId: widget.loggedSessionId,
                            currentPage: int.tryParse(_pageController.text.trim()),
                          ),
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: const Color(0xFFE8DCC0))),
                        ),
                        child: Text(
                          '+ ${l10n.notesClosingThought}',
                          style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // A page that would walk progress backwards can't be saved —
                // the entry widget says why, right under the number.
                onPressed: _error != null ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oxblood,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(l10n.stopSavePage),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  // Skip says what it costs rather than being a bare word.
                  sessionNotes.isNotEmpty
                      ? l10n.stopSkipNotesSafe(sessionNotes.length)
                      : (widget.currentPage != null
                          ? l10n.stopSkipWithPage(widget.currentPage!)
                          : l10n.stopSkipNoPage),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R3 — every sitting for this book, newest first. Reached from the anchor
/// line's "Log ›", never shown by default: most stops don't need it, but when
/// the reader can't remember where they were it's the only thing that helps.
class SessionsLog extends StatelessWidget {
  const SessionsLog({
    super.key,
    required this.title,
    required this.sessions,
    required this.onBack,
  });

  final String? title;
  final List<ReadingSession> sessions;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalSeconds = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final totalPages = sessions.fold<int>(0, (sum, s) {
      final from = s.pageStart;
      final to = s.pageEnd;
      return (from != null && to != null && to > from) ? sum + (to - from) : sum;
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.stopSessionsTitle(title ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.stopSessionsSummary(
                formatDuration(Duration(seconds: totalSeconds)),
                totalPages,
                sessions.length,
              ),
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.line),
                  itemBuilder: (context, i) => _SessionRow(
                    session: sessions[i],
                    highlight: i == 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              l10n.stopSessionsSkipNote,
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.45),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l10n.stopBackToPage),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.highlight});

  final ReadingSession session;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final from = session.pageStart;
    final to = session.pageEnd;
    final delta = (from != null && to != null && to > from) ? to - from : null;
    final noted = from != null && to != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      color: highlight ? AppColors.goldSoft : null,
      // A skipped sitting is still a sitting — greyed, never dropped, so the
      // record doesn't imply the reader failed to do something.
      child: Opacity(
        opacity: noted ? 1 : .55,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayLabel(context, session.endedAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatDuration(Duration(seconds: session.durationSeconds)),
                    style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (noted)
              Text(
                'p. $from → $to',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
              )
            else
              Text(
                l10n.stopSessionsNoPage,
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            SizedBox(
              width: 34,
              child: Text(
                delta != null ? '+$delta' : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: delta != null ? AppColors.moss : AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dayLabel(BuildContext context, DateTime endedAt) {
    final l10n = AppLocalizations.of(context)!;
    final local = endedAt.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.timerToday;
    if (diff == 1) return l10n.timerYesterday;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }
}


/// One already-saved note on the stop sheet — tappable, because the reader may
/// want to finish a thought they jotted mid-sentence.
class _StopNoteRow extends StatelessWidget {
  const _StopNoteRow({required this.note, required this.entryId});

  final ReadingNote note;
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final pages = note.pageStart == null
        ? null
        : (note.pageEnd == null
            ? 'p. ${note.pageStart}'
            : 'p. ${note.pageStart}-${note.pageEnd}');
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => NotePage(libraryEntryId: entryId, existing: note),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, height: 1.45),
              ),
            ),
            if (pages != null) ...[
              const SizedBox(width: 8),
              Text(pages, style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
            ],
          ],
        ),
      ),
    );
  }
}
