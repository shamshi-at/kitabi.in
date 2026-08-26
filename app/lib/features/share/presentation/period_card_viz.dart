import 'package:flutter/material.dart';

import '../../insights/period_summary.dart';
import 'period_card_data.dart';
import 'share_palette.dart';

/// The per-window visualizations that ride on the shared image (the card
/// catalogue, 26 Aug 2026) — the whole point of the graphical card family is
/// that these are ON the image, not stripped at share time. All of them draw
/// in [ShareCardPalette] constants, never `AppColors`, for the same reason
/// the palette exists: a card captured from dark mode must not rasterise
/// dark. The insights page reuses [ShelfStrip] and [CardLamps] for its own
/// plates, so the page's viz and the card's can't drift apart.

/// The streak lamps — seven days, lit or dark, today (the last) glowing.
class CardLamps extends StatelessWidget {
  const CardLamps({super.key, required this.days, this.size = 12, this.gap = 5});

  final List<bool> days;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, on) in days.indexed) ...[
          if (i > 0) SizedBox(width: gap),
          _Lamp(on: on, today: i == days.length - 1, size: size),
        ],
      ],
    );
  }
}

class _Lamp extends StatelessWidget {
  const _Lamp({required this.on, required this.today, required this.size});

  final bool on;
  final bool today;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: on
            ? const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFFF0DCA0), ShareCardPalette.gold],
                stops: [0.0, 0.75],
              )
            : null,
        color: on ? null : ShareCardPalette.paperDeep,
        border: Border.all(
          color: on ? ShareCardPalette.goldInk : ShareCardPalette.line,
        ),
        boxShadow: [
          if (on)
            BoxShadow(
              color: ShareCardPalette.gold.withValues(alpha: today ? 0.8 : 0.5),
              blurRadius: today ? 7 : 5,
            ),
          if (today && !on)
            BoxShadow(
              color: ShareCardPalette.gold.withValues(alpha: 0.5),
              blurRadius: 6,
            ),
        ],
      ),
    );
  }
}

/// The week's seven bars — best day oxblood, the rest gold; zero days render
/// as short stubs, never gaps (a missing bar reads as missing data, not a
/// quiet day).
class CardBars extends StatelessWidget {
  const CardBars({super.key, required this.buckets, required this.labels, this.height = 40});

  final List<int> buckets;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = buckets.isEmpty ? 0 : buckets.reduce((a, b) => a > b ? a : b);
    var peak = 0;
    for (var i = 1; i < buckets.length; i++) {
      if (buckets[i] > buckets[peak]) peak = i;
    }
    // Runner-up gets full gold so the week reads as shape, not one spike.
    var runnerUp = -1;
    for (var i = 0; i < buckets.length; i++) {
      if (i == peak) continue;
      if (runnerUp == -1 || buckets[i] > buckets[runnerUp]) runnerUp = i;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, seconds) in buckets.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      height: max == 0
                          ? 3
                          : (height * (seconds / max)).clamp(seconds > 0 ? 4.0 : 3.0, height),
                      decoration: BoxDecoration(
                        color: seconds == 0
                            ? ShareCardPalette.paperDeep
                            : i == peak
                                ? ShareCardPalette.oxblood
                                : (i == runnerUp
                                    ? ShareCardPalette.gold
                                    : ShareCardPalette.goldSoft),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2.5)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final label in labels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 6.5, color: ShareCardPalette.inkSoft),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The month's calendar heat, bare cells — gold read days, deep oxblood heavy
/// days, dashed future, ring on today. Trailing weeks that hold nothing but
/// future days are cropped so a card sent mid-month doesn't lead with blank
/// rows. Dates are deliberately absent here: a recipient reads the shape, and
/// at slip scale a numeral is smear (dates are the page's affordance, B6).
class CardHeat extends StatelessWidget {
  const CardHeat({super.key, required this.cells, this.width = 120});

  final List<CalendarCell> cells;
  final double width;

  @override
  Widget build(BuildContext context) {
    var visible = List.of(cells);
    while (visible.length >= 7) {
      final lastWeek = visible.sublist(visible.length - 7);
      final allBlank = lastWeek.every((c) => c.date == null || c.isFuture);
      if (!allBlank) break;
      visible = visible.sublist(0, visible.length - 7);
    }
    final cell = (width - 6 * 3) / 7;
    return SizedBox(
      width: width,
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final c in visible)
            SizedBox(
              width: cell,
              height: cell,
              child: c.date == null
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.isFuture
                            ? Colors.transparent
                            : c.isHeavy
                                ? ShareCardPalette.oxblood
                                : (c.isRead ? ShareCardPalette.gold : ShareCardPalette.paperDeep),
                        borderRadius: BorderRadius.circular(2.5),
                        border: c.isFuture ? Border.all(color: ShareCardPalette.line) : null,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// The 3/6-month pace line — weekly points over a hairline baseline, end dot
/// on the current week, y-scale from the window's own max.
class CardTrend extends StatelessWidget {
  const CardTrend({super.key, required this.buckets, this.height = 40});

  final List<int> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TrendPainter(buckets)),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = ShareCardPalette.line
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return;
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * (i / (values.length - 1)),
          size.height - (values[i] / max) * size.height * 0.9,
        ),
    ];
    canvas.drawPath(
      Path()..addPolygon(points, false),
      Paint()
        ..color = ShareCardPalette.oxblood
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 2.8, Paint()..color = ShareCardPalette.oxblood);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.values != values;
}

/// The year as a shelf — one spine per finished book, width from its page
/// count (clamped so an unknown count still stands and a doorstop doesn't
/// hog the ledge), height jittered and colour picked from the title hash so
/// the shelf is generated from the reader's actual year and no two are
/// alike. Standing on the same gold ledge the Shelves wall uses.
class ShelfStrip extends StatelessWidget {
  const ShelfStrip({super.key, required this.spines, this.height = 52});

  final List<ShelfSpine> spines;
  final double height;

  static const _tints = [
    ShareCardPalette.oxblood,
    Color(0xFF43617E), // slate
    Color(0xFF48663F), // moss
    ShareCardPalette.gold,
    ShareCardPalette.oxbloodDeep,
    ShareCardPalette.ink,
    Color(0xFF9A8F7C), // stamp grey
    ShareCardPalette.goldInk,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, spine) in spines.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                _Spine(spine: spine, maxHeight: height),
              ],
            ],
          ),
        ),
        Container(
          height: 4,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFC9973B), ShareCardPalette.goldInk],
            ),
            boxShadow: [
              BoxShadow(
                color: ShareCardPalette.ink.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Spine extends StatelessWidget {
  const _Spine({required this.spine, required this.maxHeight});

  final ShelfSpine spine;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final pages = spine.pages;
    // Width ∝ pages, clamped 4–12 units (spec): a 100-page book is a sliver,
    // a 900-page one a slab, an unknown count the minimum — present, not gone.
    final width = pages == null ? 4.0 : (4.0 + 8.0 * ((pages - 80) / 820)).clamp(4.0, 12.0);
    final jitter = 0.62 + 0.38 * ((spine.seed >> 3) % 100) / 100;
    return Container(
      width: width,
      height: maxHeight * jitter,
      decoration: BoxDecoration(
        color: ShelfStrip._tints[spine.seed % ShelfStrip._tints.length],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(1.5)),
      ),
      // The pale spine-edge highlight that makes the row read as books.
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 1,
          margin: const EdgeInsets.only(left: 1.5),
          color: ShareCardPalette.card.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}
