import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'cover_rating_chip.dart';
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
/// - [rating] → a dark "★ 4.4" chip, top-left — the community average worn on
///   the cover itself, so a reader scanning the shelf for the next read sees
///   it without opening each book (owner request, 9 Aug 2026). Same chip as
///   the public web's cards. Hidden while [returned] shows — that stamp owns
///   the top-left corner and is the rarer, more urgent message.
/// - [lentToName] → a gold "WITH `NAME`" band across the bottom.
/// - [borrowedFromName] → a slate "FROM `NAME`" band across the bottom, for
///   an *active* borrow.
/// - [returned] → a small grey "RETURNED" tag, top-left — a borrowed book
///   that's been given back but stays on the shelf (owner request, 15 Jul
///   2026): unlike an active borrow, this does NOT hide [status], since the
///   whole point is the reader can still see/change reading status on a book
///   they no longer physically hold.
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
    this.rating,
    this.lentToName,
    this.borrowedFromName,
    this.returned = false,
    this.timeTag,
  });

  final String title;
  final String? author;
  final String? coverUrl;
  final String? status;
  final double? progress;
  final bool favorite;

  /// The Work's community star average (null → no chip; absent is not zero).
  final double? rating;

  final String? lentToName;
  final String? borrowedFromName;
  final bool returned;

  /// "4h 20m" — how long this book would take the reader, shown only while a
  /// time-to-finish filter is on (Area 13, P5). Bottom-right, so it never
  /// fights the status pill (bottom-left) or the favourite ribbon (top-right).
  final String? timeTag;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        if (rating != null && !returned)
          Positioned(
            top: 5,
            left: 5,
            child: CoverRatingChip(rating: rating!),
          ),
        if (returned)
          Positioned(
            top: 5,
            left: 5,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xE0EAE4D6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.coverReturnedStamp.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.stampGrey,
                ),
              ),
            ),
          ),
        if (timeTag != null)
          Positioned(
            right: 4,
            bottom: 5,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                // Brightness-aware pair with the goldInk text below — a fixed
                // light pill would strand the dark-mode goldInk on cream.
                color: AppColors.goldSoft.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              child: Text(
                timeTag!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.goldInk,
                ),
              ),
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
                (lentToName != null
                        ? l10n.coverLentBand(lentToName!)
                        : l10n.coverBorrowedBand(borrowedFromName!))
                    .toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bandTextColor,
                  fontSize: 8.5,
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
