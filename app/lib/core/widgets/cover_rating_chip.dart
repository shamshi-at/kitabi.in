import 'package:flutter/material.dart';

/// The community star average worn on a cover — a dark scrim chip with the
/// palette's gold-on-dark, readable over any cover art in either theme, and
/// the same pair the public web's cards use. Overlay it bottom-left unless
/// something else owns that corner (the shelf's status pill does, so the
/// shelf wears it top-left). Only render it when a rating exists — an empty
/// chip would read as "rated zero", which is a different and untrue claim.
class CoverRatingChip extends StatelessWidget {
  const CoverRatingChip({super.key, required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xC7160D07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '★ ${rating.toStringAsFixed(1)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFD1A04A),
        ),
      ),
    );
  }
}
