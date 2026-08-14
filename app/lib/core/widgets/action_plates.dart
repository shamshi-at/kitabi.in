import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// The two plates that make the app's "put this book somewhere" offer:
/// pressed leather with gold foil for the primary, card stock with a gold
/// hairline for the secondary ("Foil & Serif", docs/book-page-unowned-mockup.html
/// round 2, direction B2).
///
/// They live here rather than on the book page because the *scanner's* result
/// screen makes the same offer, to the same reader, about the same book — and
/// a button rebuilt per screen is how the four progress surfaces drifted
/// (CLAUDE.md, Lessons learned). One widget, every caller.
class ActionPlateColors {
  const ActionPlateColors._();

  static const leather = Color(0xFF7E2A33);
  static const leatherDeep = Color(0xFF571E25);
  static const foil = Color(0xFFEFD9A4);
  static const foilDim = Color(0xFFC9A253);
}

/// The primary: gold-foil Fraunces on pressed leather, with the ❦ the design
/// doc asks for (already rendered as plain text elsewhere in the app).
class LeatherPlate extends StatelessWidget {
  const LeatherPlate({super.key, required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [ActionPlateColors.leather, ActionPlateColors.leatherDeep],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: ActionPlateColors.leatherDeep.withValues(alpha: 0.34),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('❦', style: TextStyle(color: ActionPlateColors.foilDim, fontSize: 13)),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: ActionPlateColors.foil,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The secondary: the paper counterpart to the leather plate — a gold hairline
/// on card stock. Its label follows the theme (the foil does not), so it takes
/// gold at night where oxblood would sit at 4.4:1 on the dark card.
class PaperPlate extends StatelessWidget {
  const PaperPlate({super.key, required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final fill = AppColors.card;
    final ink = AppColors.dark ? AppColors.gold : AppColors.oxblood;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.gold),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ink,
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
