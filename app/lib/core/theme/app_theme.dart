import 'package:flutter/material.dart';

/// Kitabi design tokens — seeded from the landing page palette.
/// Replace with the real design system once screen mockups exist
/// (CLAUDE.md open decision).
abstract final class AppColors {
  static const ink = Color(0xFF050724); // deep navy
  static const gold = Color(0xFFE8B84D);
  static const teal = Color(0xFF2DD4BF);
  static const text = Color(0xFFEDEEF6);
  static const dim = Color(0xFFA0A5C0);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.gold,
    brightness: Brightness.dark,
    surface: AppColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ink,
  );
}
