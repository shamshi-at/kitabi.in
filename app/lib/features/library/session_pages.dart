import '../../data/db/database.dart';

/// How many pages one sitting moved through, or null when it can't be said.
///
/// Null rather than zero on purpose, matching [computeReadingTimeStats]'s
/// `totalPagesThisWeek`: the UI omits the figure entirely instead of printing a
/// misleading "+0". Three cases collapse to null — a sitting that recorded no
/// pages at all, one that ended on the page it started (real, and normal for a
/// reader who set their page before starting the clock), and one that ended
/// *behind* its start (re-reading a chapter), which is genuine reading that no
/// positive page count describes.
int? sessionPagesRead(ReadingSession session) {
  final start = session.pageStart;
  final end = session.pageEnd;
  if (start == null || end == null || end <= start) return null;
  return end - start;
}

/// Pages across every sitting that recorded them — the reading log's header
/// total. Sittings with no page range simply don't contribute; null when none
/// of them did, so the header drops the figure rather than claiming "0 pages"
/// for a book that has hours of untracked reading against it.
int? totalPagesRead(Iterable<ReadingSession> sessions) {
  var total = 0;
  var any = false;
  for (final s in sessions) {
    final pages = sessionPagesRead(s);
    if (pages == null) continue;
    any = true;
    total += pages;
  }
  return any ? total : null;
}
