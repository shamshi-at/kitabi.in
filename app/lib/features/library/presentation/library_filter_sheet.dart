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
    this.genres = const {},
    this.favouritesOnly = false,
  });

  final Set<String> statuses;
  final Set<String> languages;
  final Set<String> genres;
  final bool favouritesOnly;

  int get activeCount =>
      statuses.length + languages.length + genres.length + (favouritesOnly ? 1 : 0);

  bool matches(LibraryHit hit) {
    if (statuses.isNotEmpty && !statuses.contains(hit.entry.status)) return false;
    if (languages.isNotEmpty) {
      final lang = hit.book.language;
      if (lang == null || !languages.contains(lang)) return false;
    }
    if (genres.isNotEmpty && _genresOf(hit).intersection(genres).isEmpty) return false;
    if (favouritesOnly && !hit.entry.isFavorite) return false;
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
}) {
  return showModalBottomSheet<LibraryFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _FilterSheet(hits: hits, current: current),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.hits, required this.current});

  final List<LibraryHit> hits;
  final LibraryFilter current;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _statuses = {...widget.current.statuses};
  late Set<String> _languages = {...widget.current.languages};
  late Set<String> _genres = {...widget.current.genres};
  late bool _favouritesOnly = widget.current.favouritesOnly;

  LibraryFilter get _working => LibraryFilter(
        statuses: _statuses,
        languages: _languages,
        genres: _genres,
        favouritesOnly: _favouritesOnly,
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
    final count = widget.hits.where(_working.matches).length;
    final languages = _availableLanguages;
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
                      _genres = {};
                      _favouritesOnly = false;
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
