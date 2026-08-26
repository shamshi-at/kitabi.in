import '../../insights/period_summary.dart';

/// The three layouts of the one shared-image widget (the card catalogue,
/// 26 Aug 2026): Story is the phone-native broadcast, Square the feed post,
/// Slip the chat bubble. Each is its own arrangement of the same parts —
/// never a scaled-down story (the 27 Jul square-overflow lesson, structural).
enum ShareCardFormat { story, square, slip }

/// The tone of the one extra fact — gold for a streak, moss for a
/// vs-last-window gain. On Slip (which has no pill row) the fact rides the
/// visualization's footer in this colour instead.
enum PillTone { gold, moss }

/// One spine on the year-shelf visualization. [pages] drives width (null =
/// the minimum — an unknown page count must not disappear the book), [seed]
/// drives colour and the height jitter, hashed from the title so the shelf is
/// stable across rebuilds and runs.
class ShelfSpine {
  const ShelfSpine({required this.pages, required this.seed, required this.title});

  final int? pages;
  final int seed;
  final String title;

  /// Cross-run-stable title hash — Dart's String.hashCode is not guaranteed
  /// stable between runs, and a shelf that reshuffles its colours every app
  /// launch reads as random rather than "your year".
  static int seedOf(String title) {
    var h = 0;
    for (final unit in title.codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return h;
  }
}

/// Everything one shared image renders, fully composed by the caller — the
/// card widget lays out strings and lists, it never period-switches or does
/// date math (the same contract the old typography-only card had, kept).
/// Exactly one visualization list should be non-null; the card renders
/// whichever it finds, so a new period means a new field here, not a new
/// codepath in the widget.
class PeriodCardData {
  const PeriodCardData({
    required this.heroValue,
    required this.heroLabel,
    required this.subLine,
    required this.closingLine,
    this.pill,
    this.pillTone = PillTone.gold,
    this.lamps,
    this.weekBars,
    this.weekBarLabels,
    this.heatCells,
    this.trendBuckets,
    this.shelf,
  });

  final String heroValue;
  final String heroLabel;
  final String subLine;
  final String closingLine;

  /// One extra fact, badged above the numeral (Story/Square) or folded into
  /// the viz footer (Slip); null/empty renders nothing — not every window has
  /// a fact worth badging.
  final String? pill;
  final PillTone pillTone;

  /// Today — the last 7 days, oldest first, today last.
  final List<bool>? lamps;

  /// Week — seconds per day, Monday first, with single-letter labels.
  final List<int>? weekBars;
  final List<String>? weekBarLabels;

  /// Month — the weekday-aligned calendar (bare cells on cards; dates are a
  /// page-only affordance, B6).
  final List<CalendarCell>? heatCells;

  /// 3/6 months — weekly seconds, oldest first.
  final List<int>? trendBuckets;

  /// Year — one spine per finished book, finish order.
  final List<ShelfSpine>? shelf;
}
