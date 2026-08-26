import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_localizations.dart';
import 'period_card_data.dart';
import 'period_card_viz.dart';
import 'share_logo.dart';
import 'share_palette.dart';

/// The shareable reading-recap image, rebuilt graphical (the card catalogue,
/// 26 Aug 2026): the window's own visualization — lamps, bars, calendar,
/// pace line, the year shelf — rides ON the image instead of being stripped
/// at share time. Three formats, one widget: each of Story (9:16), Square
/// (1:1) and Slip (5:3) is its own layout of the same [PeriodCardData]
/// parts, never a scaled-down story (the 27 Jul square-overflow lesson).
///
/// Still deliberately data-agnostic: the caller composes every string and
/// list, this widget only ever lays them out — no period switching, no date
/// math, nothing that could drift out of sync with the page's own ledger.
class PeriodShareCard extends StatelessWidget {
  const PeriodShareCard({
    super.key,
    required this.data,
    this.format = ShareCardFormat.story,
  });

  final PeriodCardData data;
  final ShareCardFormat format;

  @override
  Widget build(BuildContext context) {
    return switch (format) {
      ShareCardFormat.story => _Story(data: data),
      ShareCardFormat.square => _Square(data: data),
      ShareCardFormat.slip => _Slip(data: data),
    };
  }
}

/// The gold-framed paper plate every format sits on — outer frame, inner
/// hairline, soft vignette. [ornate] adds the corner fleurons (Story only;
/// below ~200px they read as smudges).
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, this.ornate = false, this.radius = 16});

  final Widget child;
  final bool ornate;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ShareCardPalette.paper,
        border: Border.all(color: ShareCardPalette.gold, width: 1.5),
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.8,
                  colors: [
                    ShareCardPalette.gold.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(radius <= 12 ? 4 : 7),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: ShareCardPalette.gold.withValues(alpha: 0.5),
                    width: 0.75,
                  ),
                  borderRadius: BorderRadius.circular(radius <= 12 ? 8 : 10),
                ),
              ),
            ),
          ),
          if (ornate) ...[
            Positioned(top: 12, left: 15, child: _fleuron()),
            Positioned(top: 12, right: 15, child: _fleuron()),
          ],
          child,
        ],
      ),
    );
  }

  Widget _fleuron() => Text(
        '❦',
        style: TextStyle(fontSize: 8, color: ShareCardPalette.gold.withValues(alpha: 0.7)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.fontSize = 7.5});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: ShareCardPalette.goldSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: ShareCardPalette.oxblood,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.value, required this.label, required this.valueSize, this.labelSize = 7});

  final String value;
  final String label;
  final double valueSize;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // scaleDown, never wrap: "1h 10m" at story size is wider than the
        // card and stacked into two lines without this (emulator pass).
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: GoogleFonts.fraunces(
              fontSize: valueSize,
              fontWeight: FontWeight.w600,
              color: ShareCardPalette.oxblood,
              height: 0.98,
            ),
          ),
        ),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: ShareCardPalette.inkSoft,
              ),
            ),
          ),
      ],
    );
  }
}

/// The window's visualization at a per-format scale — the switch lives here
/// once, not once per layout.
class _Viz extends StatelessWidget {
  const _Viz({required this.data, required this.format});

  final PeriodCardData data;
  final ShareCardFormat format;

  @override
  Widget build(BuildContext context) {
    final small = format == ShareCardFormat.slip;
    final mid = format == ShareCardFormat.square;
    if (data.lamps case final lamps?) {
      return CardLamps(days: lamps, size: small ? 8 : (mid ? 10 : 12), gap: small ? 3.5 : 5);
    }
    if (data.weekBars case final bars?) {
      return CardBars(
        buckets: bars,
        labels: data.weekBarLabels ?? const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        height: small ? 24 : (mid ? 34 : 40),
      );
    }
    if (data.heatCells case final cells?) {
      return CardHeat(cells: cells, width: small ? 84 : (mid ? 96 : 116));
    }
    if (data.trendBuckets case final trend?) {
      return CardTrend(buckets: trend, height: small ? 24 : (mid ? 34 : 40));
    }
    if (data.shelf case final shelf?) {
      return ShelfStrip(spines: shelf, height: small ? 28 : (mid ? 42 : 52));
    }
    return const SizedBox.shrink();
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.withTagline, this.logoSize = 12});

  final bool withTagline;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShareLogo(size: logoSize),
            const SizedBox(width: 5),
            Text(
              'kitabi.in',
              style: TextStyle(
                fontSize: logoSize * 0.75,
                fontWeight: FontWeight.w700,
                color: ShareCardPalette.oxblood,
              ),
            ),
          ],
        ),
        if (withTagline) ...[
          const SizedBox(height: 2),
          Text(
            l10n.shareTagline,
            style: const TextStyle(fontSize: 7, color: ShareCardPalette.inkSoft),
          ),
        ],
      ],
    );
  }
}

class _Story extends StatelessWidget {
  const _Story({required this.data});

  final PeriodCardData data;

  @override
  Widget build(BuildContext context) {
    final hasPill = data.pill?.trim().isNotEmpty ?? false;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: _CardFrame(
        ornate: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            children: [
              if (hasPill) _Pill(text: data.pill!),
              SizedBox(height: hasPill ? 14 : 26),
              _Hero(value: data.heroValue, label: data.heroLabel, valueSize: 40),
              const SizedBox(height: 8),
              Text(
                data.subLine,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 8.5, color: ShareCardPalette.inkSoft),
              ),
              const SizedBox(height: 14),
              _Viz(data: data, format: ShareCardFormat.story),
              const Spacer(),
              Text(
                data.closingLine,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontStyle: FontStyle.italic,
                  fontSize: 10.5,
                  height: 1.4,
                  color: ShareCardPalette.ink,
                ),
              ),
              const Spacer(),
              Container(width: 36, height: 1, color: ShareCardPalette.line),
              const SizedBox(height: 8),
              const _Wordmark(withTagline: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.data});

  final PeriodCardData data;

  @override
  Widget build(BuildContext context) {
    final hasPill = data.pill?.trim().isNotEmpty ?? false;
    return AspectRatio(
      aspectRatio: 1,
      child: _CardFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Column(
            children: [
              if (hasPill) _Pill(text: data.pill!, fontSize: 6.5),
              SizedBox(height: hasPill ? 10 : 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    _Hero(
                      value: data.heroValue,
                      label: data.heroLabel,
                      valueSize: 30,
                      labelSize: 6.5,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: _Viz(data: data, format: ShareCardFormat.square)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                data.subLine,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 8, color: ShareCardPalette.inkSoft),
              ),
              const SizedBox(height: 5),
              Text(
                data.closingLine,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontStyle: FontStyle.italic,
                  fontSize: 9.5,
                  height: 1.35,
                  color: ShareCardPalette.ink,
                ),
              ),
              const Spacer(),
              const _Wordmark(withTagline: false, logoSize: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slip extends StatelessWidget {
  const _Slip({required this.data});

  final PeriodCardData data;

  @override
  Widget build(BuildContext context) {
    final hasPill = data.pill?.trim().isNotEmpty ?? false;
    final tone = data.pillTone == PillTone.moss ? const Color(0xFF48663F) : ShareCardPalette.gold;
    return AspectRatio(
      aspectRatio: 5 / 3,
      child: _CardFrame(
        radius: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: _Hero(
                          value: data.heroValue,
                          label: data.heroLabel,
                          valueSize: 22,
                          labelSize: 6,
                        ),
                      ),
                    ),
                    Container(width: 1, color: ShareCardPalette.line),
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.subLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: ShareCardPalette.inkSoft,
                              ),
                            ),
                            const SizedBox(height: 5),
                            _Viz(data: data, format: ShareCardFormat.slip),
                            if (hasPill) ...[
                              const SizedBox(height: 4),
                              // A slip has no pill row — the extra fact rides
                              // the viz footer in its tone instead.
                              Text(
                                data.pill!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 6,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: tone,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: ShareCardPalette.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.closingLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fraunces(
                          fontStyle: FontStyle.italic,
                          fontSize: 7.5,
                          color: ShareCardPalette.inkSoft,
                        ),
                      ),
                    ),
                    const Text(
                      'kitabi.in',
                      style: TextStyle(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w700,
                        color: ShareCardPalette.oxblood,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The long-press row slip (B, chosen) — one almanac line lifted as an image:
/// eyebrow, the row verbatim, its micro-viz when it has one, the wordmark.
/// Locked to slip proportions; a single row has no story.
class RowSlipCard extends StatelessWidget {
  const RowSlipCard({
    super.key,
    required this.eyebrow,
    required this.label,
    required this.value,
    this.footnote,
    this.lamps,
    this.closingLine,
  });

  final String eyebrow;
  final String label;
  final String value;
  final String? footnote;
  final List<bool>? lamps;
  final String? closingLine;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 5 / 3,
      child: _CardFrame(
        radius: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  fontSize: 6,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: ShareCardPalette.inkSoft,
                ),
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 10, color: ShareCardPalette.ink),
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ShareCardPalette.oxblood,
                      height: 1,
                    ),
                  ),
                ],
              ),
              if (lamps case final days?) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: CardLamps(days: days, size: 8, gap: 3.5),
                ),
              ],
              if (footnote case final note?) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    note.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 6,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: ShareCardPalette.gold,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: ShareCardPalette.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        closingLine ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fraunces(
                          fontStyle: FontStyle.italic,
                          fontSize: 7.5,
                          color: ShareCardPalette.inkSoft,
                        ),
                      ),
                    ),
                    const Text(
                      'kitabi.in',
                      style: TextStyle(
                        fontSize: 6.5,
                        fontWeight: FontWeight.w700,
                        color: ShareCardPalette.oxblood,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
