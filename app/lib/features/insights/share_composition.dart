import 'package:intl/intl.dart';

import '../../core/format_duration.dart';
import '../../l10n/app_localizations.dart';
import '../share/presentation/period_card_data.dart';
import 'insights_stats.dart';
import 'period.dart';
import 'period_summary.dart';

/// Everything the wax seal needs to open the share sheet for one window —
/// composed here, in one pure function per the card catalogue's data specs
/// (26 Aug 2026), so the sheet and the card never period-switch themselves.
/// Null means the window holds nothing true to send: the seal isn't drawn,
/// and there is no shareable zero (the honest-states rule).
class PeriodShare {
  const PeriodShare({
    required this.dataBuilder,
    required this.caption,
    this.canNameBooks = false,
    this.initialFormat = ShareCardFormat.story,
  });

  final PeriodCardData Function(bool nameBooks) dataBuilder;
  final String caption;
  final bool canNameBooks;
  final ShareCardFormat initialFormat;
}

PeriodShare? composePeriodShare({
  required AppLocalizations l10n,
  required InsightsPeriod period,
  required PeriodRange range,
  required PeriodSummary summary,
  InsightsStats? yearStats,
  int? year,
  int? paceDiff,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  switch (period) {
    case InsightsPeriod.today:
      if (summary.totalSeconds == 0 && summary.sittingsCount == 0) return null;
      return _today(l10n, summary, effectiveNow);
    case InsightsPeriod.week:
      if (summary.totalSeconds == 0 && summary.booksFinishedCount == 0) return null;
      return _week(l10n, range, summary, effectiveNow);
    case InsightsPeriod.month:
      if (summary.sittingsCount == 0 && summary.booksFinishedCount == 0) return null;
      return _month(l10n, range, summary, effectiveNow);
    case InsightsPeriod.threeMonths:
    case InsightsPeriod.sixMonths:
      if (summary.totalSeconds == 0 && summary.booksFinishedCount == 0) return null;
      return _stretch(l10n, period, range, summary, effectiveNow);
    case InsightsPeriod.year:
      final stats = yearStats;
      if (stats == null || (stats.booksRead == 0 && summary.totalSeconds == 0)) return null;
      return _year(l10n, summary, stats, year: year, paceDiff: paceDiff);
  }
}

/// Day-of-year rotation over a small pool — the reading-fact card's own
/// mechanism: varied enough not to repeat, never generated.
String _rotate(List<String> pool, DateTime now) {
  final dayOfYear = now.difference(DateTime(now.year)).inDays;
  return pool[dayOfYear % pool.length];
}

PeriodShare _today(AppLocalizations l10n, PeriodSummary summary, DateTime now) {
  final books = summary.booksInHand ?? const <BookInHand>[];
  final multiBook = books.length > 1;
  final duration = formatDuration(Duration(seconds: summary.totalSeconds));
  final closing = multiBook
      ? l10n.insightsPoolTodayMulti
      : _rotate([l10n.insightsPoolToday1, l10n.insightsPoolToday2], now);

  String subLine(bool nameBooks) {
    if (summary.pagesRead <= 0) return l10n.bookLogSessions(summary.sittingsCount);
    if (multiBook) {
      return l10n.insightsCardPagesBooks(summary.pagesRead, books.length);
    }
    final book = books.isEmpty ? null : books.first;
    final to = book?.currentPage;
    final from = to == null ? null : to - summary.pagesRead;
    final span = (to != null && from != null && from > 0)
        ? l10n.insightsCardPagesSpan(summary.pagesRead, from, to)
        : l10n.insightsCardPagesOnly(summary.pagesRead);
    if (nameBooks && book != null) return '$span · ${book.title}';
    return span;
  }

  final streak = summary.streakDays ?? 0;
  return PeriodShare(
    canNameBooks: books.isNotEmpty,
    initialFormat: ShareCardFormat.slip,
    caption: '$duration, ${l10n.bookLogTotalPages(summary.pagesRead).toLowerCase()} '
        '${l10n.insightsShareCaptionSuffix}',
    dataBuilder: (nameBooks) => PeriodCardData(
      heroValue: duration,
      heroLabel: l10n.insightsCardReadToday,
      subLine: subLine(nameBooks),
      closingLine: closing,
      pill: streak > 0 ? l10n.insightsStreakPill(streak) : null,
      lamps: summary.recentDays,
    ),
  );
}

PeriodShare _week(AppLocalizations l10n, PeriodRange range, PeriodSummary summary, DateTime now) {
  final duration = formatDuration(Duration(seconds: summary.totalSeconds));
  final previous = summary.previousTotalSeconds;
  String? pill;
  if (previous != null && previous > 0) {
    final diff = summary.totalSeconds - previous;
    final arrow = diff >= 0 ? '▲' : '▼';
    pill = '$arrow ${l10n.insightsVsLastWeek(formatDuration(Duration(seconds: diff.abs())))}';
  }
  return PeriodShare(
    caption: '$duration, ${l10n.bookLogTotalPages(summary.pagesRead).toLowerCase()} '
        '${l10n.insightsShareCaptionSuffix}',
    dataBuilder: (_) => PeriodCardData(
      heroValue: duration,
      heroLabel: l10n.insightsCardThisWeek,
      subLine:
          '${l10n.bookLogTotalPages(summary.pagesRead)} · ${l10n.bookLogSessions(summary.sittingsCount)}',
      closingLine: _rotate([l10n.insightsPoolWeek1, l10n.insightsPoolWeek2], now),
      pill: pill,
      pillTone: PillTone.moss,
      weekBars: summary.dailyBuckets ?? const [0, 0, 0, 0, 0, 0, 0],
      weekBarLabels: [
        for (var i = 0; i < 7; i++)
          DateFormat.E().format(range.start.add(Duration(days: i))).substring(0, 1),
      ],
    ),
  );
}

PeriodShare _month(AppLocalizations l10n, PeriodRange range, PeriodSummary summary, DateTime now) {
  final monthLabel = DateFormat.MMMM().format(range.start).toLowerCase();
  final (read, elapsed) = summary.daysReadOfElapsed;
  final finished = summary.booksFinishedCount;
  // A month of reading with nothing finished is still a month of reading —
  // the hero falls to the duration rather than showing a zero.
  final heroValue =
      finished > 0 ? '$finished' : formatDuration(Duration(seconds: summary.totalSeconds));
  final heroLabel =
      finished > 0 ? l10n.insightsCardBooksDot(monthLabel) : l10n.insightsCardReadIn(monthLabel);
  return PeriodShare(
    caption: '${l10n.insightsBooksFinished(finished)}, '
        '${l10n.bookLogTotalPages(summary.pagesRead).toLowerCase()} '
        '${l10n.insightsShareCaptionSuffix}',
    dataBuilder: (_) => PeriodCardData(
      heroValue: heroValue,
      heroLabel: heroLabel,
      subLine: l10n.bookLogTotalPages(summary.pagesRead),
      closingLine: _rotate([l10n.insightsPoolMonth1, l10n.insightsPoolMonth2], now),
      pill: elapsed > 0 ? l10n.insightsPillDaysRead(read, elapsed) : null,
      heatCells: summary.calendarCells,
    ),
  );
}

PeriodShare _stretch(
  AppLocalizations l10n,
  InsightsPeriod period,
  PeriodRange range,
  PeriodSummary summary,
  DateTime now,
) {
  // "jun – aug", a trailing window's own months — never "Q3" (10d rule).
  final fmt = DateFormat.MMM();
  final label =
      '${fmt.format(range.start)} – ${fmt.format(range.end.subtract(const Duration(days: 1)))}'
          .toLowerCase();
  final finished = summary.booksFinishedCount;
  final duration = formatDuration(Duration(seconds: summary.totalSeconds));
  final heroValue = finished > 0 ? '$finished' : duration;
  final heroLabel =
      finished > 0 ? l10n.insightsCardBooksDot(label) : l10n.insightsCardReadIn(label);
  final previous = summary.previousTotalSeconds;
  String? pill;
  if (previous != null && previous > 0) {
    final diff = summary.totalSeconds - previous;
    final arrow = diff >= 0 ? '▲' : '▼';
    pill = '$arrow ${l10n.insightsVsPrevStretch(formatDuration(Duration(seconds: diff.abs())))}';
  }
  return PeriodShare(
    caption: '${l10n.insightsBooksFinished(finished)}, '
        '${l10n.bookLogTotalPages(summary.pagesRead).toLowerCase()} '
        '${l10n.insightsShareCaptionSuffix}',
    dataBuilder: (_) => PeriodCardData(
      heroValue: heroValue,
      heroLabel: heroLabel,
      subLine: '${l10n.bookLogTotalPages(summary.pagesRead)} · '
          '${l10n.insightsHoursReading(duration)}',
      closingLine:
          period == InsightsPeriod.sixMonths ? l10n.insightsPoolStretch2 : l10n.insightsPoolStretch1,
      pill: pill,
      pillTone: PillTone.moss,
      trendBuckets: summary.trendBuckets,
    ),
  );
}

PeriodShare _year(
  AppLocalizations l10n,
  PeriodSummary summary,
  InsightsStats stats, {
  int? year,
  int? paceDiff,
}) {
  final duration = formatDuration(Duration(seconds: summary.totalSeconds));
  final label = year != null ? '$year' : l10n.insightsAllTime.toLowerCase();
  final hasBooks = stats.booksRead > 0;
  // Finish order, oldest first — booksFinished arrives newest-first. The
  // spines stay anonymous in v1 ("Name the spines" is drawn, deferred), so
  // the toggle is not offered for the year card.
  final spines = [
    for (final book in summary.booksFinished.reversed)
      ShelfSpine(pages: book.pageCount, seed: ShelfSpine.seedOf(book.title), title: book.title),
  ];
  String? pill;
  if (paceDiff != null && paceDiff > 0) pill = l10n.insightsAhead(paceDiff);
  if (paceDiff != null && paceDiff < 0) pill = l10n.insightsBehind(-paceDiff);
  return PeriodShare(
    caption: '${l10n.insightsBooksFinished(stats.booksRead)}, '
        '${l10n.bookLogTotalPages(stats.pagesRead).toLowerCase()} '
        '${l10n.insightsShareCaptionSuffix}',
    dataBuilder: (_) => PeriodCardData(
      heroValue: hasBooks ? '${stats.booksRead}' : duration,
      heroLabel: hasBooks ? l10n.insightsCardBooksIn(label) : l10n.insightsCardReadIn(label),
      subLine: '${l10n.bookLogTotalPages(stats.pagesRead)} · ${l10n.insightsHoursReading(duration)}',
      closingLine: _rotate(
        [l10n.insightsPoolYear1, l10n.insightsPoolYear2, l10n.insightsPoolYear3],
        DateTime.now(),
      ),
      pill: pill,
      // A year with nothing finished gets no shelf and no ledge — an empty
      // ledge is a reproach, not a visualization.
      shelf: hasBooks && spines.isNotEmpty ? spines : null,
    ),
  );
}
