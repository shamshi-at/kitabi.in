import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Gold Line mark (assets/images/logo.svg) — see CLAUDE.md and
/// landing-page/logo.svg for provenance. One place to size/shape it so it
/// stays consistent across splash, sign-in, and share surfaces.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        width: size,
        height: size,
      ),
    );
  }
}
