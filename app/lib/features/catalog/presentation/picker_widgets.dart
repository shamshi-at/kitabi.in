import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Shared chrome for the author/publisher pickers (S7b) — a back-arrow header,
/// an autofocused search field, and a labelled text field for the add-new form.

class PickerHeader extends StatelessWidget {
  const PickerHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.ink),
            onPressed: () => context.pop(),
          ),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class PickerSearchField extends StatelessWidget {
  const PickerSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.paper,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.line),
            ),
          ),
        ),
      ],
    );
  }
}
