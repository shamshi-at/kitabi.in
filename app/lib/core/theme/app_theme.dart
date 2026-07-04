import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kitabi design tokens — "The Reading Room". Source of truth:
/// docs/screen-design.md and docs/kitabi_screens.html.
abstract final class AppColors {
  static const paper = Color(0xFFF6F0E3);
  static const paperDeep = Color(0xFFEFE6D2);
  static const card = Color(0xFFFFFCF4);
  static const ink = Color(0xFF2B2118);
  static const inkSoft = Color(0xFF7A6A55);
  static const line = Color(0xFFE2D6BD);
  static const oxblood = Color(0xFF7E2A33);
  static const oxbloodDeep = Color(0xFF5E1F26);
  static const gold = Color(0xFFB8862B);
  static const goldSoft = Color(0xFFF0E2C2);
  static const moss = Color(0xFF48663F);
  static const slate = Color(0xFF43617E);
  static const stampGrey = Color(0xFF9A8F7C);
  static const night = Color(0xFF241811);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.oxblood,
    brightness: Brightness.light,
    surface: AppColors.paper,
    primary: AppColors.oxblood,
    secondary: AppColors.gold,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.paper,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.fraunces(textStyle: base.textTheme.displayLarge),
      displayMedium: GoogleFonts.fraunces(textStyle: base.textTheme.displayMedium),
      displaySmall: GoogleFonts.fraunces(textStyle: base.textTheme.displaySmall),
      headlineLarge: GoogleFonts.fraunces(textStyle: base.textTheme.headlineLarge),
      headlineMedium: GoogleFonts.fraunces(textStyle: base.textTheme.headlineMedium),
      headlineSmall: GoogleFonts.fraunces(textStyle: base.textTheme.headlineSmall),
      titleLarge: GoogleFonts.fraunces(textStyle: base.textTheme.titleLarge),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.oxblood,
        foregroundColor: AppColors.paper,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.ink),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// The one intentionally dark surface (ISBN scanner is a camera view) —
/// built locally by that screen, not part of the global theme.
ThemeData buildNightOverlayTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.night,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.gold,
        brightness: Brightness.dark,
        surface: AppColors.night,
      ),
    );
