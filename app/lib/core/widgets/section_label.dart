import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one uppercase section eyebrow — 9px-equivalent, letter-spaced, inkSoft
/// (docs/screen-design.md "Type"). Replaces the ~10 private per-screen variants
/// that had drifted between 7.5 and 11px. Casing is applied here, in code, so
/// arb strings stay sentence case for future locales.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.color,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  final String text;

  /// Override for constant-dark surfaces (pass [AppColors.onDarkSoft]) or gold
  /// accents; defaults to [AppColors.inkSoft].
  final Color? color;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: color ?? AppColors.inkSoft,
        ),
      ),
    );
  }
}
