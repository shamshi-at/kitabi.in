import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A rotating literary quote on the dark accent panel — one of the
/// typographic flourishes the Reading Room voice is built on (never an
/// animated gimmick; docs/screen-design.md). Tap for another.
///
/// Lived on the profile screen until 16 Jul 2026, where it was seen about
/// once a month; the owner moved it to Home so the inspiration actually
/// lands. Shared rather than duplicated, so it can sit wherever it earns
/// its place. The quotes are the sign-in screen's l10n trio — one source,
/// no drifting literals.
class QuoteCard extends StatefulWidget {
  const QuoteCard({super.key});

  @override
  State<QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<QuoteCard> {
  int _index = 0;

  /// Tapping must always *change* the quote — a random pick that lands on the
  /// one already showing reads as a broken tap. Step past it instead.
  void _next(int count) {
    setState(() {
      if (count < 2) return;
      _index = (_index + 1 + Random().nextInt(count - 1)) % count;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final quotes = [
      (l10n.signInQuote1, l10n.signInQuote1Author),
      (l10n.signInQuote2, l10n.signInQuote2Author),
      (l10n.signInQuote3, l10n.signInQuote3Author),
    ];
    final (quote, author) = quotes[_index % quotes.length];
    return GestureDetector(
      onTap: () => _next(quotes.length),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkPanel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '“$quote”',
              textAlign: TextAlign.center,
              // Constant colors on the constant-dark panel — goldSoft here was
              // dark-brown-on-dark-brown at night.
              style: GoogleFonts.fraunces(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: AppColors.onDark,
                height: 1.45,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '— ${author.toUpperCase()} · ${l10n.quoteTapForNew.toUpperCase()}',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onDarkSoft, fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
