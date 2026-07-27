import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

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
    this.square = false,
  });

  final String heroValue;
  final String heroLabel;
  final String subLine;
  final String closingLine;

  /// Story (9:16) is the default — it's the shape a phone screen fills
  /// natively; Square (1:1) is the toggle for a feed post instead of a story.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AspectRatio(
      aspectRatio: square ? 1 : 9 / 16,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.paper,
          border: Border.all(color: AppColors.gold, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        // Square (1:1) has noticeably less absolute height than Story (9:16)
        // at the same width, so it can't afford Story's spacing or type scale
        // — a `Spacer`-based "float everything in the middle" layout overflowed
        // here rather than shrinking (real bug, caught on-device 27 Jul 2026,
        // not in review). Every size below is square-aware for the same
        // reason; this box must never scroll, because whatever it lays out to
        // is exactly the pixels that get rasterised and shared.
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: square ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('❦', style: TextStyle(fontSize: square ? 12 : 15, color: AppColors.gold)),
            Text(
              heroValue,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: square ? 36 : 56,
                fontWeight: FontWeight.w600,
                color: AppColors.oxblood,
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
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            Text(
              subLine,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: square ? 9.5 : 10.5, color: AppColors.inkSoft),
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
                color: AppColors.ink,
              ),
            ),
            _Wordmark(tagline: l10n.shareTagline, square: square),
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
        Container(width: 32, height: 1, color: AppColors.line),
        SizedBox(height: square ? 6 : 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: square ? 11 : 13,
              height: square ? 11 : 13,
              child: CustomPaint(painter: _LogoPainter()),
            ),
            const SizedBox(width: 5),
            Text(
              'kitabi.in',
              style: TextStyle(
                fontSize: square ? 9 : 10,
                fontWeight: FontWeight.w700,
                color: AppColors.oxblood,
              ),
            ),
          ],
        ),
        if (!square) ...[
          const SizedBox(height: 2),
          Text(tagline, style: TextStyle(fontSize: 7.5, color: AppColors.inkSoft)),
        ],
      ],
    );
  }
}

/// The open-book-with-gold-ribbon mark, drawn to spec rather than loaded from
/// an asset — same shapes as `landing-page/logo.svg`, scaled to whatever size
/// the caller needs. No letter K anywhere (brand rule, 3 Jul 2026).
class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    canvas.save();
    canvas.scale(s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(16, 16, 480, 480), const Radius.circular(112)),
      Paint()..color = AppColors.oxblood,
    );
    final page = Paint()..color = AppColors.paper;
    canvas.drawPath(
      Path()
        ..moveTo(114, 160)
        ..cubicTo(164, 136, 218, 136, 250, 156)
        ..lineTo(250, 366)
        ..cubicTo(218, 348, 164, 348, 114, 370)
        ..close(),
      page,
    );
    canvas.drawPath(
      Path()
        ..moveTo(398, 160)
        ..cubicTo(348, 136, 294, 136, 262, 156)
        ..lineTo(262, 366)
        ..cubicTo(294, 348, 348, 348, 398, 370)
        ..close(),
      page,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(250, 148, 12, 222), const Radius.circular(6)),
      Paint()..color = AppColors.oxbloodDeep,
    );
    canvas.drawLine(
      const Offset(298, 252),
      const Offset(362, 252),
      Paint()
        ..color = AppColors.gold
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(240, 356)
        ..lineTo(272, 356)
        ..lineTo(272, 428)
        ..lineTo(256, 410)
        ..lineTo(240, 428)
        ..close(),
      Paint()..color = AppColors.gold,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}
