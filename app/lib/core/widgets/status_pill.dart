import 'package:flutter/material.dart';

import '../../features/library/reading_status.dart';

/// Solid, tinted, uppercase — the one status pill style used everywhere
/// (docs/screen-design.md's signature pattern).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: readingStatusBackground(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        readingStatusLabel(status).toUpperCase(),
        style: TextStyle(
          color: readingStatusForeground(status),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
