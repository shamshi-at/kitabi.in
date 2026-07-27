import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The little grab-handle at the top of a modal sheet — the one shared
/// implementation (moved out of the lending sheets, 28 Jul 2026, replacing
/// four hand-rolled copies across the share and lending sheets).
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
