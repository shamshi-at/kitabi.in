import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kitabi design tokens — "The Reading Room", light and its "at night" dark
/// variant. Source of truth: docs/screen-design.md and docs/kitabi_screens.html.
///
/// The tokens are brightness-aware getters (not const) so `AppColors.paper`
/// resolves to the right value everywhere without threading a theme through.
/// [dark] is set from the active [ThemeMode] before each MaterialApp build; the
/// whole tree rebuilds on a theme change, re-reading these.
abstract final class AppColors {
  static bool dark = false;

  static Color _p(int light, int night) => Color(dark ? night : light);

  static Color get paper => _p(0xFFF6F0E3, 0xFF17120C);
  static Color get paperDeep => _p(0xFFEFE6D2, 0xFF20180F);
  static Color get card => _p(0xFFFFFCF4, 0xFF221A11);
  static Color get ink => _p(0xFF2B2118, 0xFFEDE3D0);
  static Color get inkSoft => _p(0xFF7A6A55, 0xFFA9997F);
  static Color get line => _p(0xFFE2D6BD, 0xFF3A2F20);
  static Color get oxblood => _p(0xFF7E2A33, 0xFFC06770);
  static Color get oxbloodDeep => _p(0xFF5E1F26, 0xFFA24A53);
  static Color get gold => _p(0xFFB8862B, 0xFFD1A04A);
  static Color get goldSoft => _p(0xFFF0E2C2, 0xFF3A2E17);
  static Color get moss => _p(0xFF48663F, 0xFF83A876);
  static Color get slate => _p(0xFF43617E, 0xFF7A9CC0);
  static Color get stampGrey => _p(0xFF9A8F7C, 0xFF8A8070);

  /// Darker gold ink — text on [goldSoft] fills ([gold] itself fails contrast).
  static Color get goldInk => _p(0xFF8F681E, 0xFFDDB86B);

  /// Personal-note "slip paper" and its rule — dashed private-note surfaces.
  static Color get slip => _p(0xFFF6EEDC, 0xFF261E12);
  static Color get slipLine => _p(0xFFE8DCC0, 0xFF3E3220);

  static const night = Color(0xFF241811); // the scanner overlay, always dark

  /// The single dark accent panel (AI pick, quote card, insight closers) —
  /// constant in both themes, per the token table in screen-design.md.
  static const darkPanel = Color(0xFF3A2C1E);

  /// Text/accents on constant-dark surfaces ([night], [darkPanel]). Constant on
  /// purpose: brightness-aware tokens on a constant surface is how the dark-mode
  /// cream-on-cream bugs happened.
  static const onDark = Color(0xFFEFE3C8);
  static const onDarkSoft = Color(0xFFC9B891);
  static const nightGold = Color(0xFFE3B14C);
}

/// Builds the theme for the given brightness. Sets [AppColors.dark] first so the
/// token getters (and every screen that reads them on the next rebuild) resolve
/// to the matching palette. Callers pass a single resolved theme to MaterialApp.
/// The iOS-style interactive "swipe from the left edge to go back" gesture, on
/// every platform (owner request, 19 Jul 2026: some pages had no swipe-back).
/// Android's default (ZoomPageTransitionsBuilder) has no edge-swipe at all, so
/// forcing the Cupertino builder everywhere gives every pushed route the same
/// draggable back gesture — the shell tabs (which swap, not push) are
/// unaffected.
const _swipeBackTransitions = PageTransitionsTheme(builders: {
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  TargetPlatform.android: CupertinoPageTransitionsBuilder(),
  TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
  TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
  TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
});

ThemeData buildAppTheme({bool dark = false}) {
  AppColors.dark = dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.oxblood,
    brightness: dark ? Brightness.dark : Brightness.light,
    surface: AppColors.paper,
    primary: AppColors.oxblood,
    secondary: AppColors.gold,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.paper,
    pageTransitionsTheme: _swipeBackTransitions,
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.fraunces(textStyle: base.textTheme.displayLarge),
      displayMedium: GoogleFonts.fraunces(textStyle: base.textTheme.displayMedium),
      displaySmall: GoogleFonts.fraunces(textStyle: base.textTheme.displaySmall),
      headlineLarge: GoogleFonts.fraunces(textStyle: base.textTheme.headlineLarge),
      headlineMedium: GoogleFonts.fraunces(textStyle: base.textTheme.headlineMedium),
      headlineSmall: GoogleFonts.fraunces(textStyle: base.textTheme.headlineSmall),
      titleLarge: GoogleFonts.fraunces(textStyle: base.textTheme.titleLarge),
    ),
    cardTheme: CardThemeData(
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
        foregroundColor: dark ? AppColors.ink : AppColors.paper,
        elevation: 0, // flat — the Reading Room is paper + ink, no floating shadows
        shadowColor: Colors.transparent,
        padding: EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: BorderSide(color: AppColors.ink),
        padding: EdgeInsets.symmetric(vertical: 14),
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
