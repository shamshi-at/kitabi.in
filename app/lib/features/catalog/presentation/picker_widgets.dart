import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Languages offered in the author/publisher "primary language" dropdown —
/// Indian languages first (Kitabi's regional wedge), then the wider set most
/// likely to matter. Free-typing a language was error-prone and produced
/// near-duplicate catalog values ("Malayalam" vs "malayalam"); a fixed list
/// keeps them clean.
const kCatalogLanguages = <String>[
  'English',
  'Malayalam',
  'Hindi',
  'Tamil',
  'Telugu',
  'Kannada',
  'Bengali',
  'Marathi',
  'Gujarati',
  'Punjabi',
  'Urdu',
  'Odia',
  'Assamese',
  'Sanskrit',
  'Arabic',
  'French',
  'Spanish',
  'German',
  'Portuguese',
  'Russian',
  'Japanese',
  'Chinese',
  'Other',
];

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

/// Optional language dropdown for the picker add-new forms — replaces the old
/// free-text language field so values stay canonical ([kCatalogLanguages]).
class PickerLanguageDropdown extends StatelessWidget {
  const PickerLanguageDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final String hint;
  final ValueChanged<String?> onChanged;

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isExpanded: true,
              hint: Text(hint, style: TextStyle(fontSize: 14, color: AppColors.inkSoft)),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(hint, style: TextStyle(color: AppColors.inkSoft)),
                ),
                for (final lang in kCatalogLanguages)
                  DropdownMenuItem<String?>(value: lang, child: Text(lang)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Photo picker used on the author/publisher add-new forms — shows a circular
/// preview of the chosen/uploaded image (or a placeholder) with a button to
/// pick or replace it, so users upload a real photo instead of pasting a URL.
class PickerImageField extends StatelessWidget {
  const PickerImageField({
    super.key,
    required this.label,
    required this.imageUrl,
    required this.busy,
    required this.pickLabel,
    required this.onPick,
    this.onClear,
    this.circular = true,
  });

  final String label;
  final String? imageUrl;
  final bool busy;
  final String pickLabel;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final radius = BorderRadius.circular(circular ? 28 : 10);
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
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: radius,
                border: Border.all(color: AppColors.line),
                image: hasImage
                    ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (hasImage
                      ? null
                      : Icon(Icons.image_outlined, color: AppColors.inkSoft, size: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.photo_camera_back_outlined, size: 18),
                label: Text(pickLabel),
              ),
            ),
            if (hasImage && onClear != null)
              IconButton(
                onPressed: busy ? null : onClear,
                icon: Icon(Icons.close, size: 18, color: AppColors.inkSoft),
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              ),
          ],
        ),
      ],
    );
  }
}
