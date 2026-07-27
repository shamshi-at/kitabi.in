import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/languages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/select_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';

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
              textCapitalization: TextCapitalization.words,
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
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;

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
          textCapitalization: TextCapitalization.words,
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          keyboardType: keyboardType,
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

/// Optional language select for the picker add-new forms — the one app-wide
/// language vocabulary (core/languages.dart), the reader's own profile
/// languages first, presented in the themed select sheet rather than a raw
/// Material dropdown. Replaced the file-private `kCatalogLanguages` fork.
class PickerLanguageField extends ConsumerWidget {
  const PickerLanguageField({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SelectField(
      label: label,
      displayValue: value ?? hint,
      isPlaceholder: value == null,
      onTap: () {
        final preferred = (ref.read(meProvider).valueOrNull?['preferred_languages'] as List?)
                ?.cast<String>() ??
            const <String>[];
        final options = [
          ...languageOptions(preferred),
          if (value != null && !languageOptions(preferred).contains(value)) value!,
        ];
        openSelectSheet(
          context,
          title: l10n.pickerChoose(label.toLowerCase()),
          current: value,
          options: [
            SelectOption(null, hint, subdued: true),
            for (final lang in options) SelectOption(lang, lang),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}

/// The pickers' search-failure row — an error must never impersonate the
/// empty state, because "No matches — add a new one" under a dead network is
/// exactly how duplicates get born (Part 1 #4 of the 28 Jul UX review).
class PickerErrorRow extends StatelessWidget {
  const PickerErrorRow({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 22, color: AppColors.inkSoft),
          const SizedBox(height: 6),
          Text(
            l10n.pickerSearchFailed,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

/// A labelled checkbox row for picker add-new forms — currently just "This is
/// me" on the author picker, but plain enough to reuse rather than one-off.
class PickerCheckbox extends StatelessWidget {
  const PickerCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.note,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Optional quiet line under the label ("Checked claims are reviewed…").
  final String? note;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5, height: 1.3),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
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
                    ? DecorationImage(image: netImageProvider(imageUrl!), fit: BoxFit.cover)
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
