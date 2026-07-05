import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null)
            Image.network(
              coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _typeset(),
            )
          else
            _typeset(),
          // Spine shade — left edge, every cover in the app carries this.
          Align(
            alignment: Alignment.centerLeft,
            child: Container(width: width * 0.09, color: Color(0x38000000)),
          ),
        ],
      ),
    );
  }

  Widget _typeset() {
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
            padding: EdgeInsets.fromLTRB(width * 0.18, height * 0.1, width * 0.1, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.fraunces(
                    color: AppColors.goldSoft,
                    fontSize: width * 0.24,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: height * 0.05),
                // A gold hairline — the "one line that stays with you".
                Container(width: width * 0.34, height: 1, color: AppColors.gold),
              ],
            ),
          ),
          if (author != null)
            Padding(
              padding: EdgeInsets.fromLTRB(width * 0.18, 0, width * 0.1, height * 0.06),
              child: Text(
                author!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.goldSoft.withValues(alpha: 0.85),
                  fontSize: width * 0.15,
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
