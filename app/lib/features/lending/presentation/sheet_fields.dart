import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shared form-field building blocks for the lend (S9) and log-borrowed (S8c)
/// bottom sheets, so the two flows stay visually identical.
InputDecoration sheetInputDecoration(String hint) => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: AppColors.paper,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
    );

class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1,
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SheetDateField extends StatelessWidget {
  const SheetDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetLabel(label),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
          ),
        ),
      ],
    );
  }
}

/// The little grab-handle at the top of a modal sheet.
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
