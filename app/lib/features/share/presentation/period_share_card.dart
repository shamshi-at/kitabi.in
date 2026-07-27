import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/app_localizations.dart';
import 'share_logo.dart';
import 'share_palette.dart';

/// The shareable reading-recap image — third member of the share-card family
/// alongside [BookShareCard] and the personal-endorsement variant (27 Jul
/// 2026 redesign). Deliberately data-agnostic: the caller resolves whichever
/// single figure is most flattering for the period in question (a duration
/// for Today/Week, a book count for Month/3-6-months/Year) into plain
/// strings, so this widget only ever lays out typography — no period
/// switching, no date math, nothing that could drift out of sync with the
/// flagship card's own logic.
class PeriodShareCard extends StatelessWidget {
  const PeriodShareCard({
    super.key,
    required this.heroValue,
    required this.heroLabel,
    required this.subLine,
    required this.closingLine,
    this.pill,
    this.square = false,
  });

  final String heroValue;
  final String heroLabel;
  final String subLine;
  final String closingLine;

  /// One extra fact, badged above the numeral instead of added as a second
  /// line of text (mockups 10i) — the caller decides what's most flattering
  /// per period (a streak, a vs-last-period delta, a pace note) and passes
  /// it fully composed; null/empty renders nothing, since not every period
  /// has a fact worth badging.
  final String? pill;

  /// Story (9:16) is the default — it's the shape a phone screen fills
  /// natively; Square (1:1) is the toggle for a feed post instead of a story.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasPill = pill != null && pill!.trim().isNotEmpty;
    return AspectRatio(
      aspectRatio: square ? 1 : 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: ShareCardPalette.paper,
          border: Border.all(color: ShareCardPalette.gold, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // A second, thinner frame plus a soft gold vignette behind the
            // numeral (mockup 10j) — the shipped card had shed both of these
            // from its own original mockup; this closes that gap rather than
            // adding a new one. Pure decoration: no data, applies regardless
            // of period or the pill above.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.75,
                    colors: [ShareCardPalette.gold.withValues(alpha: 0.16), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: ShareCardPalette.gold.withValues(alpha: 0.55), width: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 18,
              child: Text('❦', style: TextStyle(fontSize: 9, color: ShareCardPalette.gold.withValues(alpha: 0.7))),
            ),
            Positioned(
              top: 16,
              right: 18,
              child: Text('❦', style: TextStyle(fontSize: 9, color: ShareCardPalette.gold.withValues(alpha: 0.7))),
            ),
            // Square (1:1) has noticeably less absolute height than Story
            // (9:16) at the same width, so it can't afford Story's spacing or
            // type scale — a `Spacer`-based "float everything in the middle"
            // layout overflowed here rather than shrinking (real bug, caught
            // on-device 27 Jul 2026, not in review). Every size below is
            // square-aware for the same reason; this box must never scroll,
            // because whatever it lays out to is exactly the pixels that get
            // rasterised and shared.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: square ? 16 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The single top-center ❦ (10g) is replaced by the two
                  // corner fleurons in the Stack above — this spacer just
                  // keeps the same vertical rhythm without a redundant glyph.
                  SizedBox(height: square ? 8 : 10),
                  if (hasPill)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: square ? 9 : 12, vertical: square ? 3 : 4),
                      decoration: BoxDecoration(color: ShareCardPalette.goldSoft, borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        pill!.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: square ? 7.5 : 8.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: ShareCardPalette.oxblood,
                        ),
                      ),
                    ),
                  Text(
                    heroValue,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: square ? 36 : 56,
                      fontWeight: FontWeight.w600,
                      color: ShareCardPalette.oxblood,
                      height: 1,
                    ),
                  ),
                  if (heroLabel.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: square ? 3 : 6),
                      child: Text(
                        heroLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: ShareCardPalette.inkSoft,
                        ),
                      ),
                    ),
                  Text(
                    subLine,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: square ? 9.5 : 10.5, color: ShareCardPalette.inkSoft),
                  ),
                  Text(
                    closingLine,
                    textAlign: TextAlign.center,
                    maxLines: square ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fraunces(
                      fontStyle: FontStyle.italic,
                      fontSize: square ? 10.5 : 13,
                      height: 1.4,
                      color: ShareCardPalette.ink,
                    ),
                  ),
                  _Wordmark(tagline: l10n.shareTagline, square: square),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.tagline, required this.square});

  final String tagline;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '❦ ❦ ❦',
          style: TextStyle(fontSize: square ? 7 : 8, color: ShareCardPalette.gold.withValues(alpha: 0.6)),
        ),
        SizedBox(height: square ? 6 : 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShareLogo(size: square ? 11 : 13),
            const SizedBox(width: 5),
            Text(
              'kitabi.in',
              style: TextStyle(
                fontSize: square ? 9 : 10,
                fontWeight: FontWeight.w700,
                color: ShareCardPalette.oxblood,
              ),
            ),
          ],
        ),
        if (!square) ...[
          const SizedBox(height: 2),
          Text(tagline, style: TextStyle(fontSize: 7.5, color: ShareCardPalette.inkSoft)),
        ],
      ],
    );
  }
}

