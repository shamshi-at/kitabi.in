import 'package:flutter/services.dart';

/// Small, consistent haptic vocabulary. A light tap for routine actions, a
/// selection click for toggles/pickers, a firmer tap to confirm something done.
abstract final class Haptics {
  static void light() => HapticFeedback.lightImpact();
  static void selection() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
}
