import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/format_duration.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_label.dart';
import '../../../l10n/app_localizations.dart';
import '../period.dart';
import '../period_summary.dart';

/// The flagship card — one shape, reused for every period except Year (which
/// keeps its existing goal ring and detail charts, per the 27 Jul 2026
/// redesign): eyebrow, a headline written as a sentence before it's shown as
/// a number, the hero figure, a visualization sized to the window, and a
/// closing encouraging line on the dark panel — streak-driven for Today,
/// derived from the same period stats everywhere else (the spec's "closing
/// line" now applies to every period, ux-review 2026-07-28).
class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({
    super.key,
    required this.period,
    required this.range,
    required this.summary,
    required this.onShare,
  });

  final InsightsPeriod period;
  final PeriodRange range;
  final PeriodSummary summary;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _eyebrow(l10n),
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: AppColors.oxblood,
                  ),
                ),
              ),
              ShareGlyph(tooltip: l10n.insightsShareTooltip, onTap: onShare),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _headline(l10n),
            style: GoogleFonts.fraunces(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          _hero(l10n),
          const SizedBox(height: 12),
          _visualization(context, l10n),
          if (_closing(l10n) case final closing?) ...[
            const SizedBox(height: 10),
            _ClosingPanel(icon: closing.$1, text: closing.$2),
          ],
        ],
      ),
    );
  }

  /// The dark-panel closing line — one encouraging fact per period, derived
  /// from stats the summary already carries (never a new computation).
  (IconData, String)? _closing(AppLocalizations l10n) {
    switch (period) {
      case InsightsPeriod.today:
        final streak = summary.streakDays ?? 0;
        return streak > 0
            ? (Icons.local_fire_department, l10n.insightsStreakDays(streak))
            : (Icons.auto_stories_outlined, l10n.insightsNoSessionToday);
      case InsightsPeriod.week:
        final previous = summary.previousTotalSeconds;
        if (summary.totalSeconds == 0) {
          return (Icons.auto_stories_outlined, l10n.insightsClosingWeekNone);
        }
        if (previous != null && previous > 0 && summary.totalSeconds > previous) {
          return (Icons.local_fire_department, l10n.insightsClosingWeekUp);
        }
        return (Icons.auto_stories_outlined, l10n.insightsClosingWeekSteady);
      case InsightsPeriod.month:
        final read = (summary.calendarCells ?? const []).where((c) => c.isRead).length;
        return (Icons.calendar_month_outlined, l10n.insightsClosingMonthDays(read));
      case InsightsPeriod.threeMonths:
      case InsightsPeriod.sixMonths:
        return (Icons.auto_stories_outlined, l10n.insightsClosingStretch(summary.booksFinishedCount));
      case InsightsPeriod.year:
        return null;
    }
  }

  String _eyebrow(AppLocalizations l10n) {
    switch (period) {
      case InsightsPeriod.today:
        return DateFormat('EEE · d MMM').format(range.start).toUpperCase();
      case InsightsPeriod.week:
        return l10n.insightsEyebrowThisWeek.toUpperCase();
      case InsightsPeriod.month:
        return DateFormat('MMMM yyyy').format(range.start).toUpperCase();
      case InsightsPeriod.threeMonths:
        return l10n.insightsEyebrowLast3Months.toUpperCase();
      case InsightsPeriod.sixMonths:
        return l10n.insightsEyebrowLast6Months.toUpperCase();
      case InsightsPeriod.year:
        return '${range.start.year}';
    }
  }

  String _headline(AppLocalizations l10n) {
    switch (period) {
      case InsightsPeriod.today:
        return l10n.insightsPeriodTodayHeadline;
      case InsightsPeriod.week:
        return l10n.insightsPeriodWeekHeadline;
      case InsightsPeriod.month:
        return l10n.insightsPeriodMonthHeadline;
      case InsightsPeriod.threeMonths:
      case InsightsPeriod.sixMonths:
        return l10n.insightsPeriodMultiMonthHeadline;
      case InsightsPeriod.year:
        return '';
    }
  }

  Widget _hero(AppLocalizations l10n) {
    switch (period) {
      case InsightsPeriod.today:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDuration(Duration(seconds: summary.totalSeconds)),
                  style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w600, color: AppColors.oxblood, height: 1),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l10n.insightsReadToday, style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
                ),
              ],
            ),
            if (summary.pagesRead > 0) ...[
              const SizedBox(height: 3),
              Text(
                l10n.insightsPagesGained(summary.pagesRead),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.moss),
              ),
            ],
          ],
        );
      case InsightsPeriod.week:
        final delta = summary.previousTotalSeconds;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  formatDuration(Duration(seconds: summary.totalSeconds)),
                  style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.oxblood),
                ),
                if (delta != null && delta > 0) ...[
                  const SizedBox(width: 8),
                  _Delta(seconds: summary.totalSeconds - delta, l10n: l10n),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${l10n.bookLogSessions(summary.sittingsCount)} · ${l10n.bookLogTotalPages(summary.pagesRead)}',
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
            ),
          ],
        );
      case InsightsPeriod.month:
        final cells = summary.calendarCells ?? const [];
        final elapsed = cells.where((c) => c.date != null && !c.isFuture).length;
        final read = cells.where((c) => c.isRead).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.insightsBooksFinished(summary.booksFinishedCount),
              style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.oxblood),
            ),
            const SizedBox(height: 2),
            Text(
              '${l10n.bookLogTotalPages(summary.pagesRead)} · ${l10n.insightsDaysRead(read, elapsed)}',
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
            ),
          ],
        );
      case InsightsPeriod.threeMonths:
      case InsightsPeriod.sixMonths:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.insightsBooksFinished(summary.booksFinishedCount),
              style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.oxblood),
            ),
            const SizedBox(height: 2),
            Text(
              '${l10n.bookLogTotalPages(summary.pagesRead)} · '
              '${l10n.insightsHoursReading(formatDuration(Duration(seconds: summary.totalSeconds)))}',
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
            ),
          ],
        );
      case InsightsPeriod.year:
        return const SizedBox.shrink();
    }
  }

  Widget _visualization(BuildContext context, AppLocalizations l10n) {
    switch (period) {
      case InsightsPeriod.today:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(l10n.insightsLast7Days, padding: const EdgeInsets.only(bottom: 6)),
            _DayDots(days: summary.recentDays ?? const []),
          ],
        );
      case InsightsPeriod.week:
        return _WeekBars(range: range, buckets: summary.dailyBuckets ?? const [0, 0, 0, 0, 0, 0, 0]);
      case InsightsPeriod.month:
        return _MonthHeatmap(cells: summary.calendarCells ?? const []);
      case InsightsPeriod.threeMonths:
      case InsightsPeriod.sixMonths:
        return _TrendLine(buckets: summary.trendBuckets ?? const [], range: range);
      case InsightsPeriod.year:
        return const SizedBox.shrink();
    }
  }
}

/// The little goldSoft share square on the period and year cards — public so
/// the year card (which lives in insights_screen.dart) reuses this exact
/// widget instead of keeping its own copy.
class ShareGlyph extends StatelessWidget {
  const ShareGlyph({super.key, required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(7)),
            child: Icon(Icons.ios_share, size: 13, color: AppColors.oxblood),
          ),
        ),
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.seconds, required this.l10n});

  final int seconds;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final up = seconds >= 0;
    final color = up ? AppColors.moss : AppColors.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: color),
        Text(
          l10n.insightsVsLastWeek(formatDuration(Duration(seconds: seconds.abs()))),
          style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// The card's closing line — the spec's "single dark accent card": one gold
/// icon and one encouraging sentence on [AppColors.darkPanel] (constant in
/// both themes, so the text tokens are the constant [AppColors.onDark]).
class _ClosingPanel extends StatelessWidget {
  const _ClosingPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration:
          BoxDecoration(color: AppColors.darkPanel, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.onDark, fontSize: 11.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The daily card's streak row — a trailing week, not a calendar one, so it
/// keeps meaning "the last 7 days" no matter what weekday it is.
class _DayDots extends StatelessWidget {
  const _DayDots({required this.days});

  final List<bool> days;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, on) in days.indexed) ...[
          if (i > 0) const SizedBox(width: 5),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? AppColors.gold : AppColors.paperDeep,
              border: Border.all(
                color: i == days.length - 1 ? AppColors.oxblood : (on ? AppColors.gold : AppColors.line),
                width: i == days.length - 1 ? 1.5 : 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.range, required this.buckets});

  final PeriodRange range;
  final List<int> buckets;

  @override
  Widget build(BuildContext context) {
    final max = buckets.isEmpty ? 0 : buckets.reduce((a, b) => a > b ? a : b);
    var peakIdx = 0;
    for (var i = 1; i < buckets.length; i++) {
      if (buckets[i] > buckets[peakIdx]) peakIdx = i;
    }
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, seconds) in buckets.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: max == 0 ? 4 : (46 * (seconds / max)).clamp(seconds > 0 ? 4.0 : 2.0, 46.0),
                      decoration: BoxDecoration(
                        color: seconds == 0
                            ? AppColors.paperDeep
                            : (i == peakIdx ? AppColors.oxblood : AppColors.goldSoft),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  DateFormat.E().format(range.start.add(Duration(days: i))).substring(0, 1),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({required this.cells});

  final List<CalendarCell> cells;

  @override
  Widget build(BuildContext context) {
    // Weekday header aligned to the grid's own columns — the grid is
    // Sunday-first (see `_monthCells`), so the letters run S M T W T F S,
    // localized via DateFormat (2026-01-04 is a real Sunday).
    final dayLetters = [
      for (var i = 0; i < 7; i++)
        DateFormat.E().format(DateTime(2026, 1, 4 + i)).substring(0, 1),
    ];
    return Column(
      children: [
        Row(
          children: [
            for (final letter in dayLetters)
              Expanded(
                child: Text(
                  letter,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        _grid(context),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cells.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemBuilder: (context, i) {
        final cell = cells[i];
        if (cell.date == null) return const SizedBox.shrink();
        return Container(
          decoration: BoxDecoration(
            color: cell.isFuture ? Colors.transparent : (cell.isRead ? AppColors.gold : AppColors.paperDeep),
            borderRadius: BorderRadius.circular(3),
            border: cell.isFuture
                ? Border.all(color: AppColors.line)
                : (cell.date!.day == DateTime.now().day &&
                        cell.date!.month == DateTime.now().month &&
                        cell.date!.year == DateTime.now().year
                    ? Border.all(color: AppColors.oxblood, width: 1.5)
                    : null),
          ),
        );
      },
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.buckets, required this.range});

  final List<int> buckets;
  final PeriodRange range;

  @override
  Widget build(BuildContext context) {
    // `end` is exclusive, so the right label names the last day inside the
    // window, not the day after it.
    final startLabel = DateFormat.MMM().format(range.start);
    final endLabel = DateFormat.MMM().format(range.end.subtract(const Duration(days: 1)));
    return Column(
      children: [
        SizedBox(
          height: 46,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(buckets)),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(startLabel, style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft)),
            Text(endLabel, style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft)),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), baseline);
    if (values.length < 2) return;

    final max = values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return;

    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * (i / (values.length - 1)),
          size.height - (values[i] / max) * size.height * 0.92,
        ),
    ];
    final line = Paint()
      ..color = AppColors.oxblood
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()..addPolygon(points, false), line);
    canvas.drawCircle(points.last, 3, Paint()..color = AppColors.oxblood);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}
