import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/format_duration.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../share/presentation/period_card_data.dart';
import '../../share/presentation/period_card_viz.dart';
import '../../share/presentation/period_share_card.dart';
import '../../share/presentation/share_period_sheet.dart';
import '../insights_stats.dart';
import '../period.dart';
import '../period_summary.dart';
import '../reading_time_stats.dart';
import '../providers/insights_providers.dart';
import '../share_composition.dart';
import 'almanac_widgets.dart';
import 'finished_books_screen.dart';
import 'period_selector.dart';
import 'sittings_sheet.dart';

/// Single-letter month labels for the year's books-per-month bar chart axis.
const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// S10 — Insights as the almanac (Direction B, owner pick 26 Aug 2026;
/// revised same day to R2, docs/insights-share-mockups.html "B, revised").
/// No card boxes: the page is one typeset sheet — stat pairs (the figure
/// with its name directly beneath it, two to a row, one downward glance
/// each; the first ledger's label-left/figure-right rows made the eye walk
/// a dotted bridge per line), tight name lines for In hand / Most read /
/// Longest, small-caps section heads. Two verbs govern every row: tap navigates
/// (every oxblood value is a door — the house rule), long-press shares (the
/// row slip). The one control is the gold wax seal, which opens the share
/// sheet with the window's graphical card — never a full-page capture — and
/// is simply not drawn when the window holds nothing true to send.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  // Today, not Year — the current date is what a reader most often means by
  // "how's my reading going?", even though Year leads the chip row (it's the
  // scope-setting chip, not the default view).
  InsightsPeriod _period = InsightsPeriod.today;
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

  /// Where the reader is vs. an even pace through the year — the year
  /// ledger's "Against pace" row.
  String _paceNote(AppLocalizations l10n, int read, int goal) {
    final diff = _paceDiff(read, goal);
    if (diff == 0) return l10n.insightsOnTrack;
    return diff > 0 ? l10n.insightsAhead(diff) : l10n.insightsBehind(-diff);
  }

  /// The year head's sentence — the same pace comparison one register up.
  /// Only meaningful for the current year; a past year or all time has no
  /// "pace" left to keep.
  String _yearHeadline(AppLocalizations l10n,
      {required int read, required int goal, required bool isPaceable}) {
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

  /// Cached books store author *names*, not ids, so the most-read row can't
  /// link straight through. Resolve the name against the catalogue and open
  /// their page; if that can't be done (offline, or an author the catalogue
  /// doesn't know under that spelling) fall back to search rather than
  /// leaving the tap dead.
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
    if (context.mounted) {
      context.push('${Routes.catalogSearch}?q=${Uri.encodeQueryComponent(name)}');
    }
  }

  void _openShare(PeriodShare share) {
    showSharePeriodSheet(
      context,
      dataBuilder: share.dataBuilder,
      initialCaption: share.caption,
      canNameBooks: share.canNameBooks,
      initialFormat: share.initialFormat,
    );
  }

  /// The long-press verb — one almanac line lifted as a slip.
  void _shareRow(
    AppLocalizations l10n, {
    required String window,
    required String label,
    required String value,
    String? footnote,
    List<bool>? lamps,
  }) {
    showRowSlipSheet(
      context,
      card: RowSlipCard(
        eyebrow: '${l10n.insightsRowSlipEyebrow} · $window',
        label: label,
        value: value,
        footnote: footnote,
        lamps: lamps,
      ),
      initialCaption: '$label: $value ${l10n.insightsShareCaptionSuffix}',
    );
  }

  void _openSittings(PeriodRange range, String title) =>
      showSittingsSheet(context, range: range, title: title);

  void _openFinished({required PeriodRange range, int? year, bool showGoal = false, String? title}) {
    context.push(
      Routes.insightsFinished,
      extra: FinishedBooksArgs(range: range, year: year, showGoal: showGoal, customTitle: title),
    );
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
            final dataYears = <int>{
              thisYear,
              for (final h in hits)
                if (h.entry.status == 'read') (h.entry.finishDate ?? h.entry.updatedAt).year,
            }.toList()
              ..sort((a, b) => b.compareTo(a));
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
            final share = periodSummary == null
                ? null
                : composePeriodShare(
                    l10n: l10n,
                    period: _period,
                    range: range,
                    summary: periodSummary,
                    yearStats: yearStats,
                    year: _year,
                    paceDiff: _period == InsightsPeriod.year && _year == thisYear && yearStats != null
                        ? _paceDiff(yearStats.booksRead, goal)
                        : null,
                  );

            return Stack(
              children: [
                ListView(
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
                      years: dataYears,
                    ),
                    SizedBox(height: 16),
                    if (periodSummary == null)
                      ListSkeleton()
                    else ...[
                      ..._almanac(
                        l10n,
                        range: range,
                        summary: periodSummary,
                        yearStats: yearStats,
                        goal: goal,
                        thisYear: thisYear,
                      ),
                      if (_period == InsightsPeriod.year &&
                          yearStats != null &&
                          timeStats?.busiestWeekday != null &&
                          timeStats?.busiestHour != null) ...[
                        SizedBox(height: 18),
                        _BusiestTimeInsight(
                            weekday: timeStats!.busiestWeekday!, hour: timeStats.busiestHour!),
                      ],
                    ],
                    SizedBox(height: 18),
                    _ReadingFactCard(),
                    // Clearance so the last row never hides under the seal.
                    SizedBox(height: 56),
                  ],
                ),
                if (share != null)
                  Positioned(
                    right: 6,
                    bottom: 10,
                    child: WaxSeal(
                      label: l10n.insightsSealSend,
                      onTap: () => _openShare(share),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- almanac

  List<Widget> _almanac(
    AppLocalizations l10n, {
    required PeriodRange range,
    required PeriodSummary summary,
    required InsightsStats? yearStats,
    required int goal,
    required int thisYear,
  }) {
    switch (_period) {
      case InsightsPeriod.today:
        return _todayLedger(l10n, range, summary);
      case InsightsPeriod.week:
        return _weekLedger(l10n, range, summary);
      case InsightsPeriod.month:
        return _monthLedger(l10n, range, summary);
      case InsightsPeriod.threeMonths:
      case InsightsPeriod.sixMonths:
        return _stretchLedger(l10n, range, summary);
      case InsightsPeriod.year:
        return _yearLedger(l10n, range, summary, yearStats!, goal, thisYear);
    }
  }

  Widget _headline(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          text,
          style: GoogleFonts.fraunces(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
      );

  /// The fleuron + italic closing line that ends every ledger.
  List<Widget> _closing(String? text) => [
        if (text != null) ...[
          const SizedBox(height: 14),
          Center(
            child: Text('❦',
                style: TextStyle(fontSize: 12, color: AppColors.gold, letterSpacing: 6)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontStyle: FontStyle.italic,
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ];

  List<Widget> _todayLedger(AppLocalizations l10n, PeriodRange range, PeriodSummary summary) {
    final window = DateFormat('EEEE · d MMMM').format(range.start);
    final dayOfYear = range.start.difference(DateTime(range.start.year)).inDays + 1;
    final empty = summary.totalSeconds == 0 && summary.sittingsCount == 0;
    final streak = summary.streakDays ?? 0;
    final books = summary.booksInHand ?? const <BookInHand>[];
    final duration = formatDuration(Duration(seconds: summary.totalSeconds));

    return [
      AlmanacHead(left: window, right: l10n.insightsHeadIssueNo(dayOfYear)),
      _headline(empty ? l10n.insightsNoSessionToday : l10n.insightsPeriodTodayHeadline),
      // R2 (owner pick, 26 Aug 2026): figures over their names, two to a row
      // — one downward glance per stat, no left-right eye travel. Doors and
      // long-press slips ride the cells unchanged.
      StatPairsGrid(pairs: [
        if (!empty) ...[
          StatPair(
            value: duration,
            label: l10n.insightsRowTimeRead,
            onTap: () => _openSittings(range, window),
            onLongPress: () =>
                _shareRow(l10n, window: window, label: l10n.insightsRowTimeRead, value: duration),
          ),
          StatPair(
            value: '${summary.pagesRead}',
            suffix: l10n.insightsUnitPages,
            label: l10n.insightsRowPagesTurned,
            onTap: () => _openSittings(range, window),
          ),
          StatPair(
            value: '${summary.sittingsCount}',
            label: l10n.insightsRowSittings,
            onTap: () => _openSittings(range, window),
          ),
        ],
        if (streak > 0)
          StatPair(
            value: '$streak',
            suffix: l10n.insightsUnitDays,
            label: l10n.insightsRowStreak,
            // The heatmap is the streak's map — the door flips to Month.
            onTap: () => setState(() => _period = InsightsPeriod.month),
            onLongPress: () => _shareRow(
              l10n,
              window: window,
              label: l10n.insightsRowStreak,
              value: '$streak ${l10n.insightsUnitDays}',
              lamps: summary.recentDays,
            ),
          ),
      ]),
      if (!empty && books.isNotEmpty) ...[
        const SizedBox(height: 14),
        SectRule(l10n.insightsSectInHandCount(books.length)),
        const SizedBox(height: 2),
        // A name is read, not scanned — the title stays a sentence with its
        // page snug after it. Three at most (B3); a crowded day overflows
        // into the sittings sheet.
        for (final book in books.take(3))
          TightRow(
            name: book.title,
            trailing: book.currentPage != null
                ? '${l10n.insightsPageN(book.currentPage!)}'
                    "${book.pageCount != null ? ' ${l10n.insightsOfN('${book.pageCount}')}' : ''}"
                : null,
            onTap: () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
          ),
        if (books.length > 3)
          InkWell(
            onTap: () => _openSittings(range, window),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.insightsAndMoreBooks(books.length - 3),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.oxblood,
                ),
              ),
            ),
          ),
      ],
      const SizedBox(height: 14),
      SectRule(l10n.insightsSectWeekSoFar),
      const SizedBox(height: 10),
      CardLamps(days: summary.recentDays ?? const [], size: 14, gap: 7),
      if (empty && streak > 0) ...[
        const SizedBox(height: 6),
        Text(
          l10n.insightsStreakStillOpen(streak).toUpperCase(),
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.gold,
          ),
        ),
      ],
      ..._closing(streak > 0 && !empty ? l10n.insightsStreakDays(streak) : null),
    ];
  }

  List<Widget> _weekLedger(AppLocalizations l10n, PeriodRange range, PeriodSummary summary) {
    final window = l10n.insightsEyebrowThisWeek;
    final duration = formatDuration(Duration(seconds: summary.totalSeconds));
    final previous = summary.previousTotalSeconds;
    final closing = summary.totalSeconds == 0
        ? l10n.insightsClosingWeekNone
        : (previous != null && previous > 0 && summary.totalSeconds > previous)
            ? l10n.insightsClosingWeekUp
            : l10n.insightsClosingWeekSteady;
    return [
      AlmanacHead(left: window),
      _headline(l10n.insightsPeriodWeekHeadline),
      StatPairsGrid(pairs: [
        StatPair(
          value: duration,
          label: l10n.insightsRowTimeRead,
          onTap: () => _openSittings(range, window),
          onLongPress: () =>
              _shareRow(l10n, window: window, label: l10n.insightsRowTimeRead, value: duration),
        ),
        StatPair(
          value: '${summary.pagesRead}',
          suffix: l10n.insightsUnitPages,
          label: l10n.insightsRowPagesTurned,
          onTap: () => _openSittings(range, window),
        ),
        StatPair(
          value: '${summary.sittingsCount}',
          label: l10n.insightsRowSittings,
          onTap: () => _openSittings(range, window),
        ),
      ]),
      const SizedBox(height: 14),
      SectRule(l10n.insightsSectPace),
      const SizedBox(height: 10),
      WeekBarsPlate(buckets: summary.dailyBuckets ?? const [0, 0, 0, 0, 0, 0, 0], weekStart: range.start),
      ..._closing(closing),
    ];
  }

  List<Widget> _monthLedger(AppLocalizations l10n, PeriodRange range, PeriodSummary summary) {
    final now = DateTime.now();
    final isCurrent = range.start.year == now.year && range.start.month == now.month;
    final window = DateFormat('MMMM yyyy').format(range.start);
    final (read, elapsed) = summary.daysReadOfElapsed;
    final duration = formatDuration(Duration(seconds: summary.totalSeconds));
    return [
      AlmanacHead(
        left: window,
        right: isCurrent ? l10n.insightsHeadToDate(DateFormat('d MMM').format(now)) : null,
      ),
      _headline(l10n.insightsPeriodMonthHeadline),
      StatPairsGrid(pairs: [
        StatPair(
          value: '${summary.booksFinishedCount}',
          label: l10n.insightsRowBooksFinished,
          onTap: () => _openFinished(
            range: range,
            title: '${l10n.insightsRowBooksFinished} · ${DateFormat.MMMM().format(range.start)}',
          ),
        ),
        StatPair(
          value: '${summary.pagesRead}',
          suffix: l10n.insightsUnitPages,
          label: l10n.insightsRowPagesTurned,
          onTap: () => _openSittings(range, window),
        ),
        StatPair(
          value: duration,
          label: l10n.insightsRowTimeRead,
          onTap: () => _openSittings(range, window),
        ),
        StatPair(
          value: '$read',
          suffix: l10n.insightsOfN('$elapsed'),
          label: l10n.insightsRowDaysRead,
        ),
      ]),
      const SizedBox(height: 14),
      SectRule(l10n.insightsSectCalendar),
      const SizedBox(height: 10),
      DatedCalendar(
        cells: summary.calendarCells ?? const [],
        onReadDayTap: (day) => _openSittings(
          PeriodRange(start: day, end: day.add(const Duration(days: 1))),
          DateFormat('EEEE · d MMM').format(day),
        ),
      ),
      ..._closing(l10n.insightsClosingMonthDays(read)),
    ];
  }

  List<Widget> _stretchLedger(AppLocalizations l10n, PeriodRange range, PeriodSummary summary) {
    final window = _period == InsightsPeriod.threeMonths
        ? l10n.insightsEyebrowLast3Months
        : l10n.insightsEyebrowLast6Months;
    final duration = formatDuration(Duration(seconds: summary.totalSeconds));
    return [
      AlmanacHead(left: window),
      _headline(l10n.insightsPeriodMultiMonthHeadline),
      StatPairsGrid(pairs: [
        StatPair(
          value: '${summary.booksFinishedCount}',
          label: l10n.insightsRowBooksFinished,
          onTap: () => _openFinished(
            range: range,
            title: '${l10n.insightsRowBooksFinished} · $window',
          ),
        ),
        StatPair(
          value: '${summary.pagesRead}',
          suffix: l10n.insightsUnitPages,
          label: l10n.insightsRowPagesTurned,
          onTap: () => _openSittings(range, window),
        ),
        StatPair(
          value: duration,
          label: l10n.insightsRowHours,
          onTap: () => _openSittings(range, window),
        ),
      ]),
      const SizedBox(height: 14),
      SectRule(l10n.insightsSectPace),
      const SizedBox(height: 10),
      TrendPlate(buckets: summary.trendBuckets ?? const [], start: range.start, end: range.end),
      ..._closing(l10n.insightsClosingStretch(summary.booksFinishedCount)),
    ];
  }

  /// The pace cell's two-word figure — "3 ahead" fits a stat pair where
  /// "3 ahead of pace" would not; the label beneath says the rest.
  String _paceShort(AppLocalizations l10n, int diff) {
    if (diff > 0) return l10n.insightsPaceAheadShort(diff);
    if (diff < 0) return l10n.insightsPaceBehindShort(-diff);
    return l10n.insightsPaceOnTrackShort;
  }

  List<Widget> _yearLedger(
    AppLocalizations l10n,
    PeriodRange range,
    PeriodSummary summary,
    InsightsStats stats,
    int goal,
    int thisYear,
  ) {
    final isPaceable = _year == thisYear;
    final window = _year == null ? l10n.insightsAllTime : '$_year';
    final duration = formatDuration(Duration(seconds: summary.totalSeconds));
    final pages = NumberFormat.decimalPattern().format(stats.pagesRead);
    final paceDiff = _paceDiff(stats.booksRead, goal);
    final spines = [
      for (final book in summary.booksFinished.reversed)
        ShelfSpine(pages: book.pageCount, seed: ShelfSpine.seedOf(book.title), title: book.title),
    ];
    return [
      AlmanacHead(
        left: window,
        right: isPaceable ? l10n.insightsHeadToDate(DateFormat('d MMM').format(DateTime.now())) : null,
      ),
      _headline(_yearHeadline(l10n, read: stats.booksRead, goal: goal, isPaceable: isPaceable)),
      StatPairsGrid(pairs: [
        StatPair(
          value: '${stats.booksRead}',
          suffix: isPaceable ? l10n.insightsOfN('$goal') : null,
          label: l10n.insightsRowBooksFinished,
          onTap: () => _openFinished(range: range, year: _year, showGoal: isPaceable),
          onLongPress: () => _shareRow(
            l10n,
            window: window,
            label: l10n.insightsRowBooksFinished,
            value: '${stats.booksRead}',
            footnote: isPaceable ? _paceNote(l10n, stats.booksRead, goal) : null,
          ),
        ),
        StatPair(
          value: pages,
          suffix: l10n.insightsUnitPages,
          label: l10n.insightsRowPagesTurned,
        ),
        StatPair(
          value: duration,
          label: l10n.insightsRowHours,
          onTap: () => _openSittings(range, window),
        ),
        if (isPaceable)
          StatPair(
            value: _paceShort(l10n, paceDiff),
            label: l10n.insightsRowAgainstPace,
            valueColor: paceDiff >= 0 ? AppColors.moss : AppColors.oxblood,
            // The goal is edited where the "of 30" is explained — but the
            // cell is also a door to the dialog for the reader mid-ledger.
            onTap: () => _editGoal(goal),
          ),
      ]),
      if (stats.topAuthor case final author?)
        TightRow(
          label: l10n.insightsRowMostRead,
          name: author,
          trailing: '· ${stats.topAuthorCount}',
          onTap: () => _openAuthor(context, ref, author),
          onLongPress: () => _shareRow(
            l10n,
            window: window,
            label: l10n.insightsRowMostRead,
            value: author,
          ),
        ),
      if (stats.longestBookPages > 0)
        TightRow(
          label: l10n.insightsRowLongest,
          name: stats.longestBookTitle ?? '',
          trailing: '· ${stats.longestBookPages} ${l10n.insightsUnitPages}',
          onTap: stats.longestBookWorkId == null || stats.longestBookEditionId == null
              ? null
              : () => context.push(
                    Routes.bookDetailPath(stats.longestBookWorkId!, stats.longestBookEditionId!),
                  ),
        ),
      if (spines.isNotEmpty) ...[
        const SizedBox(height: 14),
        SectRule(l10n.insightsSectShelf),
        const SizedBox(height: 10),
        ShelfStrip(spines: spines, height: 56),
      ],
      // The detail charts keep living below the fold, unchanged — the
      // redesign changed what's above them, not the almanac's appendix.
      if (stats.busiestMonthCount > 0) ...[
        SizedBox(height: 18),
        _ChartLabel(l10n.insightsPerMonth),
        SizedBox(height: 10),
        _MonthBars(counts: stats.booksPerMonth, max: stats.busiestMonthCount),
      ],
      if (stats.peakPagesMonth > 0) ...[
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
    ];
  }
}

/// The all-time "you read most on Thursdays, often around 9–10 PM" note —
/// a genuine all-time pattern, kept under Year alongside the appendix charts.
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
      decoration:
          BoxDecoration(color: AppColors.darkPanel, borderRadius: BorderRadius.circular(12)),
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
              style: TextStyle(color: AppColors.onDark, fontSize: 11.5, height: 1.5),
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

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.counts, required this.max});

  final List<int> counts;
  final int max;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 92, not 90 — count label + bar + axis letter overflowed by 2px on
      // device (debug banner), caught on the emulator pass.
      height: 92,
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
                      style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
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
/// honest preview of what the almanac grows into.
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
    final ringColor = showTarget ? AppColors.gold : AppColors.line;
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
                      valueColor: AlwaysStoppedAnimation(ringColor),
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
