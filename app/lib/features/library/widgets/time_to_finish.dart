import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format_duration.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/providers/insights_providers.dart';
import '../../insights/reading_pace.dart';

/// "Time to finish" — the same estimate on every book page (Area 13, P1–P9).
///
/// One widget with one state machine over `(pageCount, currentPage, status,
/// pace sample)`, because the four progress surfaces already taught us what
/// happens when the same idea is built separately per screen (CLAUDE.md,
/// 19 Jul 2026). It renders nothing at all rather than guessing: no page
/// count and no way to fix it, or a finished book with no logged sittings,
/// both produce `SizedBox.shrink()`.
enum TimeToFinishVariant {
  /// The block inside the book page's reading card — big number, units,
  /// and the pace footnote (P1/P2/P6/P8/P9).
  card,

  /// One gold line for a book the reader doesn't own, where there is no
  /// reading card to live in and it must not compete with "Add to library"
  /// (P7).
  strip,
}

class TimeToFinish extends ConsumerWidget {
  const TimeToFinish({
    super.key,
    required this.pageCount,
    this.language,
    this.entry,
    this.variant = TimeToFinishVariant.card,
    this.onAddPageCount,
    this.dividerAbove = false,
  });

  /// From the shared catalogue (Layer 1) — present on a book whether or not
  /// the reader owns it, which is what lets this render on every book page.
  final int? pageCount;

  /// The edition's language, so a reader with a measured മലയാളം pace gets it
  /// used here instead of their English one.
  final String? language;

  /// Null on a book that isn't in the library — then there is no progress, no
  /// status and no book-specific pace, and only the total can be shown.
  final LibraryEntry? entry;

  final TimeToFinishVariant variant;

  /// Opens whatever the host screen uses to set a page count (the reading
  /// card's progress editor). Null hides the prompt entirely — on an unowned
  /// book there is nothing to open.
  final VoidCallback? onAddPageCount;

  /// Draws the hairline that separates this from whatever sits above it —
  /// *only* when there is something to separate. The host can't decide that
  /// itself without duplicating this widget's state machine, and a rule left
  /// hanging over an empty block is exactly the kind of drift this widget
  /// exists to prevent.
  final bool dividerAbove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = _content(context, ref);
    if (content == null) return const SizedBox.shrink();
    if (!dividerAbove) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 13),
        Container(height: 1, color: AppColors.line),
        SizedBox(height: 13),
        content,
      ],
    );
  }

  Widget? _content(BuildContext context, WidgetRef ref) {
    final pace = ref.watch(readingPaceProvider);
    final entry = this.entry;

    // A finished book stops estimating and reports what it actually cost.
    if (entry != null && entry.status == 'read') {
      return _finished(context, ref, pace, entry);
    }

    if (pageCount == null || pageCount! <= 0) {
      if (variant == TimeToFinishVariant.strip) return null;
      return _NoPageCount(onAddPageCount: onAddPageCount);
    }

    // The book's own pace beats the reader's average once it has one (P2).
    final bookPace = entry == null ? null : ref.watch(bookPaceProvider(entry.id));
    final estimate = estimateFinish(
      pageCount: pageCount,
      pace: pace,
      currentPage: entry?.currentPage,
      language: language,
      bookPagesPerHour: bookPace?.pagesPerHour,
    );
    if (estimate == null) return null;

    return variant == TimeToFinishVariant.strip
        ? _Strip(estimate: estimate, pace: pace, language: language)
        : _EstimateBlock(
            estimate: estimate,
            pace: pace,
            language: language,
            pageCount: pageCount!,
            currentPage: entry?.currentPage,
            bookPace: bookPace,
          );
  }

  Widget? _finished(BuildContext context, WidgetRef ref, ReadingPace pace, LibraryEntry entry) {
    final sessions = ref.watch(readingSessionsStreamProvider).valueOrNull;
    if (sessions == null) return null;
    final own = sessions.where((s) => s.libraryEntryId == entry.id).toList();
    // Read, but never timed — a book finished before the timer existed, or an
    // import. There is nothing true to say, so it says nothing.
    if (own.isEmpty) return null;
    if (variant == TimeToFinishVariant.strip) return null;

    return _FinishedBlock(actual: actualFor(own), pace: pace, pageCount: pageCount);
  }
}

/// "42" for a whole number, "41.6" otherwise — a pace claimed to three decimal
/// places would be pretending to a precision the sample can't carry.
String _pph(double value) =>
    value >= 10 ? value.round().toString() : value.toStringAsFixed(1);

/// The estimate rendered in weeks, or in days when weeks would round to
/// something meaningless ("≈ 0 weeks").
String? _spanLabel(AppLocalizations l10n, double? weeks) {
  if (weeks == null) return null;
  if (weeks < 1.5) {
    final days = (weeks * 7).ceil();
    return days <= 0 ? null : l10n.paceDays(days);
  }
  return l10n.paceWeeks(weeks.round());
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// The label strip every variant of the block shares.
class _Header extends StatelessWidget {
  const _Header({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.inkSoft,
      ),
    );
  }
}

/// P1 / P2 / P6 — the estimate inside the reading card.
class _EstimateBlock extends StatelessWidget {
  const _EstimateBlock({
    required this.estimate,
    required this.pace,
    required this.language,
    required this.pageCount,
    required this.currentPage,
    required this.bookPace,
  });

  final FinishEstimate estimate;
  final ReadingPace pace;
  final String? language;
  final int pageCount;
  final int? currentPage;

  /// This book's own pace and how many of its sittings measured it — both, so
  /// the footnote can't quote the global sample size for a per-book claim.
  final ({double pagesPerHour, int sessions})? bookPace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final assumed = estimate.isAssumedPace;
    final started = (currentPage ?? 0) > 0;
    final pagesLeft = pageCount - (currentPage ?? 0).clamp(0, pageCount);
    final span = _spanLabel(l10n, estimate.weeks);
    final numberColour = assumed ? AppColors.stampGrey : AppColors.oxblood;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          text: '◷ ${l10n.paceLabel} · ${assumed ? l10n.paceLabelAssumed : l10n.paceLabelYours}',
        ),
        SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatDuration(Duration(seconds: estimate.remainingSeconds)),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 28,
                    height: 1,
                    color: numberColour,
                  ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assumed
                          ? l10n.paceAssumedValue(_pph(estimate.pagesPerHour))
                          : (started ? l10n.paceLeft : l10n.paceOfReading),
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
                    ),
                    if (!assumed)
                      Text(
                        l10n.pacePages(pagesLeft),
                        style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // The two units that make the hours mean something. Only ever shown
        // when they rest on a real figure — no habit, no "weeks".
        if (estimate.sittings != null || span != null) ...[
          SizedBox(height: 9),
          Row(
            children: [
              if (estimate.sittings != null)
                Expanded(
                  child: _UnitTile(
                    value: '≈ ${estimate.sittings}',
                    label: l10n.paceSittingsUnit,
                  ),
                ),
              if (estimate.sittings != null && span != null) SizedBox(width: 6),
              if (span != null)
                Expanded(
                  child: _UnitTile(
                    value: span,
                    label: l10n.paceAtYourRate,
                    // Gold: this is the unit that actually decides whether a
                    // book gets read, because it knows the reader's week.
                    gold: true,
                  ),
                ),
            ],
          ),
        ],
        if (estimate.finishDate != null && started) ...[
          SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_outlined, size: 13, color: AppColors.inkSoft),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.paceFinishAround(_fmtDate(estimate.finishDate!)),
                  style: TextStyle(fontSize: 11, color: AppColors.ink, height: 1.35),
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: 8),
        Text(
          _footnote(l10n),
          style: TextStyle(fontSize: 10, color: AppColors.inkSoft, height: 1.45),
        ),
      ],
    );
  }

  /// An estimate you can't audit is a horoscope — every state names the
  /// figure it used and how much reading it rests on.
  String _footnote(AppLocalizations l10n) {
    if (estimate.isAssumedPace) {
      return l10n.paceAssumedHint(pace.sampleSessions, minSessionsForPace);
    }
    final parts = <String>[];
    if (bookPace != null) {
      parts.add(l10n.paceBookPaceLine(_pph(bookPace!.pagesPerHour), bookPace!.sessions));
      if (pace.pagesPerHour != null) parts.add(l10n.paceVsUsual(_pph(pace.pagesPerHour!)));
    } else if (estimate.usedLanguagePace && language != null) {
      parts.add(l10n.paceLanguageLine(language!, _pph(estimate.pagesPerHour)));
    } else {
      parts.add(l10n.paceYourPaceLine(_pph(estimate.pagesPerHour), pace.sampleSessions));
    }
    if (pace.weeklySeconds > 0) {
      parts.add(l10n.paceWeeklyHabit(formatDuration(Duration(seconds: pace.weeklySeconds))));
    }
    return parts.join(' ');
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.value, required this.label, this.gold = false});

  final String value;
  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: gold ? AppColors.goldSoft : AppColors.paper,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: gold ? AppColors.gold : AppColors.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: gold ? AppColors.gold : AppColors.ink,
            ),
          ),
          SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 9, color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// P8 — a read book shows the actual, and marks its own homework.
class _FinishedBlock extends StatelessWidget {
  const _FinishedBlock({required this.actual, required this.pace, required this.pageCount});

  final FinishedActual actual;
  final ReadingPace pace;
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final calibration = _calibration(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(text: '✓ ${l10n.paceFinished}', color: AppColors.moss),
        SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatDuration(Duration(seconds: actual.totalSeconds)),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 26, height: 1, color: AppColors.moss),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.paceYouReadItIn,
                        style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25)),
                    Text(l10n.paceActualSittings(actual.sessions),
                        style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (calibration != null) ...[
          SizedBox(height: 9),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.paperDeep,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              calibration,
              style: TextStyle(fontSize: 10.5, color: AppColors.ink, height: 1.45),
            ),
          ),
        ],
      ],
    );
  }

  /// What the reader's usual pace would have predicted, against what it
  /// actually took. Only when both halves are real: a measured overall pace,
  /// a page count, and a measured pace on this book.
  String? _calibration(AppLocalizations l10n) {
    final usual = pace.pagesPerHour;
    final here = actual.pagesPerHour;
    final pages = pageCount;
    if (!pace.isMeasured || usual == null || here == null || pages == null || pages <= 0) {
      return null;
    }
    final predicted = (pages / usual * 3600).round();
    if (predicted <= 0 || actual.totalSeconds <= 0) return null;
    final diff = ((actual.totalSeconds - predicted) / predicted * 100).round();
    // Within a tenth either way is agreement, not a finding worth a sentence.
    if (diff.abs() < 10) return null;
    final headline = l10n.paceCalibration(formatDuration(Duration(seconds: predicted)));
    final detail = diff > 0
        ? l10n.paceCalibrationOver(diff, _pph(here))
        : l10n.paceCalibrationUnder(diff.abs(), _pph(here));
    return '$headline $detail';
  }
}

/// P9 — the page count is the only input that can actually be missing.
class _NoPageCount extends StatelessWidget {
  const _NoPageCount({required this.onAddPageCount});

  final VoidCallback? onAddPageCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(text: '◷ ${l10n.paceLabel}'),
        SizedBox(height: 7),
        Text(
          l10n.paceNoPageCount,
          style: TextStyle(fontSize: 12, color: AppColors.ink, height: 1.35),
        ),
        Text(
          l10n.paceNoPageCountSub,
          style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.4),
        ),
        if (onAddPageCount != null) ...[
          SizedBox(height: 9),
          GestureDetector(
            onTap: onAddPageCount,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.paceAddPageCount,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.gold),
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    l10n.paceAddPageCountHint,
                    style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.search_off, size: 13, color: AppColors.stampGrey),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                l10n.paceHiddenFromFilters,
                style: TextStyle(fontSize: 10, color: AppColors.stampGrey),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// P7 — one gold line on a book the reader doesn't own.
class _Strip extends StatelessWidget {
  const _Strip({required this.estimate, required this.pace, required this.language});

  final FinishEstimate estimate;
  final ReadingPace pace;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final duration = formatDuration(Duration(seconds: estimate.totalSeconds));
    final assumed = estimate.isAssumedPace;
    final detail = <String>[
      if (estimate.sittings != null) l10n.paceSittings(estimate.sittings!),
      if (assumed)
        l10n.paceAssumedHint(pace.sampleSessions, minSessionsForPace)
      else if (estimate.usedLanguagePace && language != null)
        l10n.paceLanguageLine(language!, _pph(estimate.pagesPerHour))
      else
        l10n.paceYourPaceLine(_pph(estimate.pagesPerHour), pace.sampleSessions),
    ].join(' · ');

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: assumed ? AppColors.paperDeep : AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: assumed ? AppColors.line : AppColors.gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('◷ ',
              style: TextStyle(
                  fontSize: 12, color: assumed ? AppColors.stampGrey : AppColors.gold)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assumed ? l10n.paceStripAssumed(duration) : l10n.paceStripValue(duration),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: assumed ? AppColors.inkSoft : AppColors.gold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
