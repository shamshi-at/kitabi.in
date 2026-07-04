import 'package:flutter/material.dart';

/// The 5 reading states (S6 status picker / S5 status pills) — exact
/// values and colors from docs/kitabi_screens.html, not free text.
const readingStatuses = ['pending', 'reading', 'read', 'stopped', 'wishlist'];

String readingStatusLabel(String status) => switch (status) {
      'reading' => 'Reading',
      'read' => 'Read',
      'stopped' => 'Stopped',
      'wishlist' => 'Wishlist',
      _ => 'Pending',
    };

Color readingStatusBackground(String status) => switch (status) {
      'reading' => const Color(0xFFF2DEDA),
      'read' => const Color(0xFFE3EAD9),
      'wishlist' => const Color(0xFFDEE7EF),
      _ => const Color(0xFFEAE4D6),
    };

Color readingStatusForeground(String status) => switch (status) {
      'reading' => const Color(0xFF7E2A33),
      'read' => const Color(0xFF48663F),
      'stopped' => const Color(0xFF8A7F6C),
      'wishlist' => const Color(0xFF43617E),
      _ => const Color(0xFF7A6A55),
    };
