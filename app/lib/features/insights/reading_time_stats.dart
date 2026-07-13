import '../../data/db/database.dart';

/// Derived reading-time figures for Insights — the weekly chart and the
/// plain-language "you read best on..." observation. Pure function over
/// already-fetched sessions, same shape as `computeInsights` in
/// insights_stats.dart.
class ReadingTimeStats {
  const ReadingTimeStats({
    required this.secondsByDayThisWeek,
    required this.thisWeekSeconds,
    required this.lastWeekSeconds,
    this.busiestWeekday,
    this.busiestHour,
    this.totalPagesThisWeek,
    this.pagesPerHour,
  });

  /// Index 0 = Monday .. 6 = Sunday, of the current week.
  final List<int> secondsByDayThisWeek;
  final int thisWeekSeconds;
  final int lastWeekSeconds;

  /// 1 = Monday .. 7 = Sunday (DateTime.weekday convention) — only set once
  /// there's enough data (>= 5 sessions) to say something real.
  final int? busiestWeekday;

  /// 0-23 — the hour with the most accumulated reading time, same
  /// minimum-data guard as [busiestWeekday].
  final int? busiestHour;

  /// Sum of `pageEnd - pageStart` across this week's sessions that recorded
  /// both — null (not zero) when no session this week qualifies, so the UI
  /// can omit the figure entirely rather than show a misleading "0 pages".
  final int? totalPagesThisWeek;

  /// [totalPagesThisWeek] divided by the combined duration of exactly those
  /// same qualifying sessions (not all reading time this week) — a pace
  /// figure, not "pages ÷ total hours read".
  final double? pagesPerHour;
}

/// [now] is injectable for tests — real callers never pass it, so the week
/// boundary is always the actual current week.
ReadingTimeStats computeReadingTimeStats(List<ReadingSession> sessions, {DateTime? now}) {
  final effectiveNow = now ?? DateTime.now();
  final today = DateTime(effectiveNow.year, effectiveNow.month, effectiveNow.day);
  final startOfThisWeek = today.subtract(Duration(days: effectiveNow.weekday - 1));
  final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));

  final byDayThisWeek = List<int>.filled(7, 0);
  var thisWeek = 0;
  var lastWeek = 0;
  final byWeekdayAllTime = List<int>.filled(7, 0);
  final byHourAllTime = List<int>.filled(24, 0);
  var pagesThisWeek = 0;
  var pagedSecondsThisWeek = 0;
  var hasPagedSessionThisWeek = false;

  for (final s in sessions) {
    if (s.deletedAt != null) continue;
    final started = s.startedAt;
    byWeekdayAllTime[started.weekday - 1] += s.durationSeconds;
    byHourAllTime[started.hour] += s.durationSeconds;

    if (!started.isBefore(startOfThisWeek)) {
      thisWeek += s.durationSeconds;
      final day = DateTime(started.year, started.month, started.day);
      final idx = day.difference(startOfThisWeek).inDays;
      if (idx >= 0 && idx < 7) byDayThisWeek[idx] += s.durationSeconds;

      final pageStart = s.pageStart;
      final pageEnd = s.pageEnd;
      if (pageStart != null && pageEnd != null && pageEnd > pageStart) {
        hasPagedSessionThisWeek = true;
        pagesThisWeek += pageEnd - pageStart;
        pagedSecondsThisWeek += s.durationSeconds;
      }
    } else if (!started.isBefore(startOfLastWeek)) {
      lastWeek += s.durationSeconds;
    }
  }

  const minSessionsForNarrative = 5;
  int? busiestWeekday;
  int? busiestHour;
  if (sessions.length >= minSessionsForNarrative) {
    var dayIdx = 0;
    for (var i = 1; i < 7; i++) {
      if (byWeekdayAllTime[i] > byWeekdayAllTime[dayIdx]) dayIdx = i;
    }
    if (byWeekdayAllTime[dayIdx] > 0) busiestWeekday = dayIdx + 1;

    var hourIdx = 0;
    for (var i = 1; i < 24; i++) {
      if (byHourAllTime[i] > byHourAllTime[hourIdx]) hourIdx = i;
    }
    if (byHourAllTime[hourIdx] > 0) busiestHour = hourIdx;
  }

  return ReadingTimeStats(
    secondsByDayThisWeek: byDayThisWeek,
    thisWeekSeconds: thisWeek,
    lastWeekSeconds: lastWeek,
    busiestWeekday: busiestWeekday,
    busiestHour: busiestHour,
    totalPagesThisWeek: hasPagedSessionThisWeek ? pagesThisWeek : null,
    pagesPerHour: hasPagedSessionThisWeek && pagedSecondsThisWeek > 0
        ? pagesThisWeek / (pagedSecondsThisWeek / 3600)
        : null,
  );
}
