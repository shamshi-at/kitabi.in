import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import 'net_image.dart';
import 'ticker_text.dart';

/// One frame for every cover in the app (docs/screen-design.md): a real
/// cover image fills it edge-to-edge; with no `coverUrl`, this renders a
/// "typeset" cover instead — title + author set on a color derived from the
/// book's own title/author, so the shelf never shows a broken-image icon.
class TypesetCover extends StatelessWidget {
  const TypesetCover({
    super.key,
    required this.title,
    this.author,
    this.coverUrl,
    this.width = 30,
    this.height = 44,
  });

  final String title;
  final String? author;
  final String? coverUrl;
  final double width;
  final double height;

  /// The deterministic base colour a book derives from its title/author — the
  /// same hue the generated cover uses. Exposed so the book page can wash its
  /// hero in the book's own colour (and any cover-derived accent stays in sync
  /// with the shelf), photo cover or not.
  static Color accentFor(String title, String? author) {
    final seed = '$title${author ?? ''}'.hashCode.abs();
    final hue = (seed % 360).toDouble();
    final sat = 0.26 + (seed % 5) * 0.035;
    final light = 0.25 + (seed % 4) * 0.03;
    return HSLColor.fromAHSL(1, hue, sat, light).toColor();
  }

  /// A soft wash of [accentFor] — the book page's hero band. Clamps a
  /// saturation *floor* (raising a muted cover's colour up, never diluting
  /// it further) and a lightness ceiling below paper-white, so every book
  /// gets a wash with real presence — a bug fix: the previous version forced
  /// lightness to a flat 0.9 while also *halving* saturation, which made an
  /// already-muted cover (e.g. a faded brown photo scan) wash out to nearly
  /// nothing against the paper background.
  static Color tintFor(String title, String? author) {
    final base = HSLColor.fromColor(accentFor(title, author));
    final sat = base.saturation.clamp(0.32, 0.6);
    return HSLColor.fromAHSL(1, base.hue, sat, 0.80).toColor();
  }

  /// Lead-in before an overflowing title/author runs its one ticker pass —
  /// jittered per book so a shelf of long titles doesn't move in lockstep
  /// (docs/screen-design.md: overflow-only, once on first render, never in
  /// loops on a full grid).
  Duration get _tickDelay =>
      Duration(milliseconds: 1200 + ('$title${author ?? ''}'.hashCode.abs() % 5) * 180);

  /// A deterministic, muted 2-stop gradient derived from the book — same book
  /// always looks the same, but saturation/lightness vary a little per book so
  /// a shelf of generated covers reads as a varied set of spines, not a wall of
  /// one flat colour.
  List<Color> _derivedGradient() {
    final seed = '$title${author ?? ''}'.hashCode.abs();
    final hue = (seed % 360).toDouble();
    final sat = 0.26 + (seed % 5) * 0.035; // 0.26 .. 0.40
    final light = 0.25 + (seed % 4) * 0.03; // 0.25 .. 0.34
    final top = HSLColor.fromAHSL(1, hue, sat, light).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 12) % 360, sat, (light - 0.09).clamp(0.1, 1)).toColor();
    return [top, bottom];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Color(0x472B2118), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // The grid passes width/height: infinity (fill the cell), so text and
      // padding sizes must come from the REAL laid-out size — width * 0.24 on
      // an infinite width renders no text at all (this is why library covers
      // were blank). LayoutBuilder gives the actual pixels.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite ? constraints.maxWidth : width;
          final h = constraints.maxHeight.isFinite ? constraints.maxHeight : height;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                // Disk-cached (net_image.dart): a cover scrolled out of the
                // grid repaints from cache instead of re-downloading.
                netImage(
                  coverUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _typeset(w, h),
                )
              else
                _typeset(w, h),
              // Spine shade — left edge, every cover in the app carries this.
              Align(
                alignment: Alignment.centerLeft,
                child: Container(width: w * 0.09, color: Color(0x38000000)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _typeset(double w, double h) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _derivedGradient(),
        ),
      ),
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(w * 0.14, h * 0.09, w * 0.1, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TickerText(
                  title,
                  maxLines: 3,
                  startDelay: _tickDelay,
                  style: GoogleFonts.fraunces(
                    color: AppColors.goldSoft,
                    // Scale with width; the max clamp keeps a big grid cover
                    // from a giant title, the min keeps a tiny chip legible
                    // without overflowing its 44px box.
                    fontSize: (w * 0.16).clamp(6.0, 22.0),
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: h * 0.04),
                // A gold hairline — the "one line that stays with you".
                Container(width: w * 0.34, height: 1, color: AppColors.gold),
              ],
            ),
          ),
          if (author != null)
            Padding(
              padding: EdgeInsets.fromLTRB(w * 0.14, 0, w * 0.1, h * 0.06),
              child: TickerText(
                author!.toUpperCase(),
                startDelay: _tickDelay,
                style: TextStyle(
                  color: AppColors.goldSoft.withValues(alpha: 0.85),
                  fontSize: (w * 0.1).clamp(6.0, 12.0),
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
