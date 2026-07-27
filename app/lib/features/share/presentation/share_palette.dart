import 'dart:ui';

/// Constant light-theme tokens for the rasterised share cards. The cards are a
/// brand surface — the gold-framed "aged paper" look must ship identically
/// whatever theme the app is in, and `AppColors` getters are theme-dependent,
/// so a card captured from dark mode used to rasterise as a near-black tile
/// (ux-review 2026-07-28, Part 1 #1). Values mirror `AppColors`' light column
/// in app_theme.dart.
abstract final class ShareCardPalette {
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
  static const goldInk = Color(0xFF8F681E);
}
