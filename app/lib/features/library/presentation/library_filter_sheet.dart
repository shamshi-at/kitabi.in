import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/reading_pace.dart';
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
    this.finish,
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

  /// One time-to-finish bucket, single-select — "what can I actually get
  /// through?" is a question with one answer at a time (Area 13, P4). Needs
  /// the reader's pace to evaluate, so [matches] takes one.
  final FinishBucket? finish;

  int get activeCount =>
      statuses.length +
      languages.length +
      forms.length +
      genres.length +
      (favouritesOnly ? 1 : 0) +
      (shelf != null ? 1 : 0) +
      (finish != null ? 1 : 0);

  /// [shelvesOf] is entryId → tag ids (entryShelvesProvider's map); only
  /// consulted when a [shelf] is set, so every other caller can omit it.
  /// [pace] is only consulted when a [finish] bucket is set; without one the
  /// time facet can't be evaluated and nothing matches it, rather than the
  /// filter silently behaving as though it weren't there.
  bool matches(
    LibraryHit hit, {
    Map<String, Set<String>> shelvesOf = const {},
    ReadingPace? pace,
  }) {
    if (finish != null) {
      // A book you've finished has nothing left to finish. It would otherwise
      // estimate at zero seconds and turn up first in "under 3h", which reads
      // as the shelf offering you a book you've already read.
      if (hit.entry.status == 'read') return false;
      if (pace == null || !finish!.contains(estimateSecondsFor(hit, pace))) return false;
    }
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

  /// This filter with the time facet dropped — what "would match if we could
  /// estimate it" means, and therefore what the excluded count is counted
  /// against (P4's "6 books have no page count").
  LibraryFilter get withoutFinish => LibraryFilter(
        statuses: statuses,
        languages: languages,
        forms: forms,
        genres: genres,
        favouritesOnly: favouritesOnly,
        shelf: shelf,
      );

  static Set<String> _genresOf(LibraryHit hit) => (hit.book.genreNames ?? '')
      .split(',')
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toSet();
}

/// Seconds of reading left in a book at the reader's pace, or null when the
/// edition has no page count — the one input that can actually be missing.
int? estimateSecondsFor(LibraryHit hit, ReadingPace pace) => estimateFinish(
      pageCount: hit.book.pageCount,
      pace: pace,
      currentPage: hit.entry.currentPage,
      language: hit.book.language,
    )?.remainingSeconds;

/// How many books the time filter had to leave out because nobody has told the
/// catalogue how long they are. Shown, never swallowed: a silently shorter
/// shelf reads as "that's all you have".
int unestimatableCount(
  List<LibraryHit> hits,
  LibraryFilter filter, {
  required ReadingPace pace,
  Map<String, Set<String>> shelvesOf = const {},
}) {
  if (filter.finish == null) return 0;
  final others = filter.withoutFinish;
  return hits
      .where((h) =>
          // Finished books aren't "excluded for lack of a page count" — they
          // aren't candidates at all, so counting them here would overstate
          // what the reader is missing.
          h.entry.status != 'read' &&
          others.matches(h, shelvesOf: shelvesOf) &&
          estimateSecondsFor(h, pace) == null)
      .length;
}

/// One time-to-finish bucket. Bounds are in seconds; either end may be open.
class FinishBucket {
  const FinishBucket({this.minSeconds, this.maxSeconds});

  final int? minSeconds;
  final int? maxSeconds;

  bool contains(int? seconds) {
    if (seconds == null) return false; // no page count → not estimable
    if (minSeconds != null && seconds < minSeconds!) return false;
    if (maxSeconds != null && seconds > maxSeconds!) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is FinishBucket &&
      other.minSeconds == minSeconds &&
      other.maxSeconds == maxSeconds;

  @override
  int get hashCode => Object.hash(minSeconds, maxSeconds);
}

const _hour = 3600;

/// The buckets themselves — hours a reader can picture (an evening, a weekend,
/// a holiday, a project).
const finishBuckets = <({FinishBucket bucket, int? from, int? to})>[
  (bucket: FinishBucket(maxSeconds: 3 * _hour), from: null, to: 3),
  (bucket: FinishBucket(minSeconds: 3 * _hour, maxSeconds: 8 * _hour), from: 3, to: 8),
  (bucket: FinishBucket(minSeconds: 8 * _hour, maxSeconds: 15 * _hour), from: 8, to: 15),
  (bucket: FinishBucket(minSeconds: 15 * _hour), from: 15, to: null),
];

String finishBucketLabel(AppLocalizations l10n, ({FinishBucket bucket, int? from, int? to}) b) {
  if (b.from == null) return l10n.paceFilterUnder(b.to!);
  if (b.to == null) return l10n.paceFilterOver(b.from!);
  return l10n.paceFilterRange(b.from!, b.to!);
}

Future<LibraryFilter?> showLibraryFilterSheet(
  BuildContext context, {
  required List<LibraryHit> hits,
  required LibraryFilter current,
  required ReadingPace pace,
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
    builder: (_) => _FilterSheet(
      hits: hits,
      current: current,
      pace: pace,
      shelves: shelves,
      shelvesOf: shelvesOf,
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.hits,
    required this.current,
    required this.pace,
    required this.shelves,
    required this.shelvesOf,
  });

  final List<LibraryHit> hits;
  final LibraryFilter current;

  /// The reader's pace, resolved by the grid — the time facet is meaningless
  /// without it, and it must be the same figure the book pages quote.
  final ReadingPace pace;

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
  late FinishBucket? _finish = widget.current.finish;

  LibraryFilter get _working => LibraryFilter(
        statuses: _statuses,
        languages: _languages,
        forms: _forms,
        genres: _genres,
        favouritesOnly: _favouritesOnly,
        shelf: _shelf,
        finish: _finish,
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
    final count = widget.hits
        .where((h) =>
            _working.matches(h, shelvesOf: widget.shelvesOf, pace: widget.pace))
        .length;
    final excluded = unestimatableCount(
      widget.hits,
      _working,
      pace: widget.pace,
      shelvesOf: widget.shelvesOf,
    );
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
                      _finish = null;
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
            // Time to finish (P4). Sits last among the chip rows because it's
            // the one facet that depends on the reader rather than the book.
            SizedBox(height: 14),
            _Label('◷ ${l10n.paceFilterLabel}'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip(
                  label: l10n.paceFilterAny,
                  selected: _finish == null,
                  onTap: () => setState(() => _finish = null),
                ),
                for (final b in finishBuckets)
                  _Chip(
                    label: finishBucketLabel(l10n, b),
                    selected: _finish == b.bucket,
                    // Single-select: tapping the chosen bucket steps back to Any.
                    onTap: () =>
                        setState(() => _finish = _finish == b.bucket ? null : b.bucket),
                  ),
              ],
            ),
            // Two honesty lines, only when they're true: whose pace this is,
            // and how many books the facet had to leave out.
            if (_finish != null && !widget.pace.isMeasured)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  l10n.paceFilterAssumedNote,
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.4),
                ),
              ),
            if (excluded > 0)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  l10n.paceFilterExcluded(excluded),
                  style: TextStyle(fontSize: 10.5, color: AppColors.stampGrey, height: 1.4),
                ),
              ),
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
