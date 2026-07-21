import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// One row in the option-picker sheet. [value] is null only for a "not set"
/// entry (Language), which renders subdued.
class SelectOption {
  const SelectOption(this.value, this.label, {this.subdued = false});
  final String? value;
  final String label;
  final bool subdued;
}

class _SelectResult {
  const _SelectResult(this.value);
  final String? value;
}

/// The shared look for every "tap to choose" field on a form (Format,
/// Language, and the publisher picker's cousin): a labelled box, matching the
/// text fields' height, with a chevron — never the raw Material dropdown.
class SelectField extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.displayValue,
    required this.isPlaceholder,
    required this.onTap,
    this.note,
    this.labelStyle,
  });

  final String label;
  final String displayValue;
  final bool isPlaceholder;
  final VoidCallback onTap;
  final String? note;

  /// Override so a host form's label row stays uniform (the stub sheet's
  /// TITLE/YEAR labels differ slightly from the add-form's).
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: labelStyle ??
              TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w600,
              ),
        ),
        SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            // vertical: 10 matches the form's dense TextFormField height, so a
            // select aligns with the text field beside it (Format↔ISBN,
            // Language↔Pages) — the dropdown-height gripe.
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isPlaceholder ? AppColors.inkSoft : AppColors.ink,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 18, color: AppColors.inkSoft),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          SizedBox(height: 4),
          Text(note!, style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.3)),
        ],
      ],
    );
  }
}

/// Opens the Reading Room option-picker sheet. Fires [onChanged] only when the
/// user actually picks something; a dismiss (scrim tap / swipe down) leaves the
/// value untouched — which is how "not set" (a real null pick) stays distinct
/// from cancelling. Long lists (the ~40-language pick-list) get a type-to-filter
/// field at the top; short ones (Format) stay a plain tap-list.
Future<void> openSelectSheet(
  BuildContext context, {
  required String title,
  required List<SelectOption> options,
  required String? current,
  required ValueChanged<String?> onChanged,
}) async {
  final result = await showModalBottomSheet<_SelectResult>(
    context: context,
    backgroundColor: AppColors.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _SelectSheet(title: title, options: options, current: current),
  );
  if (result != null) onChanged(result.value);
}

/// Filtering above this many options is faster than scrolling; below it a
/// search box is just clutter.
const _kSearchThreshold = 12;

class _SelectSheet extends StatefulWidget {
  const _SelectSheet({required this.title, required this.options, required this.current});

  final String title;
  final List<SelectOption> options;
  final String? current;

  @override
  State<_SelectSheet> createState() => _SelectSheetState();
}

class _SelectSheetState extends State<_SelectSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searchable = widget.options.length > _kSearchThreshold;
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? widget.options
        : [
            for (final opt in widget.options)
              if (opt.label.toLowerCase().contains(query)) opt,
          ];

    return SafeArea(
      child: Padding(
        // Keep the filtered list above the keyboard while typing.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            if (searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: l10n.pickerSearchHint,
                    hintStyle: TextStyle(fontSize: 14, color: AppColors.inkSoft),
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in visible)
                    ListTile(
                      dense: true,
                      title: Text(
                        opt.label,
                        style: TextStyle(
                          color: opt.subdued ? AppColors.inkSoft : AppColors.ink,
                          fontWeight:
                              opt.value == widget.current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      trailing: opt.value == widget.current
                          ? Icon(Icons.check, size: 18, color: AppColors.oxblood)
                          : null,
                      onTap: () => Navigator.of(context).pop(_SelectResult(opt.value)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
