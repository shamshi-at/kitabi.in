import 'package:flutter/material.dart';

import '../languages.dart';
import '../theme/app_theme.dart';

/// A wrap of toggleable language chips over [kLanguages] — shared by the
/// onboarding picker and the profile edit sheet.
class LanguageChips extends StatelessWidget {
  const LanguageChips({super.key, required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final lang in kLanguages)
          _Chip(label: lang, selected: selected.contains(lang), onTap: () => onToggle(lang)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.oxblood : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.oxblood : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 14, color: AppColors.paper),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.paper : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
