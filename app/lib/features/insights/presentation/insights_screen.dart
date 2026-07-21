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
import '../insights_stats.dart';
import '../providers/insights_providers.dart';
import '../reading_time_stats.dart';

/// Single-letter month labels for the books-per-month bar chart axis.
const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// S10 — insights, the reader's almanac. Reading goal ring, a year selector,
/// headline stats, superlatives (most-read author, longest book), charts, and
/// a daily rotating reading fact — which also makes the page worth opening on
/// day one: a fresh reader gets the settable goal ring, the fact, and a
/// preview of what grows here, never a bare "no data".
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  // Default to the current year; null means "all time".
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

  /// Where the reader is vs. an even pace through the year.
  String _paceNote(AppLocalizations l10n, int read, int goal) {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays + 1;
    final expected = (goal * dayOfYear / 365).floor();
    final diff = read - expected;
    if (diff == 0) return l10n.insightsOnTrack;
    return diff > 0 ? l10n.insightsAhead(diff) : l10n.insightsBehind(-diff);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(libraryWithBooksProvider);
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? 30;
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
            final stats = computeInsights(hits, year: _year);
            return ListView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(l10n.insightsTitle, style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 12),
                _YearSelector(
                  year: _year,
                  thisYear: thisYear,
                  allTimeLabel: l10n.insightsAllTime,
                  onChanged: (y) => setState(() => _year = y),
                ),
                SizedBox(height: 16),
                _GoalRing(
                  booksRead: stats.booksRead,
                  goal: goal,
                  showTarget: _year != null,
                  targetCaption: l10n.insightsGoalRing(goal),
                  totalCaption: l10n.insightsBooksReadTotal,
                  paceNote: _year == thisYear ? _paceNote(l10n, stats.booksRead, goal) : null,
                  onTap: () => _editGoal(goal),
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        value: '${stats.pagesRead}',
                        label: l10n.insightsPagesRead,
                        color: AppColors.slate,
                      ),
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
                // The superlatives — the almanac lines readers quote.
                if (stats.topAuthor != null || stats.longestBookPages > 0) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      if (stats.topAuthor != null)
                        Expanded(
                          child: _SuperlativeTile(
                            icon: Icons.workspace_premium_outlined,
                            title: stats.topAuthor!,
                            caption:
                                '${l10n.insightsTopAuthor} · ${stats.topAuthorCount}',
                            color: AppColors.gold,
                            // Names are doors everywhere else; they were dead
                            // text here (owner report, 21 Jul 2026). Cached
                            // books hold author *names*, not ids, so resolve
                            // the name to a page on tap.
                            onTap: () => _openAuthor(context, ref, stats.topAuthor!),
                          ),
                        ),
                      if (stats.topAuthor != null && stats.longestBookPages > 0)
                        SizedBox(width: 8),
                      if (stats.longestBookPages > 0)
                        Expanded(
                          child: _SuperlativeTile(
                            icon: Icons.straighten,
                            title: stats.longestBookTitle ?? '',
                            caption:
                                '${l10n.insightsLongestBook} · ${stats.longestBookPages} pp',
                            color: AppColors.slate,
                            onTap: stats.longestBookWorkId == null ||
                                    stats.longestBookEditionId == null
                                ? null
                                : () => context.push(
                                      Routes.bookDetailPath(
                                        stats.longestBookWorkId!,
                                        stats.longestBookEditionId!,
                                      ),
                                    ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (_year != null && stats.busiestMonthCount > 0) ...[
                  SizedBox(height: 18),
                  _ChartLabel(l10n.insightsPerMonth),
                  SizedBox(height: 10),
                  _MonthBars(counts: stats.booksPerMonth, max: stats.busiestMonthCount),
                ],
                if (_year != null && stats.peakPagesMonth > 0) ...[
                  SizedBox(height: 18),
                  _ChartLabel(l10n.insightsPagesPerMonth),
                  SizedBox(height: 10),
                  _PagesLine(pages: stats.pagesPerMonth, max: stats.peakPagesMonth),
                ],
                if (stats.languageMix.length > 1) ...[
                  SizedBox(height: 18),
                  _ChartLabel(l10n.insightsLanguages),
                  SizedBox(height: 10),
                  _LanguageDonut(mix: stats.languageMix),
                ],
                SizedBox(height: 18),
                _ReadingTimeSection(),
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

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.year,
    required this.thisYear,
    required this.allTimeLabel,
    required this.onChanged,
  });

  final int? year;
  final int thisYear;
  final String allTimeLabel;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String, int?)>[
      ('$thisYear', thisYear),
      ('${thisYear - 1}', thisYear - 1),
      (allTimeLabel, null),
    ];
    return Row(
      children: [
        for (final (label, value) in options)
          Padding(
            padding: EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: year == value ? AppColors.ink : AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: year == value ? AppColors.ink : AppColors.line),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: year == value ? AppColors.paper : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
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

/// Weekly reading-time chart, pulled forward from the v1.5 parking lot
/// (10 Jul 2026, owner request) alongside the reading-timer feature itself.
/// Gated on having logged at least one session, same "don't show a chart
/// with nothing on it" convention as the rest of this screen.
class _ReadingTimeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(allReadingSessionsProvider).valueOrNull;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();

    final stats = computeReadingTimeStats(sessions);
    final max = stats.secondsByDayThisWeek.reduce((a, b) => a > b ? a : b);
    final delta = stats.thisWeekSeconds - stats.lastWeekSeconds;
    // The real current week's Monday — used only to pull correctly-ordered
    // weekday names out of DateFormat, never displayed as a date itself.
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChartLabel(l10n.insightsReadingTime),
        SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.insightsWeekTotal(formatDuration(Duration(seconds: stats.thisWeekSeconds))),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (stats.lastWeekSeconds > 0) ...[
              SizedBox(width: 8),
              Icon(
                delta >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: delta >= 0 ? AppColors.moss : AppColors.inkSoft,
              ),
              Text(
                l10n.insightsVsLastWeek(formatDuration(Duration(seconds: delta.abs()))),
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ],
          ],
        ),
        SizedBox(height: 10),
        SizedBox(
          height: 80,
          width: double.infinity,
          child: CustomPaint(painter: _AreaPainter(stats.secondsByDayThisWeek, max)),
        ),
        SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  DateFormat.E().format(monday.add(Duration(days: i))),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
        if (stats.totalPagesThisWeek != null) ...[
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.auto_stories_outlined, size: 12, color: AppColors.inkSoft),
              SizedBox(width: 5),
              Text(
                stats.pagesPerHour != null
                    ? '${l10n.insightsPagesThisWeek(stats.totalPagesThisWeek!)} · '
                        '${l10n.insightsPagesPace(stats.pagesPerHour!.round().toString())}'
                    : l10n.insightsPagesThisWeek(stats.totalPagesThisWeek!),
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
        if (stats.busiestWeekday != null && stats.busiestHour != null) ...[
          SizedBox(height: 12),
          Container(
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
                      DateFormat.EEEE().format(monday.add(Duration(days: stats.busiestWeekday! - 1))),
                      _hourRangeLabel(stats.busiestHour!),
                    ),
                    style: TextStyle(color: Color(0xFFEFE3C8), fontSize: 11.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// "9–10 PM" — locale-aware hour formatting either side of a plain dash.
  String _hourRangeLabel(int hour) {
    final start = DateFormat.j().format(DateTime(2026, 1, 1, hour));
    final end = DateFormat.j().format(DateTime(2026, 1, 1, (hour + 1) % 24));
    return '$start–$end';
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter(this.seconds, this.max);

  final List<int> seconds;
  final int max;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), baseline);

    if (max == 0) return;

    final points = <Offset>[
      for (var i = 0; i < 7; i++)
        Offset(
          size.width * (i / 6),
          size.height - (seconds[i] / max) * size.height * 0.88,
        ),
    ];

    final fillPath = Path()
      ..moveTo(points.first.dx, size.height)
      ..lineTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.gold.withValues(alpha: 0.32), AppColors.gold.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fill);

    final line = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..addPolygon(points, false), line);

    var peakIdx = 0;
    for (var i = 1; i < 7; i++) {
      if (seconds[i] > seconds[peakIdx]) peakIdx = i;
    }
    if (seconds[peakIdx] > 0) {
      canvas.drawCircle(points[peakIdx], 4, Paint()..color = AppColors.oxblood);
    }
  }

  @override
  bool shouldRepaint(covariant _AreaPainter old) => old.seconds != seconds || old.max != max;
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
