/// How fast the reader actually reads, and what that means for a given book —
/// the arithmetic behind "time to finish" (mockups P1–P9, Area 13).
///
/// Deliberately **not** a crowd average. With a handful of readers, "readers
/// average 8h" is one person's sittings wearing a plural noun; the honest —
/// and more useful — number is the reader's own pace. A shared figure becomes
/// possible later as a server-side aggregate; nothing here has to change for
/// it, it just gains a second number to sit beside these.
///
/// Pure over already-fetched rows, same shape as `computeReadingTimeStats`:
/// no UI imports, no db access, fully unit-testable.
library;

import '../../data/db/database.dart';

/// Below this many measurable sittings we don't claim to know the reader — the
/// estimate falls back to [assumedPagesPerHour] and says so (P6).
const minSessionsForPace = 3;

/// A stated, borrowed figure for a reader we haven't measured yet. Roughly
/// 250 wpm at ~300 words a page. Never silently blended with a real pace: the
/// UI renders an assumed estimate in grey and calls it typical.
const assumedPagesPerHour = 40.0;

/// How far back "your pace" looks. Long enough to survive a fortnight off,
/// short enough that a pace from a year ago doesn't outvote this month's.
const paceWindowDays = 90;

/// The window the weekly-habit figure averages over — the input that turns
/// hours into "about 3 weeks".
const weeklyHabitWeeks = 6;

/// A reading pace measured from the reader's own sittings.
class ReadingPace {
  const ReadingPace({
    required this.pagesPerHour,
    required this.sampleSessions,
    required this.byLanguage,
    required this.weeklySeconds,
    required this.medianSittingSeconds,
    this.recentWeekSeconds = 0,
  });

  /// Pages per hour across every measurable sitting in the window — null when
  /// there aren't any (a brand-new reader, or one who never notes a page).
  final double? pagesPerHour;

  /// How many sittings that figure rests on. Shown next to it: an estimate you
  /// can't audit is a horoscope.
  final int sampleSessions;

  /// language → pages/hour, for languages with their own usable sample. A
  /// reader's മലയാളം pace and English pace differ enough that ignoring the
  /// split is wrong on half the shelf.
  final Map<String, ({double pagesPerHour, int sessions})> byLanguage;

  /// Average seconds read per week over the last [weeklyHabitWeeks] — what
  /// converts "17h of reading" into "about 3 weeks".
  final int weeklySeconds;

  /// Typical length of one sitting, for the "≈ 14 sittings" unit.
  final int? medianSittingSeconds;

  /// Seconds read in the last 7 days alone. A reader three days into a binge
  /// is better described by this than by [weeklySeconds], which dilutes those
  /// days across five quieter weeks — "you'd finish in 2 weeks" to someone
  /// reading two hours a night is the average talking, not the reader.
  final int recentWeekSeconds;

  /// The weekly figure a finish estimate should divide by: the current week
  /// when it's the reader's busiest evidence, the long average otherwise (so
  /// a few quiet days never *worsen* the estimate below the habit).
  int get effectiveWeeklySeconds =>
      recentWeekSeconds > weeklySeconds ? recentWeekSeconds : weeklySeconds;

  /// True when [effectiveWeeklySeconds] is the streak, not the habit — the UI
  /// says which week it believed.
  bool get usesRecentHabit => recentWeekSeconds > weeklySeconds;

  bool get isMeasured => pagesPerHour != null && sampleSessions >= minSessionsForPace;

  /// The pace to use for a book, most specific first: this language (when it
  /// has its own sample), then overall, then the stated typical figure.
  double paceFor(String? language) {
    if (isMeasured) {
      final forLanguage = language == null ? null : byLanguage[language];
      if (forLanguage != null && forLanguage.sessions >= minSessionsForPace) {
        return forLanguage.pagesPerHour;
      }
      return pagesPerHour!;
    }
    return assumedPagesPerHour;
  }

  /// True when [paceFor] would return a language-specific figure — lets the UI
  /// say *which* pace it used rather than implying one global number.
  bool usesLanguagePace(String? language) {
    if (!isMeasured || language == null) return false;
    final forLanguage = byLanguage[language];
    return forLanguage != null && forLanguage.sessions >= minSessionsForPace;
  }

  static const empty = ReadingPace(
    pagesPerHour: null,
    sampleSessions: 0,
    byLanguage: {},
    weeklySeconds: 0,
    medianSittingSeconds: null,
  );
}

/// What a specific book costs this reader.
class FinishEstimate {
  const FinishEstimate({
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.pagesPerHour,
    required this.isAssumedPace,
    required this.usedLanguagePace,
    required this.sittings,
    required this.weeks,
    required this.finishDate,
    required this.weeklySecondsUsed,
    required this.usedRecentHabit,
  });

  /// The whole book, cover to cover, at [pagesPerHour].
  final int totalSeconds;

  /// What's left from the reader's current page — equal to [totalSeconds] on a
  /// book not started.
  final int remainingSeconds;

  final double pagesPerHour;

  /// The pace is [assumedPagesPerHour], not this reader's — render it grey and
  /// say so (P6). Never let an assumed number look measured.
  final bool isAssumedPace;

  /// The pace came from the book's own language rather than the overall figure.
  final bool usedLanguagePace;

  /// [remainingSeconds] in typical sittings — null until we know how long this
  /// reader's sittings actually run.
  final int? sittings;

  /// [remainingSeconds] against the weekly habit — null when there's no habit
  /// to divide by (nothing read in the last [weeklyHabitWeeks] weeks).
  final double? weeks;

  /// When [weeks] says they'd be done, or null for the same reason.
  final DateTime? finishDate;

  /// The weekly figure [weeks] divided by — so the footnote quotes the number
  /// the estimate actually used, not a different one.
  final int weeklySecondsUsed;

  /// [weeklySecondsUsed] is the current week (a streak), not the six-week
  /// habit — the footnote phrases it as "this past week", not "lately".
  final bool usedRecentHabit;
}

/// [now] is injectable for tests only — real callers never pass it.
FinishEstimate? estimateFinish({
  required int? pageCount,
  required ReadingPace pace,
  int? currentPage,
  String? language,
  /// Overrides [pace] for this book alone — its own sittings, once there are
  /// enough of them. A dense book is dense for you specifically (P2).
  double? bookPagesPerHour,
  DateTime? now,
}) {
  if (pageCount == null || pageCount <= 0) return null;

  final languagePace = pace.usesLanguagePace(language);
  final pagesPerHour = bookPagesPerHour ?? pace.paceFor(language);
  if (pagesPerHour <= 0) return null;

  final read = (currentPage ?? 0).clamp(0, pageCount);
  final remainingPages = pageCount - read;

  int secondsFor(int pages) => (pages / pagesPerHour * 3600).round();
  final remainingSeconds = secondsFor(remainingPages);

  final sitting = pace.medianSittingSeconds;
  final weekly = pace.effectiveWeeklySeconds;
  final weeks = weekly > 0 ? remainingSeconds / weekly : null;

  return FinishEstimate(
    totalSeconds: secondsFor(pageCount),
    remainingSeconds: remainingSeconds,
    pagesPerHour: pagesPerHour,
    // A book-specific pace is measured by definition — it came from sittings.
    isAssumedPace: bookPagesPerHour == null && !pace.isMeasured,
    usedLanguagePace: bookPagesPerHour == null && languagePace,
    sittings: (sitting != null && sitting > 0) ? (remainingSeconds / sitting).ceil() : null,
    weeks: weeks,
    finishDate: weeks == null
        ? null
        : (now ?? DateTime.now()).add(Duration(days: (weeks * 7).ceil())),
    weeklySecondsUsed: weekly,
    usedRecentHabit: pace.usesRecentHabit,
  );
}

/// Pages per hour across [sessions] that recorded a forward page range, or
/// null when none did. Used both for the global pace and for one book's own.
double? pagesPerHourOf(Iterable<ReadingSession> sessions) {
  var pages = 0;
  var seconds = 0;
  for (final s in sessions) {
    if (s.deletedAt != null) continue;
    final start = s.pageStart;
    final end = s.pageEnd;
    // A sitting only measures pace if it says where it started *and* ended,
    // and moved forward. Everything else still counts toward reading time.
    if (start == null || end == null || end <= start) continue;
    if (s.durationSeconds <= 0) continue;
    pages += end - start;
    seconds += s.durationSeconds;
  }
  if (seconds <= 0 || pages <= 0) return null;
  return pages / (seconds / 3600);
}

/// Count of sittings in [sessions] that can measure pace.
int measurableSessions(Iterable<ReadingSession> sessions) => sessions
    .where((s) =>
        s.deletedAt == null &&
        s.pageStart != null &&
        s.pageEnd != null &&
        s.pageEnd! > s.pageStart! &&
        s.durationSeconds > 0)
    .length;

/// The reader's pace, from every sitting joined to the book it was on (the
/// join is what makes the per-language split possible).
///
/// [now] is injectable for tests; real callers never pass it.
ReadingPace computeReadingPace({
  required List<ReadingSession> sessions,
  required List<LibraryHit> hits,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final windowStart = effectiveNow.subtract(const Duration(days: paceWindowDays));
  final habitStart = effectiveNow.subtract(const Duration(days: weeklyHabitWeeks * 7));
  final recentStart = effectiveNow.subtract(const Duration(days: 7));

  final languageOf = <String, String?>{
    for (final hit in hits) hit.entry.id: hit.book.language,
  };

  final inWindow = <ReadingSession>[];
  final byLanguageSessions = <String, List<ReadingSession>>{};
  var habitSeconds = 0;
  var recentSeconds = 0;
  final sittingLengths = <int>[];

  for (final s in sessions) {
    if (s.deletedAt != null) continue;
    if (!s.startedAt.isBefore(habitStart)) habitSeconds += s.durationSeconds;
    if (!s.startedAt.isBefore(recentStart)) recentSeconds += s.durationSeconds;
    if (s.startedAt.isBefore(windowStart)) continue;

    inWindow.add(s);
    if (s.durationSeconds > 0) sittingLengths.add(s.durationSeconds);
    final language = languageOf[s.libraryEntryId];
    if (language != null && language.trim().isNotEmpty) {
      byLanguageSessions.putIfAbsent(language, () => []).add(s);
    }
  }

  final byLanguage = <String, ({double pagesPerHour, int sessions})>{};
  byLanguageSessions.forEach((language, rows) {
    final pace = pagesPerHourOf(rows);
    if (pace != null) {
      byLanguage[language] = (pagesPerHour: pace, sessions: measurableSessions(rows));
    }
  });

  sittingLengths.sort();

  return ReadingPace(
    pagesPerHour: pagesPerHourOf(inWindow),
    sampleSessions: measurableSessions(inWindow),
    byLanguage: byLanguage,
    // Whole weeks, so a partial current week doesn't inflate the average.
    weeklySeconds: (habitSeconds / weeklyHabitWeeks).round(),
    medianSittingSeconds:
        sittingLengths.isEmpty ? null : sittingLengths[sittingLengths.length ~/ 2],
    recentWeekSeconds: recentSeconds,
  );
}

/// What a finished book actually cost — the moss figure on a read book (P8),
/// and the raw material of a shared average later.
class FinishedActual {
  const FinishedActual({
    required this.totalSeconds,
    required this.sessions,
    required this.pagesPerHour,
  });

  final int totalSeconds;
  final int sessions;

  /// Pace on this book alone — null when no sitting recorded a page range,
  /// which is common on a book finished before the timer existed.
  final double? pagesPerHour;
}

FinishedActual actualFor(List<ReadingSession> bookSessions) {
  final live = bookSessions.where((s) => s.deletedAt == null).toList();
  return FinishedActual(
    totalSeconds: live.fold<int>(0, (sum, s) => sum + s.durationSeconds),
    sessions: live.length,
    pagesPerHour: pagesPerHourOf(live),
  );
}
