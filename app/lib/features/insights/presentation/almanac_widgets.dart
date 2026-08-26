import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../period_summary.dart';

/// The almanac page's building blocks (Direction B, chosen 26 Aug 2026).
/// No card boxes anywhere — hairlines and type do all the work. Two verbs
/// govern every row: tap navigates (every oxblood value is a door), long-
/// press shares (the row slip); the widgets here just expose both callbacks.

/// The heavy ink rule that opens the almanac, with the window's small-caps
/// label left and an accent (issue number, "to the 26th") right in gold.
class AlmanacHead extends StatelessWidget {
  const AlmanacHead({super.key, required this.left, this.right});

  final String left;
  final String? right;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(child: _SmallCaps(left, color: AppColors.inkSoft)),
          if (right != null) _SmallCaps(right!, color: AppColors.gold),
        ],
      ),
    );
  }
}

/// A small-caps section head with a trailing hairline — "IN HAND · 2 BOOKS",
/// "THE CALENDAR".
class SectRule extends StatelessWidget {
  const SectRule(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SmallCaps(text, color: AppColors.inkSoft),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: AppColors.line)),
      ],
    );
  }
}

class _SmallCaps extends StatelessWidget {
  const _SmallCaps(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: color,
      ),
    );
  }
}

/// One stat pair — a figure with its name directly beneath it (R2, the
/// owner's pick 26 Aug 2026). The built ledger's label-left / figure-right
/// rows made the eye walk a ~200dp dotted bridge per line ("look left, then
/// look right — uncomfortable"); a pair is read in one downward glance. The
/// oxblood figure is still the door (house rule), long-press still lifts the
/// slip.
class StatPair {
  const StatPair({
    required this.value,
    required this.label,
    this.suffix,
    this.valueColor,
    this.onTap,
    this.onLongPress,
  });

  final String value;

  /// The small grey unit after the figure — "pp", "of 30", "days".
  final String? suffix;

  /// Rendered as small caps under the figure.
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}

/// The pairs, two to a row, each cell hairlined — an almanac's data table,
/// not a wall of tiles: no boxes, type and rules only.
class StatPairsGrid extends StatelessWidget {
  const StatPairsGrid({super.key, required this.pairs});

  final List<StatPair> pairs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < pairs.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatCell(pair: pairs[i])),
              const SizedBox(width: 18),
              Expanded(
                child: i + 1 < pairs.length
                    ? _StatCell(pair: pairs[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.pair});

  final StatPair pair;

  @override
  Widget build(BuildContext context) {
    final cell = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: pair.value,
              style: GoogleFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: pair.valueColor ?? AppColors.oxblood,
                height: 1,
              ),
              children: [
                if (pair.suffix case final suffix?)
                  TextSpan(
                    text: ' $suffix',
                    // Explicit Inter — a nested span inherits Fraunces from
                    // the figure otherwise, and the unit must read as UI.
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkSoft,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            pair.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
    if (pair.onTap == null && pair.onLongPress == null) return cell;
    return InkWell(onTap: pair.onTap, onLongPress: pair.onLongPress, child: cell);
  }
}

/// A name line — In hand, Most read, Longest. A name is read, not scanned,
/// so it stays a left-clustered sentence: optional small label, the name in
/// Fraunces italic (oxblood when it is a door), the detail snug after it.
class TightRow extends StatelessWidget {
  const TightRow({
    super.key,
    this.label,
    required this.name,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final String? label;
  final String name;
  final String? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (label case final l?) ...[
            Text(l, style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fraunces(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                color: onTap == null ? AppColors.ink : AppColors.oxblood,
              ),
            ),
          ),
          if (trailing case final t?) ...[
            const SizedBox(width: 7),
            Text(t, style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return row;
    return InkWell(onTap: onTap, onLongPress: onLongPress, child: row);
  }
}

/// The week's seven-bar plate — the page-side twin of the card's bars,
/// Monday-first, best day oxblood.
class WeekBarsPlate extends StatelessWidget {
  const WeekBarsPlate({super.key, required this.buckets, required this.weekStart});

  final List<int> buckets;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) {
    final max = buckets.isEmpty ? 0 : buckets.reduce((a, b) => a > b ? a : b);
    var peak = 0;
    for (var i = 1; i < buckets.length; i++) {
      if (buckets[i] > buckets[peak]) peak = i;
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
                            : (i == peak ? AppColors.oxblood : AppColors.goldSoft),
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
                  DateFormat.E().format(weekStart.add(Duration(days: i))).substring(0, 1),
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

/// The 3/6-month pace-line plate with its month labels.
class TrendPlate extends StatelessWidget {
  const TrendPlate({super.key, required this.buckets, required this.start, required this.end});

  final List<int> buckets;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 46,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPlatePainter(buckets)),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat.MMM().format(start),
                style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft)),
            // `end` is exclusive — label the last day inside the window.
            Text(DateFormat.MMM().format(end.subtract(const Duration(days: 1))),
                style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft)),
          ],
        ),
      ],
    );
  }
}

class _TrendPlatePainter extends CustomPainter {
  _TrendPlatePainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = AppColors.line
        ..strokeWidth = 1,
    );
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
    canvas.drawPath(
      Path()..addPolygon(points, false),
      Paint()
        ..color = AppColors.oxblood
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 3, Paint()..color = AppColors.oxblood);
  }

  @override
  bool shouldRepaint(covariant _TrendPlatePainter old) => old.values != values;
}

/// The dated month calendar (B6) — the almanac prints its dates where the
/// share card keeps silhouette. Ink numerals on gold read days, paper on the
/// deep-oxblood heavy days, grey on dashed future cells, today ringed and
/// bold. A read day is a door to that day's sittings; empty days are inert —
/// there's nothing behind them.
class DatedCalendar extends StatelessWidget {
  const DatedCalendar({super.key, required this.cells, this.onReadDayTap});

  final List<CalendarCell> cells;
  final void Function(DateTime day)? onReadDayTap;

  @override
  Widget build(BuildContext context) {
    // Sunday-first, matching `_monthCells` (2026-01-04 is a real Sunday).
    final dayLetters = [
      for (var i = 0; i < 7; i++) DateFormat.E().format(DateTime(2026, 1, 4 + i)).substring(0, 1),
    ];
    final now = DateTime.now();
    return Column(
      children: [
        Row(
          children: [
            for (final letter in dayLetters)
              Expanded(
                child: Text(
                  letter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemBuilder: (context, i) {
            final cell = cells[i];
            final date = cell.date;
            if (date == null) return const SizedBox.shrink();
            final isToday = date.day == now.day && date.month == now.month && date.year == now.year;
            final numeral = Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: cell.isRead || isToday ? FontWeight.w700 : FontWeight.w500,
                color: cell.isFuture
                    ? AppColors.stampGrey
                    : cell.isHeavy
                        ? AppColors.paper
                        : (cell.isRead ? AppColors.ink : AppColors.inkSoft),
              ),
            );
            final box = Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cell.isFuture
                    ? Colors.transparent
                    : cell.isHeavy
                        ? AppColors.oxblood
                        : (cell.isRead ? AppColors.gold : AppColors.paperDeep),
                borderRadius: BorderRadius.circular(6),
                border: cell.isFuture
                    ? Border.all(color: AppColors.line)
                    : (isToday ? Border.all(color: AppColors.oxblood, width: 1.5) : null),
              ),
              child: numeral,
            );
            if (!cell.isRead || onReadDayTap == null) return box;
            return InkWell(
              onTap: () => onReadDayTap!(date),
              borderRadius: BorderRadius.circular(6),
              child: box,
            );
          },
        ),
      ],
    );
  }
}

/// The one control on the almanac page — the gold wax seal, pressed
/// bottom-right: ⇲ SEND. Opens the share sheet with the window's graphical
/// card (never a full-page capture — owner pick, 26 Aug 2026).
class WaxSeal extends StatelessWidget {
  const WaxSeal({super.key, required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.3, -0.4),
              colors: [Color(0xFFD2A94F), Color(0xFFB8862B), Color(0xFF8F681E)],
              stops: [0.0, 0.6, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8F681E).withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: const Color(0xFF5E1F26).withValues(alpha: 0.25), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.ios_share, size: 15, color: Color(0xFF3D2C07)),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 6.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF3D2C07),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
