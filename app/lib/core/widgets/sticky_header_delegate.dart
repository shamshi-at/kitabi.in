import 'package:flutter/material.dart';

/// Pins a fixed-height widget to the top of a [CustomScrollView] — no
/// shrink/expand behaviour, just "stays put" while the rest scrolls under
/// it. Used for the search bar on the library grid and a public profile's
/// shelf tab (owner request, 16 Jul 2026), so search stays reachable without
/// scrolling back up.
class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  const StickyHeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
