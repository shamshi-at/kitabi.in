import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rotating literary quote on the dark accent panel — one of the
/// typographic flourishes the Reading Room voice is built on (never an
/// animated gimmick; docs/screen-design.md). Tap for another.
///
/// Lived on the profile screen until 16 Jul 2026, where it was seen about
/// once a month; the owner moved it to Home so the inspiration actually
/// lands. Shared rather than duplicated, so it can sit wherever it earns
/// its place.
class QuoteCard extends StatefulWidget {
  const QuoteCard({super.key});

  @override
  State<QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<QuoteCard> {
  int _index = 0;

  static const _quotes = [
    ('"I have always imagined that Paradise will be a kind of library."', 'BORGES'),
    ('"A reader lives a thousand lives before he dies."', 'GEORGE R.R. MARTIN'),
    ('"A book must be the axe for the frozen sea within us."', 'KAFKA'),
  ];

  /// Tapping must always *change* the quote — a random pick that lands on the
  /// one already showing reads as a broken tap. Step past it instead.
  void _next() {
    setState(() {
      if (_quotes.length < 2) return;
      _index = (_index + 1 + Random().nextInt(_quotes.length - 1)) % _quotes.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (quote, author) = _quotes[_index];
    return GestureDetector(
      onTap: _next,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              quote,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.goldSoft,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '— $author · TAP FOR A NEW ONE',
              style: TextStyle(color: AppColors.inkSoft, fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
