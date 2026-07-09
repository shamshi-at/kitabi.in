import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'status_pill.dart';
import 'typeset_cover.dart';

/// The "pure shelf" book card (Grid B, docs/screen-design.md) — a cover that
/// fills its cell with every piece of state layered *on the cover* as an
/// overlay, no caption plate below. One component for every shelf: the library
/// grid, the borrowed section, a public profile's shelf, the home strip. Same
/// overlay means the same thing wherever a book appears.
///
/// Overlays (any combination):
/// - [status] → a solid tinted pill, bottom-left, lifted off the cover.
/// - [progress] (0..1) → an oxblood reading sliver along the very bottom.
/// - [favorite] → a gold ribbon bookmark, top-right corner.
/// - [lentToName] → a gold "WITH `NAME`" band across the bottom.
/// - [borrowedFromName] → a slate "FROM `NAME`" band across the bottom.
///
/// A band (lent/borrowed) owns the bottom strip, so the status pill hides when
/// one is present — the band already carries the headline for that book.
class ShelfCover extends StatelessWidget {
  const ShelfCover({
    super.key,
    required this.title,
    this.author,
    this.coverUrl,
    this.status,
    this.progress,
    this.favorite = false,
    this.lentToName,
    this.borrowedFromName,
  });

  final String title;
  final String? author;
  final String? coverUrl;
  final String? status;
  final double? progress;
  final bool favorite;
  final String? lentToName;
  final String? borrowedFromName;

  @override
  Widget build(BuildContext context) {
    final band = lentToName ?? borrowedFromName;
    final bandColor = lentToName != null ? const Color(0xEBB8862B) : const Color(0xEB43617E);
    final bandTextColor = lentToName != null ? const Color(0xFF241811) : AppColors.paper;

    return Stack(
      fit: StackFit.expand,
      children: [
        TypesetCover(
          title: title,
          author: author,
          coverUrl: coverUrl,
          width: double.infinity,
          height: double.infinity,
        ),
        // Reading sliver — hidden under a band if one is showing.
        if (progress != null && progress! > 0 && band == null)
          Align(
            alignment: Alignment.bottomLeft,
            child: FractionallySizedBox(
              widthFactor: progress!.clamp(0.0, 1.0),
              child: Container(height: 3, color: AppColors.oxblood),
            ),
          ),
        if (favorite)
          Positioned(
            top: -2,
            right: 6,
            child: ClipPath(
              clipper: _RibbonClipper(),
              child: Container(width: 9, height: 20, color: AppColors.gold),
            ),
          ),
        if (band != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: bandColor,
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                lentToName != null
                    ? 'WITH ${lentToName!.toUpperCase()}'
                    : 'FROM ${borrowedFromName!.toUpperCase()}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bandTextColor,
                  fontSize: 6.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          )
        else if (status != null)
          Positioned(
            left: 5,
            bottom: 5,
            child: DecoratedBox(
              // A small lift so a light pill still reads over a light photo cover.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              child: StatusPill(status: status!),
            ),
          ),
      ],
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.78)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
