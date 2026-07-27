import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'share_palette.dart';

/// The open-book-with-gold-ribbon mark, drawn to spec rather than loaded from
/// an asset — same shapes as `landing-page/logo.svg`, scaled to whatever size
/// the caller needs. No letter K anywhere (brand rule, 3 Jul 2026). One
/// painter for the whole share-card family (period, book, entity) — the
/// generic `Icons.menu_book` tile the book/entity cards used to draw was a
/// different mark than the one the period card shipped.
class ShareLogo extends StatelessWidget {
  const ShareLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: ShareLogoPainter()));
  }
}

class ShareLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    canvas.save();
    canvas.scale(s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(16, 16, 480, 480), const Radius.circular(112)),
      Paint()..color = ShareCardPalette.oxblood,
    );
    final page = Paint()..color = ShareCardPalette.paper;
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
      Paint()..color = ShareCardPalette.oxbloodDeep,
    );
    canvas.drawLine(
      const Offset(298, 252),
      const Offset(362, 252),
      Paint()
        ..color = ShareCardPalette.gold
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
      Paint()..color = ShareCardPalette.gold,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ShareLogoPainter oldDelegate) => false;
}

/// The shared footer strip on the book and entity cards — logo + kitabi.in on
/// the left, the tagline on the right, above a hairline rule. (The period
/// card's centered wordmark is a deliberately different layout and keeps its
/// own.)
class ShareCardFooter extends StatelessWidget {
  const ShareCardFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: ShareCardPalette.line),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const ShareLogo(size: 16),
                const SizedBox(width: 5),
                Text(
                  'kitabi.in',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: ShareCardPalette.oxblood,
                  ),
                ),
              ],
            ),
            Text(
              l10n.shareTagline,
              style: TextStyle(fontSize: 8, color: ShareCardPalette.inkSoft),
            ),
          ],
        ),
      ],
    );
  }
}
