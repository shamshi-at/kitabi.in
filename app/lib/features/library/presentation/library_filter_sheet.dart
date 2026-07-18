import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../reading_status.dart';

/// The set of active library-grid filters (S4b). Empty sets mean "no filter".
class LibraryFilter {
  const LibraryFilter({
    this.statuses = const {},
    this.languages = const {},
    this.forms = const {},
    this.genres = const {},
    this.favouritesOnly = false,
    this.shelf,
  });

  final Set<String> statuses;
  final Set<String> languages;

  /// Literary forms ("Type": Novel, Short stories, Poetry…) — the Work-level
  /// single-valued axis, filtered offline from the cached-book mirror.
  final Set<String> forms;
  final Set<String> genres;
  final bool favouritesOnly;

  /// One personal shelf (tag id) to walk — single-select, like standing at
  /// one shelf of a real bookcase. Composes with every other facet
  /// ("Favourites shelf, Malayalam, unread"). The built-in shelves (Reading,
  /// Read…) aren't values here: they map onto [statuses]/[favouritesOnly],
  /// so the filter sheet's own controls already show them selected.
  final String? shelf;

  int get activeCount =>
      statuses.length +
      languages.length +
      forms.length +
      genres.length +
      (favouritesOnly ? 1 : 0) +
      (shelf != null ? 1 : 0);

  /// [shelvesOf] is entryId → tag ids (entryShelvesProvider's map); only
  /// consulted when a [shelf] is set, so every other caller can omit it.
  bool matches(LibraryHit hit, {Map<String, Set<String>> shelvesOf = const {}}) {
    if (statuses.isNotEmpty && !statuses.contains(hit.entry.status)) return false;
    if (languages.isNotEmpty) {
      final lang = hit.book.language;
      if (lang == null || !languages.contains(lang)) return false;
    }
    if (forms.isNotEmpty) {
      final form = hit.book.form;
      if (form == null || !forms.contains(form)) return false;
    }
    if (genres.isNotEmpty && _genresOf(hit).intersection(genres).isEmpty) return false;
    if (favouritesOnly && !hit.entry.isFavorite) return false;
    if (shelf != null && !(shelvesOf[hit.entry.id]?.contains(shelf) ?? false)) return false;
    return true;
  }

  static Set<String> _genresOf(LibraryHit hit) => (hit.book.genreNames ?? '')
      .split(',')
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet();
}

Future<LibraryFilter?> showLibraryFilterSheet(
  BuildContext context, {
  required List<LibraryHit> hits,
  required LibraryFilter current,
  List<PersonalTag> shelves = const [],
  Map<String, Set<String>> shelvesOf = const {},
}) {
  return showModalBottomSheet<LibraryFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _FilterSheet(hits: hits, current: current, shelves: shelves, shelvesOf: shelvesOf),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.hits,
    required this.current,
    required this.shelves,
    required this.shelvesOf,
  });

  final List<LibraryHit> hits;
  final LibraryFilter current;

  /// The reader's personal shelves, for the single-select Shelf row.
  final List<PersonalTag> shelves;

  /// entryId → tag ids, so the live count respects a picked shelf.
  final Map<String, Set<String>> shelvesOf;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _statuses = {...widget.current.statuses};
  late Set<String> _languages = {...widget.current.languages};
  late Set<String> _forms = {...widget.current.forms};
  late Set<String> _genres = {...widget.current.genres};
  late bool _favouritesOnly = widget.current.favouritesOnly;
  late String? _shelf = widget.current.shelf;

  LibraryFilter get _working => LibraryFilter(
        statuses: _statuses,
        languages: _languages,
        forms: _forms,
        genres: _genres,
        favouritesOnly: _favouritesOnly,
        shelf: _shelf,
      );

  List<String> get _availableLanguages {
    final set = <String>{};
    for (final h in widget.hits) {
      final lang = h.book.language;
      if (lang != null && lang.trim().isNotEmpty) set.add(lang);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _availableForms {
    final set = <String>{};
    for (final h in widget.hits) {
      final form = h.book.form;
      if (form != null && form.trim().isNotEmpty) set.add(form);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _availableGenres {
    final set = <String>{};
    for (final h in widget.hits) {
      for (final g in (h.book.genreNames ?? '').split(',')) {
        if (g.trim().isNotEmpty) set.add(g.trim());
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  void _toggle(Set<String> set, String value) {
    setState(() => set.contains(value) ? set.remove(value) : set.add(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count =
        widget.hits.where((h) => _working.matches(h, shelvesOf: widget.shelvesOf)).length;
    final languages = _availableLanguages;
    final forms = _availableForms;
    final genres = _availableGenres;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.libraryFilterTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (_working.activeCount > 0)
                  TextButton(
                    onPressed: () => setState(() {
                      _statuses = {};
                      _languages = {};
                      _forms = {};
                      _genres = {};
                      _favouritesOnly = false;
                      _shelf = null;
                    }),
                    child: Text(l10n.libraryFilterClear),
                  ),
              ],
            ),
            SizedBox(height: 8),
            _Label(l10n.libraryFilterStatus),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final status in readingStatuses)
                  _Chip(
                    label: readingStatusLabel(status),
                    selected: _statuses.contains(status),
                    onTap: () => _toggle(_statuses, status),
                  ),
              ],
            ),
            if (languages.isNotEmpty) ...[
              SizedBox(height: 14),
              _Label(l10n.libraryFilterLanguage),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final lang in languages)
                    _Chip(
                      label: lang,
                      selected: _languages.contains(lang),
                      onTap: () => _toggle(_languages, lang),
                    ),
                ],
              ),
            ],
            if (widget.shelves.isNotEmpty) ...[
              SizedBox(height: 14),
              _Label(l10n.libraryFilterShelf),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final shelf in widget.shelves)
                    _Chip(
                      label: shelf.name,
                      selected: _shelf == shelf.id,
                      // Single-select: you stand at one shelf at a time.
                      // Tapping the selected one steps away from it again.
                      onTap: () =>
                          setState(() => _shelf = _shelf == shelf.id ? null : shelf.id),
                    ),
                ],
              ),
            ],
            if (forms.isNotEmpty) ...[
              SizedBox(height: 14),
              _Label(l10n.libraryFilterType),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final form in forms)
                    _Chip(
                      label: form,
                      selected: _forms.contains(form),
                      onTap: () => _toggle(_forms, form),
                    ),
                ],
              ),
            ],
            if (genres.isNotEmpty) ...[
              SizedBox(height: 14),
              _Label(l10n.libraryFilterGenre),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final genre in genres)
                    _Chip(
                      label: genre,
                      selected: _genres.contains(genre),
                      onTap: () => _toggle(_genres, genre),
                    ),
                ],
              ),
            ],
            SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.libraryFilterFavouritesOnly),
              value: _favouritesOnly,
              activeThumbColor: AppColors.gold,
              onChanged: (v) => setState(() => _favouritesOnly = v),
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_working),
                child: Text(l10n.libraryFilterShow(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1,
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w700,
        ),
      ),
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
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.oxblood : AppColors.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.oxblood : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.paper : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
