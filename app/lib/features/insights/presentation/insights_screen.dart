import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/format_duration.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../share/presentation/share_period_sheet.dart';
import '../insights_stats.dart';
import '../period.dart';
import '../period_summary.dart';
import '../providers/insights_providers.dart';
import '../reading_time_stats.dart';
import 'finished_books_strip.dart';
import 'period_selector.dart';
import 'period_summary_card.dart';

/// Single-letter month labels for the books-per-month bar chart axis.
const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// S10 — insights, the reader's almanac. Redesigned 27 Jul 2026 around one
/// flagship card reused across every window a reader might mean by "how's my
/// reading going?" — Today, Week, Month, 3/6 months, Year. Year is the one
/// period that keeps the pre-redesign detail below it (goal ring's charts,
/// superlatives, the daily rotating reading fact) — this redesign changes
/// what's above the fold, not what Insights eventually shows underneath.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  InsightsPeriod _period = InsightsPeriod.year;
  // Only meaningful while _period is year; null means "all time".
  late int? _year = DateTime.now().year;

  Future<void> _editGoal(int current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: '$current');
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.insightsGoalDialogTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.insightsGoalDialogHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (goal == null || goal <= 0) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.setReadingGoal(goal);
    ref.invalidate(readingGoalProvider);
  }

  /// Where the reader is vs. an even pace through the year — the sub-line
  /// under the goal ring ("3 ahead of pace").
  String _paceNote(AppLocalizations l10n, int read, int goal) {
    final diff = _paceDiff(read, goal);
    if (diff == 0) return l10n.insightsOnTrack;
    return diff > 0 ? l10n.insightsAhead(diff) : l10n.insightsBehind(-diff);
  }

  /// The year card's headline — the same pace comparison as [_paceNote], one
  /// register up (a plain sentence rather than a number). Only meaningful for
  /// the current year; a past year or all time has no "pace" left to keep.
  String _yearHeadline(AppLocalizations l10n, {required int read, required int goal, required bool isPaceable}) {
    if (!isPaceable) return l10n.insightsYearHeadlineAllTime;
    final diff = _paceDiff(read, goal);
    if (diff > 0) return l10n.insightsYearHeadlineAhead;
    if (diff < 0) return l10n.insightsYearHeadlineBehind;
    return l10n.insightsYearHeadlineOnTrack;
  }

  int _paceDiff(int read, int goal) {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays + 1;
    final expected = (goal * dayOfYear / 365).floor();
    return read - expected;
  }

  /// Cached books store author *names*, not ids, so the most-read-author tile
  /// can't link straight through. Resolve the name against the catalogue and
  /// open their page; if that can't be done (offline, or an author the
  /// catalogue doesn't know under that spelling) fall back to search rather
  /// than leaving the tap dead.
  Future<void> _openAuthor(BuildContext context, WidgetRef ref, String name) async {
    try {
      final matches = await ref.read(apiClientProvider).searchAuthors(name);
      final exact = matches.firstWhere(
        (a) => (a['name'] as String? ?? '').toLowerCase() == name.toLowerCase(),
        orElse: () => matches.isNotEmpty ? matches.first : const <String, dynamic>{},
      );
      final id = exact['id'] as String?;
      if (!context.mounted) return;
      if (id != null) {
        context.push(Routes.authorBrowsePath(id));
        return;
      }
    } catch (_) {
      // Offline or the lookup failed — search still gets them somewhere useful.
    }
    if (context.mounted) context.push(Routes.catalogSearch);
  }

  /// Assembles the share sheet's inputs from whichever card is on screen.
  /// Deliberately generic over period (see [PeriodShareCard]'s own doc): the
  /// caller — here — is the one place that knows which figure is most
  /// flattering for a given window, everything downstream just lays it out.
  void _sharePeriod(PeriodSummary summary) {
    final l10n = AppLocalizations.of(context)!;
    final isDuration = _period == InsightsPeriod.today || _period == InsightsPeriod.week;
    final heroValue =
        isDuration ? formatDuration(Duration(seconds: summary.totalSeconds)) : '${summary.booksFinishedCount}';
    final heroLabel = isDuration ? '' : l10n.insightsBooksLabel(summary.booksFinishedCount);
    final subLine = isDuration
        ? '${l10n.bookLogTotalPages(summary.pagesRead)} · ${l10n.bookLogSessions(summary.sittingsCount)}'
        : '${l10n.bookLogTotalPages(summary.pagesRead)} · '
            '${l10n.insightsHoursReading(formatDuration(Duration(seconds: summary.totalSeconds)))}';
    showSharePeriodSheet(
      context,
      heroValue: heroValue,
      heroLabel: heroLabel,
      subLine: subLine,
      initialCaption: _buildCaption(l10n, summary, isDuration: isDuration),
    );
  }

  void _shareYear(InsightsStats stats, PeriodSummary yearSummary) {
    final l10n = AppLocalizations.of(context)!;
    final pages = l10n.bookLogTotalPages(stats.pagesRead);
    final duration = formatDuration(Duration(seconds: yearSummary.totalSeconds));
    showSharePeriodSheet(
      context,
      heroValue: '${stats.booksRead}',
      heroLabel: l10n.insightsBooksLabel(stats.booksRead),
      subLine: _year == null
          ? l10n.insightsShareSubLineAllTime(pages, duration)
          : l10n.insightsShareSubLineYear(pages, duration, _year!),
      initialCaption: '${l10n.insightsBooksFinished(stats.booksRead)}, ${pages.toLowerCase()} '
          '${l10n.insightsShareCaptionSuffix}',
    );
  }

  /// Leads with whichever figure the card itself leads with — [isDuration]
  /// must match [_sharePeriod]'s own hero choice, or the caption ends up
  /// claiming a different headline number than the image right above it (a
  /// book that happened to finish today isn't why the Today card exists).
  String _buildCaption(AppLocalizations l10n, PeriodSummary summary, {required bool isDuration}) {
    final parts = <String>[];
    if (isDuration) {
      parts.add(formatDuration(Duration(seconds: summary.totalSeconds)));
      if (summary.pagesRead > 0) parts.add(l10n.bookLogTotalPages(summary.pagesRead));
      if (summary.booksFinishedCount > 0) parts.add(l10n.insightsBooksFinished(summary.booksFinishedCount));
    } else {
      parts.add(l10n.insightsBooksFinished(summary.booksFinishedCount));
      if (summary.pagesRead > 0) parts.add(l10n.bookLogTotalPages(summary.pagesRead));
    }
    return '${parts.join(', ')} ${l10n.insightsShareCaptionSuffix}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(libraryWithBooksProvider);
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? 30;
    final sessions = ref.watch(readingSessionsStreamProvider).valueOrNull;
    final ratings = ref.watch(ratingsByWorkIdProvider).valueOrNull ?? const {};
    final thisYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: data.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(libraryWithBooksProvider)),
          data: (hits) {
            if (hits.isEmpty) {
              return _FreshInsights(goal: goal, onEditGoal: () => _editGoal(goal));
            }

            final range = rangeFor(_period, year: _year);
            final periodSummary = sessions == null
                ? null
                : computePeriodSummary(
                    period: _period,
                    range: range,
                    sessions: sessions,
                    hits: hits,
                    ratingsByWorkId: ratings,
                  );
            final timeStats = sessions == null ? null : computeReadingTimeStats(sessions);
            final yearStats = _period == InsightsPeriod.year ? computeInsights(hits, year: _year) : null;

            return ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(l10n.insightsTitle, style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 12),
                PeriodSelector(
                  selected: _period,
                  onSelected: (p) => setState(() => _period = p),
                  selectedYear: _year,
                  onYearSelected: (y) => setState(() => _year = y),
                  thisYear: thisYear,
                ),
                SizedBox(height: 14),
                if (periodSummary == null)
                  ListSkeleton()
                else if (yearStats != null) ...[
                  _YearCard(
                    stats: yearStats,
                    yearSummary: periodSummary,
                    goal: goal,
                    year: _year,
                    thisYear: thisYear,
                    headlineBuilder: _yearHeadline,
                    paceNoteBuilder: _paceNote,
                    onEditGoal: () => _editGoal(goal),
                    onShare: _shareYear,
                  ),
                  // The superlatives — the almanac lines readers quote.
                  if (yearStats.topAuthor != null || yearStats.longestBookPages > 0) ...[
                    SizedBox(height: 14),
                    Row(
                      children: [
                        if (yearStats.topAuthor != null)
                          Expanded(
                            child: _SuperlativeTile(
                              icon: Icons.workspace_premium_outlined,
                              title: yearStats.topAuthor!,
                              caption: '${l10n.insightsTopAuthor} · ${yearStats.topAuthorCount}',
                              color: AppColors.gold,
                              onTap: () => _openAuthor(context, ref, yearStats.topAuthor!),
                            ),
                          ),
                        if (yearStats.topAuthor != null && yearStats.longestBookPages > 0) SizedBox(width: 8),
                        if (yearStats.longestBookPages > 0)
                          Expanded(
                            child: _SuperlativeTile(
                              icon: Icons.straighten,
                              title: yearStats.longestBookTitle ?? '',
                              caption: '${l10n.insightsLongestBook} · ${yearStats.longestBookPages} pp',
                              color: AppColors.slate,
                              onTap: yearStats.longestBookWorkId == null || yearStats.longestBookEditionId == null
                                  ? null
                                  : () => context.push(
                                        Routes.bookDetailPath(
                                          yearStats.longestBookWorkId!,
                                          yearStats.longestBookEditionId!,
                                        ),
                                      ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (yearStats.busiestMonthCount > 0) ...[
                    SizedBox(height: 18),
                    _ChartLabel(l10n.insightsPerMonth),
                    SizedBox(height: 10),
                    _MonthBars(counts: yearStats.booksPerMonth, max: yearStats.busiestMonthCount),
                  ],
                  if (yearStats.peakPagesMonth > 0) ...[
                    SizedBox(height: 18),
                    _ChartLabel(l10n.insightsPagesPerMonth),
                    SizedBox(height: 10),
                    _PagesLine(pages: yearStats.pagesPerMonth, max: yearStats.peakPagesMonth),
                  ],
                  if (yearStats.languageMix.length > 1) ...[
                    SizedBox(height: 18),
                    _ChartLabel(l10n.insightsLanguages),
                    SizedBox(height: 10),
                    _LanguageDonut(mix: yearStats.languageMix),
                  ],
                  if (timeStats?.busiestWeekday != null && timeStats?.busiestHour != null) ...[
                    SizedBox(height: 18),
                    _BusiestTimeInsight(weekday: timeStats!.busiestWeekday!, hour: timeStats.busiestHour!),
                  ],
                ] else ...[
                  PeriodSummaryCard(
                    period: _period,
                    range: range,
                    summary: periodSummary,
                    onShare: () => _sharePeriod(periodSummary),
                  ),
                  if (periodSummary.booksFinished.isNotEmpty) ...[
                    SizedBox(height: 12),
                    FinishedBooksStrip(books: periodSummary.booksFinished),
                  ],
                ],
                SizedBox(height: 18),
                _ReadingFactCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The year period's flagship header — eyebrow, a pace-derived headline, the
/// goal ring, and the share glyph. Everything below it (bars, donut,
/// superlatives) is assembled by the screen itself, since only Year keeps
/// that detail.
class _YearCard extends StatelessWidget {
  const _YearCard({
    required this.stats,
    required this.yearSummary,
    required this.goal,
    required this.year,
    required this.thisYear,
    required this.headlineBuilder,
    required this.paceNoteBuilder,
    required this.onEditGoal,
    required this.onShare,
  });

  final InsightsStats stats;
  final PeriodSummary yearSummary;
  final int goal;
  final int? year;
  final int thisYear;
  final String Function(AppLocalizations, {required int read, required int goal, required bool isPaceable})
      headlineBuilder;
  final String Function(AppLocalizations, int read, int goal) paceNoteBuilder;
  final VoidCallback onEditGoal;
  final void Function(InsightsStats stats, PeriodSummary yearSummary) onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isPaceable = year == thisYear;
    return Container(
      padding: EdgeInsets.all(14),
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
                  year == null ? l10n.insightsAllTime.toUpperCase() : '$year',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: AppColors.oxblood,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onShare(stats, yearSummary),
                  borderRadius: BorderRadius.circular(7),
                  child: Tooltip(
                    message: l10n.insightsShareTooltip,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(7)),
                      child: Icon(Icons.ios_share, size: 13, color: AppColors.oxblood),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Text(
            headlineBuilder(l10n, read: stats.booksRead, goal: goal, isPaceable: isPaceable),
            style: GoogleFonts.fraunces(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          SizedBox(height: 10),
          _GoalRing(
            booksRead: stats.booksRead,
            goal: goal,
            showTarget: year != null,
            targetCaption: l10n.insightsGoalRing(goal),
            totalCaption: l10n.insightsBooksReadTotal,
            paceNote: isPaceable ? paceNoteBuilder(l10n, stats.booksRead, goal) : null,
            onTap: onEditGoal,
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(value: '${stats.pagesRead}', label: l10n.insightsPagesRead, color: AppColors.slate),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  value: '${stats.currentlyReading}',
                  label: l10n.insightsReadingNow,
                  color: AppColors.oxblood,
                ),
              ),
              if (stats.avgPagesPerBook > 0) ...[
                SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    value: '${stats.avgPagesPerBook}',
                    label: l10n.insightsAvgPages,
                    color: AppColors.moss,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The all-time "you read most on Thursdays, often around 9–10 PM" note —
/// pulled out of the old always-visible weekly chart (superseded by the Week
/// period card) but kept, because it's a genuine all-time pattern, not a
/// per-week one. Lives under Year alongside the other superlatives.
class _BusiestTimeInsight extends StatelessWidget {
  const _BusiestTimeInsight({required this.weekday, required this.hour});

  final int weekday;
  final int hour;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final monday = DateTime(2026, 1, 5); // an arbitrary real Monday.
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.night, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 14, color: AppColors.gold),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              l10n.insightsReadingTimeInsight(
                DateFormat.EEEE().format(monday.add(Duration(days: weekday - 1))),
                _hourRangeLabel(hour),
              ),
              style: TextStyle(color: Color(0xFFEFE3C8), fontSize: 11.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// "9–10 PM" — locale-aware hour formatting either side of a plain dash.
  String _hourRangeLabel(int hour) {
    final start = DateFormat.j().format(DateTime(2026, 1, 1, hour));
    final end = DateFormat.j().format(DateTime(2026, 1, 1, (hour + 1) % 24));
    return '$start–$end';
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.booksRead,
    required this.goal,
    required this.showTarget,
    required this.targetCaption,
    required this.totalCaption,
    required this.onTap,
    this.paceNote,
  });

  final int booksRead;
  final int goal;
  final bool showTarget;
  final String targetCaption;
  final String totalCaption;
  final String? paceNote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = showTarget && goal > 0 ? (booksRead / goal).clamp(0.0, 1.0) : 1.0;
    return GestureDetector(
      onTap: showTarget ? onTap : null,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: AppColors.line,
                      valueColor: AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                  Text(
                    '$booksRead',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppColors.oxblood, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    showTarget ? targetCaption : totalCaption,
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                  ),
                  if (showTarget && paceNote != null) ...[
                    SizedBox(height: 4),
                    Text(
                      paceNote!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.moss,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showTarget) Icon(Icons.edit, size: 16, color: AppColors.oxblood),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.counts, required this.max});

  final List<int> counts;
  final int max;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (counts[i] > 0)
                    Text(
                      '${counts[i]}',
                      style: TextStyle(fontSize: 8, color: AppColors.inkSoft),
                    ),
                  SizedBox(height: 2),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 3),
                    height: (60 * (counts[i] / max)).clamp(counts[i] > 0 ? 4.0 : 0.0, 60.0),
                    decoration: BoxDecoration(
                      color: counts[i] > 0 ? AppColors.oxblood : AppColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _monthLetters[i],
                    style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartLabel extends StatelessWidget {
  const _ChartLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.inkSoft,
      ),
    );
  }
}

// Runtime (not const): AppColors tokens resolve per active theme.
List<Color> get _chartPalette => [
      AppColors.oxblood,
      AppColors.gold,
      AppColors.slate,
      AppColors.moss,
      AppColors.ink,
      AppColors.stampGrey,
    ];

class _PagesLine extends StatelessWidget {
  const _PagesLine({required this.pages, required this.max});

  final List<int> pages;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 70,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(pages, max)),
        ),
        SizedBox(height: 4),
        Row(
          children: [
            for (final letter in _monthLetters)
              Expanded(
                child: Text(
                  letter,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pages, this.max);

  final List<int> pages;
  final int max;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), baseline);

    final points = <Offset>[
      for (var i = 0; i < 12; i++)
        Offset(
          size.width * (i / 11),
          size.height - (max == 0 ? 0 : (pages[i] / max) * size.height * 0.9),
        ),
    ];
    final line = Paint()
      ..color = AppColors.oxblood
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..addPolygon(points, false);
    canvas.drawPath(path, line);

    final dot = Paint()..color = AppColors.oxblood;
    for (var i = 0; i < 12; i++) {
      if (pages[i] > 0) canvas.drawCircle(points[i], 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.pages != pages || old.max != max;
}

class _LanguageDonut extends StatelessWidget {
  const _LanguageDonut({required this.mix});

  final Map<String, int> mix;

  @override
  Widget build(BuildContext context) {
    final entries = mix.entries.toList();
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return Row(
      children: [
        SizedBox(
          width: 78,
          height: 78,
          child: CustomPaint(painter: _DonutPainter(entries.map((e) => e.value).toList(), total)),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, entry) in entries.indexed)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _chartPalette[i % _chartPalette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.ink),
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.total);

  final List<int> values;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    var start = -1.5708; // -90° — start at top
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 6.28319;
      final paint = Paint()
        ..color = _chartPalette[i % _chartPalette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12;
      canvas.drawArc(rect, start, sweep - 0.03, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}

/// A small superlative card — the almanac lines ("most-read author",
/// "longest book") with a colour-keyed icon.
class _SuperlativeTile extends StatelessWidget {
  const _SuperlativeTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 15, color: AppColors.inkSoft),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
    );
  }
}

/// A rotating bookish fact — one per day, no repeats until the list cycles.
/// Gives the page something worth reading even before any data exists.
class _ReadingFactCard extends StatelessWidget {
  const _ReadingFactCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final facts = [
      l10n.insightsFact1,
      l10n.insightsFact2,
      l10n.insightsFact3,
      l10n.insightsFact4,
      l10n.insightsFact5,
      l10n.insightsFact6,
      l10n.insightsFact7,
      l10n.insightsFact8,
    ];
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final fact = facts[dayOfYear % facts.length];

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_stories, size: 13, color: AppColors.gold),
              SizedBox(width: 6),
              Text(
                l10n.insightsFactLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            fact,
            style: GoogleFonts.fraunces(
              fontStyle: FontStyle.italic,
              fontSize: 14,
              height: 1.45,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Day-one insights: instead of "no data", the settable goal ring (a goal is
/// the one stat you can have before any book), today's reading fact, and an
/// honest preview of the charts this page grows into.
class _FreshInsights extends StatelessWidget {
  const _FreshInsights({required this.goal, required this.onEditGoal});

  final int goal;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final year = DateTime.now().year;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(l10n.insightsTitle, style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 4),
        Text(
          l10n.insightsFreshTitle,
          style: GoogleFonts.fraunces(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        SizedBox(height: 4),
        Text(
          l10n.insightsFreshBody,
          style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4),
        ),
        SizedBox(height: 16),
        _GoalRing(
          booksRead: 0,
          goal: goal,
          showTarget: true,
          targetCaption: l10n.insightsGoalRing(goal),
          totalCaption: l10n.insightsBooksReadTotal,
          paceNote: l10n.insightsSetGoalHint(year),
          onTap: onEditGoal,
        ),
        SizedBox(height: 14),
        _ReadingFactCard(),
        SizedBox(height: 18),
        _ChartLabel(l10n.insightsGrowsLabel),
        SizedBox(height: 8),
        _GrowsRow(icon: Icons.bar_chart, text: l10n.insightsComingBars),
        _GrowsRow(icon: Icons.show_chart, text: l10n.insightsComingPages),
        _GrowsRow(icon: Icons.donut_large_outlined, text: l10n.insightsComingLangs),
        _GrowsRow(icon: Icons.workspace_premium_outlined, text: l10n.insightsComingAuthor),
        SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(Routes.catalogSearch),
            icon: Icon(Icons.add, size: 18),
            label: Text(l10n.insightsAddFirstBook),
          ),
        ),
      ],
    );
  }
}

/// One "what grows here" preview row — muted, honest, a little inviting.
class _GrowsRow extends StatelessWidget {
  const _GrowsRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.stampGrey),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}
