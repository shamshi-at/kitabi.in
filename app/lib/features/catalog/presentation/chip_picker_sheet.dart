import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';

/// One option in a [ChipPickerSheet] — a value, and optionally how many books
/// in the catalogue already carry it.
class PickerOption {
  const PickerOption(this.name, {this.count});

  final String name;

  /// Books carrying this value. Null hides the count (a closed vocabulary like
  /// Type has no duplicate problem to solve, so the number would be noise).
  final int? count;
}

/// M11 — the searchable sheet behind Type and Genre's "All N" door. The chip
/// rows on the add form are a *shortcut* to a handful of values; this holds
/// the whole vocabulary, so the rows never grow with the catalogue.
///
/// Its second job is duplicate pressure. Genres are free text with no
/// case-folding on write (Type has `normalize_form`; genre doesn't), so three
/// spellings of one genre fragment the shared library filter forever. Showing
/// what already exists — with its book count — is what stops "Sci-fi" being
/// born next to "Science fiction · 128". Creating a new value stays possible
/// but is the dashed last resort, and says out loud that it's shared.
///
/// Returns the chosen set via [Navigator.pop]; null if dismissed.
class ChipPickerSheet extends StatefulWidget {
  const ChipPickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    this.multiSelect = true,
    this.allowCreate = false,
    this.createSharedNote,
  });

  final String title;
  final List<PickerOption> options;
  final Set<String> selected;

  /// Genre is multi-select; Type is one-of, and closes as soon as you pick.
  final bool multiSelect;

  /// Whether a value outside the list can be created from the search text.
  /// False for closed vocabularies (Type), true for genres.
  final bool allowCreate;

  /// The line under "Create X" spelling out that the new value is shared.
  final String? createSharedNote;

  @override
  State<ChipPickerSheet> createState() => _ChipPickerSheetState();
}

class _ChipPickerSheetState extends State<ChipPickerSheet> {
  final _search = TextEditingController();
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PickerOption> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final option in widget.options)
        if (option.name.toLowerCase().contains(q)) option,
    ];
  }

  /// Offer to create only when the typed text isn't already an option —
  /// case-insensitively, or the sheet would invite the exact duplicate it
  /// exists to prevent.
  bool get _canCreate {
    if (!widget.allowCreate) return false;
    final q = _query.trim();
    if (q.isEmpty) return false;
    return !widget.options.any((o) => o.name.toLowerCase() == q.toLowerCase());
  }

  void _toggle(String name) {
    if (!widget.multiSelect) {
      Navigator.of(context).pop({name});
      return;
    }
    setState(() {
      if (!_selected.remove(name)) _selected.add(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final matches = _matches;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.multiSelect
                        ? l10n.pickerGenreSubtitle(widget.options.length)
                        : l10n.pickerTypeSubtitle(widget.options.length),
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    textCapitalization: TextCapitalization.words,
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.pickerSearchHint,
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  if (matches.isNotEmpty) ...[
                    Text(
                      l10n.pickerAlreadyHere.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, option) in matches.indexed)
                            _OptionRow(
                              option: option,
                              selected: _selected.contains(option.name),
                              multiSelect: widget.multiSelect,
                              divided: i > 0,
                              onTap: () => _toggle(option.name),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_canCreate) ...[
                    const SizedBox(height: 12),
                    _CreateRow(
                      value: _search.text.trim(),
                      note: widget.createSharedNote,
                      onTap: () => Navigator.of(context).pop(
                        widget.multiSelect
                            ? {..._selected, _search.text.trim()}
                            : {_search.text.trim()},
                      ),
                    ),
                  ],
                  if (matches.isEmpty && !_canCreate)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        l10n.pickerNoMatches,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.multiSelect)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.oxblood,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(l10n.pickerDone(_selected.length)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.multiSelect,
    required this.divided,
    required this.onTap,
  });

  final PickerOption option;
  final bool selected;
  final bool multiSelect;
  final bool divided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          border: divided ? Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        child: Row(
          children: [
            if (multiSelect)
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? AppColors.oxblood : null,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: selected ? AppColors.oxblood : AppColors.line,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 13, color: AppColors.paper)
                    : null,
              )
            else
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.oxblood : AppColors.line,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (option.count != null)
              Text(
                l10n.pickerBookCount(option.count!),
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}

/// The dashed last resort. Deliberately quieter than the matches above it and
/// explicit that a new genre joins the shared filter for every reader.
class _CreateRow extends StatelessWidget {
  const _CreateRow({required this.value, required this.note, required this.onTap});

  final String value;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD8C9A8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.pickerCreate(value),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 3),
              Text(
                note!,
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
