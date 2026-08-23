import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../providers/library_providers.dart';
import '../../../l10n/app_localizations.dart';
import 'session_log_row.dart';
import 'session_notes_block.dart';
import 'session_page_entry.dart';

/// What the reader entered before the sheet closed.
class StopSessionResult {
  const StopSessionResult({this.page, this.total, this.finished = false});

  final int? page;

  /// Only set when the book had no page count and the reader supplied one.
  final int? total;

  /// The reader closed the last page, not just the app — the caller applies
  /// [markBookFinished] on top of the ordinary page save. Deliberately part of
  /// this one shared result rather than a second sheet, so the mini-bar, the
  /// Home card and the timer all offer finishing in the same breath as
  /// stopping.
  final bool finished;
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
    // Uncapped, a long sittings list pushed the header under the status bar
    // (owner screenshot, 22 Jul 2026) — a modal sheet's SafeArea can't add top
    // padding it was never given.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
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
  // Both fields feed the Save button's enablement (an empty sheet has nothing
  // to save), so typing must rebuild.
  late final _pageController =
      TextEditingController(text: widget.currentPage?.toString() ?? '')
        ..addListener(_onFieldChanged);
  late final _totalController = TextEditingController()
    ..addListener(_onFieldChanged);
  final _pageFocusNode = FocusNode();
  PageEntryError? _error;
  bool _showingLog = false;

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _totalController.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _deleteSession(ReadingSession session) async {
    Haptics.selection();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final repo = await ref.read(readingSessionsRepositoryProvider.future);
    await repo.deleteSession(session.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.bookLogDeleted)));
  }

  Future<void> _editSession(ReadingSession session, DateTime endedAt, int? pageEnd) async {
    Haptics.selection();
    final repo = await ref.read(readingSessionsRepositoryProvider.future);
    await repo.correctSessionEnd(
      session.id,
      startedAt: session.startedAt,
      endedAt: endedAt,
      pageEnd: pageEnd,
    );
  }

  void _save() {
    Navigator.of(context).pop(
      StopSessionResult(
        page: int.tryParse(_pageController.text.trim()),
        total: int.tryParse(_totalController.text.trim()),
      ),
    );
  }

  /// A sitting that ended the book ended on its last page, so the page goes out
  /// as the total when the catalogue knows it — the session's own range should
  /// say what happened, not just the entry's progress.
  void _finish() {
    final total = widget.pageCount ?? int.tryParse(_totalController.text.trim());
    Navigator.of(context).pop(
      StopSessionResult(
        page: (total != null && total > 0)
            ? total
            : int.tryParse(_pageController.text.trim()),
        total: int.tryParse(_totalController.text.trim()),
        finished: true,
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
        onDelete: _deleteSession,
        onEdit: _editSession,
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
            // Always offered, even for a sitting with no notes yet — the
            // closing thought is often the only one you want to write, and it
            // used to be reachable only if you'd already written another
            // (owner report, 22 Jul 2026). Shared with the timer's wax-seal
            // face via [SessionNotesBlock].
            const SizedBox(height: 14),
            SessionNotesBlock(
              notes: sessionNotes,
              libraryEntryId: widget.libraryEntryId,
              sessionId: widget.loggedSessionId,
              bookTitle: widget.title,
              currentPage: () => int.tryParse(_pageController.text.trim()),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // A page that would walk progress backwards can't be saved —
                // the entry widget says why, right under the number. And with
                // both fields empty there is nothing to save: Skip is the
                // honest exit, so a Save that would silently do the same is
                // disabled rather than pretending.
                onPressed: (_error != null ||
                        (int.tryParse(_pageController.text.trim()) == null &&
                            int.tryParse(_totalController.text.trim()) == null))
                    ? null
                    : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oxblood,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(l10n.stopSavePage),
              ),
            ),
            const SizedBox(height: 6),
            // Moss, and secondary to Save: the larger, rarer claim, findable
            // without ever competing with the ordinary way out. Same action,
            // same words as the timer's wax-seal face.
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _error != null ? null : _finish,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.moss,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\u2713  ${l10n.timerMarkFinished}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.timerMarkFinishedHint,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              // A comfortable target — Skip is small type doing real work.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  child: Text(
                    // Skip says what it costs rather than being a bare word —
                    // and when notes *and* a page are both in play, it names
                    // both costs, not just the notes.
                    sessionNotes.isNotEmpty
                        ? (widget.currentPage != null
                            ? l10n.stopSkipNotesAndPage(
                                sessionNotes.length, widget.currentPage!)
                            : l10n.stopSkipNotesSafe(sessionNotes.length))
                        : (widget.currentPage != null
                            ? l10n.stopSkipWithPage(widget.currentPage!)
                            : l10n.stopSkipNoPage),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
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
    required this.onDelete,
    required this.onEdit,
  });

  final String? title;
  final List<ReadingSession> sessions;
  final VoidCallback onBack;

  /// Soft-deletes one sitting — the stray micro-sessions. Same affordance as
  /// the book page's reading log (they share [SessionLogRow]).
  final Future<void> Function(ReadingSession session) onDelete;

  /// Corrects a sitting's end time and end page. Same affordance as the book
  /// page's reading log (they share [SessionLogRow]).
  final Future<void> Function(ReadingSession session, DateTime endedAt, int? pageEnd) onEdit;

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
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  itemBuilder: (context, i) => SessionLogRow(
                    session: sessions[i],
                    primary: _dayLabel(context, sessions[i].endedAt),
                    highlight: i == 0,
                    divider: i < sessions.length - 1,
                    onDelete: () => onDelete(sessions[i]),
                    onEdit: (endedAt, pageEnd) => onEdit(sessions[i], endedAt, pageEnd),
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
