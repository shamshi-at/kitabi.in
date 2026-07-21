import 'package:flutter/material.dart';

/// The 5 reading states (S6 status picker / S5 status pills) — exact
/// values and colors from docs/kitabi_screens.html, not free text.
const readingStatuses = ['pending', 'reading', 'read', 'stopped', 'wishlist'];

String readingStatusLabel(String status) => switch (status) {
      'reading' => 'Reading',
      'read' => 'Read',
      'stopped' => 'Stopped',
      'wishlist' => 'Wishlist',
      _ => 'To read', // 'pending' — the mockups' "To read" shelf state
    };

Color readingStatusBackground(String status) => switch (status) {
      'reading' => Color(0xFFF2DEDA),
      'read' => Color(0xFFE3EAD9),
      'wishlist' => Color(0xFFDEE7EF),
      'stopped' => Color(0xFFEAE4D6),
      _ => Color(0xFFF2E6C4), // To read
    };

Color readingStatusForeground(String status) => switch (status) {
      'reading' => Color(0xFF7E2A33),
      'read' => Color(0xFF48663F),
      'stopped' => Color(0xFF8A7F6C),
      'wishlist' => Color(0xFF43617E),
      _ => Color(0xFF8F681E), // To read
    };

/// The mark that stands for a status — one glyph, used on the shelf tile, the
/// book page's status row, and anywhere else a status needs to be recognised
/// without reading the word (owner request, 21 Jul 2026; mockups U1/U5).
IconData readingStatusIcon(String status) => switch (status) {
      'reading' => Icons.play_arrow_rounded,
      'read' => Icons.check_rounded,
      'stopped' => Icons.pause_rounded,
      'wishlist' => Icons.bookmark_outline_rounded,
      _ => Icons.schedule_rounded, // 'pending' — to read
    };

/// The ink for that mark, matching the pill tints already in use.
Color readingStatusInk(String status) => switch (status) {
      'reading' => const Color(0xFF7E2A33),
      'read' => const Color(0xFF48663F),
      'stopped' => const Color(0xFF8A7F6C),
      'wishlist' => const Color(0xFF43617E),
      _ => const Color(0xFF8F681E),
    };
