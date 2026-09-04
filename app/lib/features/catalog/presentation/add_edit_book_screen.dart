import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/image_crop.dart';
import '../../../core/languages.dart';
import '../../../core/quiet_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/select_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../cover_extract.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../catalog_image_upload.dart';
import '../providers/catalog_providers.dart';
import '../work_editions.dart';
import '../work_forms.dart';
import 'chip_picker_sheet.dart';
import 'edition_picker.dart';
import 'form_widgets.dart';

/// S4d — form to add a new catalog Work + first Edition, or edit an existing one:
/// title, authors, publisher, genres, and edition-level fields (ISBN, format,
/// cover). Contributions flow through the API when online (catalog is
/// server-authoritative, CLAUDE.md rule 2). Formats live in
/// [kEditionFormats] (form_widgets.dart), shared with the add-edition screen.
const _commonGenres = [
  'Fiction',
  'Non-fiction',
  'Poetry',
  'Historical',
  'Mystery',
  'Romance',
  'Fantasy',
  'Biography',
  'Science',
  'Self-help',
];

/// S7b — the manual add/edit flow. `workId == null` creates a new catalog
/// entry; otherwise this loads and edits the existing Work + its first
/// Edition (CLAUDE.md rule 17: series/ISBN/format/pages live on the
/// Edition, everything else on the Work).
class AddEditBookScreen extends ConsumerWidget {
  const AddEditBookScreen({
    super.key,
    this.workId,
    this.editionId,
    this.initialIsbn,
    this.initialTitle,
    this.initialOriginal,
    this.seed,
    this.returnCreated = false,
  });

  final String? workId;

  /// *Which* printing this edit is about.
  ///
  /// The form edits one Edition alongside the Work, and picking it with
  /// `editions.first` is the trap `work_editions.dart` exists to name: two
  /// printings differ in exactly the fields being edited here — page count,
  /// covers, format, publisher — so improving the wrong one writes a reader's
  /// 240-page reprint onto the 55-page first edition. Every caller that
  /// resolved a specific printing (a scan, a duplicate-ISBN 409) passes it;
  /// null still means "the only one, or the first" for the paths that
  /// genuinely have nothing better to go on.
  final String? editionId;

  /// A scanned-but-unmatched ISBN carried in from the scanner's not-found
  /// state, so the form starts with the number already filled.
  final String? initialIsbn;

  /// A title typed somewhere else that found nothing — carried in so the
  /// reader never retypes it (the borrow sheet's "not in the catalog?" path).
  final String? initialTitle;

  /// T6's "Add a translation": the *original* Work's summary carried in from
  /// its book page, so the form opens pre-linked (Translated-from filled,
  /// author carried over) and links the group on save.
  final Map<String, dynamic>? initialOriginal;

  /// Details already captured somewhere else — the add form's "it's this one,
  /// add what I have" fork. Applied over the loaded Work, into empty fields
  /// only. See [_BookFormState._applySeed].
  final Map<String, dynamic>? seed;

  /// Pick mode: this screen was opened to *produce a book for the caller*, so
  /// on save it pops with the created Work instead of showing the standalone
  /// "Added to the catalog" popup — the caller selects it and carries on.
  final bool returnCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workId == null) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: _BookForm(
            initialIsbn: initialIsbn,
            initialTitle: initialTitle,
            initialOriginal: initialOriginal,
            seed: seed,
            returnCreated: returnCreated,
          ),
        ),
      );
    }
    final work = ref.watch(workProvider(workId!));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: work.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(workProvider(workId!))),
          data: (body) => _BookForm(initialWork: body, seed: seed, editionId: editionId),
        ),
      ),
    );
  }
}

class _BookForm extends ConsumerStatefulWidget {
  const _BookForm({
    this.initialWork,
    this.editionId,
    this.initialIsbn,
    this.initialTitle,
    this.initialOriginal,
    this.seed,
    this.returnCreated = false,
  });

  final Map<String, dynamic>? initialWork;
  final String? editionId;
  final String? initialIsbn;
  final String? initialTitle;
  final Map<String, dynamic>? initialOriginal;
  final Map<String, dynamic>? seed;
  final bool returnCreated;

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  // The picked series row ({id, name, ...}). `_series` still holds a *name*,
  // because a series read off a scanned cover or an extracted photo arrives as
  // a string with no id — it prefills the picker rather than becoming a row.
  Map<String, dynamic>? _seriesPick;
  late final TextEditingController _series;
  late final TextEditingController _seriesNumber;
  late final TextEditingController _pages;
  late final TextEditingController _isbn;
  // Genres the reader added themselves — chips on the same row as the
  // suggestions (they used to live in a free-text field underneath).
  final List<String> _customGenreList = [];
  // Optional; null when unset. No silent default — a reader who never chose a
  // format saves none, instead of every book quietly becoming a Paperback.
  String? _format;
  // Optional; null when unset. A dropdown, not free text — so the catalog stays
  // consistent ("Malayalam", not "malayalam"/"mal"/"Malyalam").
  String? _language;
  // The literary form ("Type") — single-select from kWorkForms, or null.
  String? _form;
  // Series fields are hidden behind a toggle (most books are standalone); on by
  // default only when editing a book that already has a series.
  bool _hasSeries = false;
  // The less-essential fields (series, publisher, ISBN, pages, format,
  // description) fold into a "More details" section — collapsed on a fresh
  // create, open when editing or when a scan/photo-read prefilled them.
  bool _detailsExpanded = false;

  /// "Create another" has to *look* like a fresh form, not a cleared one: the
  /// reader is at the bottom of a long page when the popup closes, so a wiped
  /// form left where it stood reads as nothing having happened (owner request,
  /// 4 Sep 2026). The list goes back to the top and the title takes the cursor.
  final _scroll = ScrollController();
  final _titleFocus = FocusNode();
  // What prefilled the form last ('scan' | 'photos') — drives the dismissible
  // provenance banner so prefilled data is announced, not silent.
  String? _prefillSource;
  late final Set<String> _selectedGenres;
  // Authors and publisher are chosen via the dedicated picker pages, so each
  // carries its canonical catalog id (falling back to name for legacy data).
  final List<Map<String, dynamic>> _authors = [];
  Map<String, dynamic>? _publisher;
  // "Translated from" (T1/T4): the original Work's summary once linked, and
  // the translator credits (Author rows via the same picker as authors). The
  // translator field only appears while an original is linked — that's the
  // only moment it means anything.
  Map<String, dynamic>? _original;
  final List<Map<String, dynamic>> _translators = [];
  // What the loaded Work already had (edit mode) — a post-save link call is
  // made only when the reader *newly* attached an original.
  String? _initialOriginalId;
  // The edition's front and back cover URLs — set from an ISBN scan, an existing
  // edition (edit mode), or a photo the user captures right here.
  String? _coverUrl;
  String? _backCoverUrl;
  // Snapshot at load, so on edit we only PATCH the edition for a side the user
  // actually changed — and never null an existing cover out.
  String? _initialCoverUrl;
  String? _initialBackCoverUrl;
  // The rest of the Edition as it was loaded. Everything below lives on the
  // Edition, not the Work, so `updateWork` silently ignores it — an edit only
  // lands if it's sent as an edition patch, and only what actually changed
  // should be (owner report, 17 Jul 2026: adding a page count did nothing).
  int? _initialPageCount;
  String? _initialIsbn;
  String? _initialFormat;
  String? _initialPublisherId;
  String? _initialPublisherName;
  String? _initialSeriesName;
  String? _initialSeriesId;
  int? _initialSeriesNumber;
  bool _uploadingFront = false;
  bool _uploadingBack = false;
  bool _saving = false;
  bool _scanning = false;
  bool _extracting = false;

  // The genre vocabulary behind the row (M10/M11). `_readerGenres` is the
  // reader's own, commonest first, read from their shelves; `_catalogueGenres`
  // is every genre in the catalogue with its work count. Both load in the
  // background — the row renders from the hardcoded suggestions until they
  // arrive, so the form is never blocked on a request.
  List<String> _readerGenres = const [];
  List<Map<String, dynamic>> _catalogueGenres = const [];

  // Duplicate detection (create mode only): as the title is typed, a debounced
  // trigram search quietly surfaces near-matches already in the catalog.
  List<Map<String, dynamic>> _similar = const [];
  bool _similarDismissed = false;
  // What the title was when the panel was dismissed — clearing the title or
  // typing a substantially different one re-arms the check.
  String _similarDismissedQuery = '';
  Timer? _similarDebounce;
  int _similarSeq = 0;
  // The similar row whose full Work is being fetched for the fork sheet — the
  // sheet cannot ask an honest question until the printings are in hand.
  String? _forkBusyId;

  // What this copy said where the entry already had an answer of its own.
  // Collected by [_applySeed] rather than dropped, and offered under the form.
  final List<_Carried> _carried = [];
  // The catalogue Work this form was prefilled from, if any. It is not a
  // "possible duplicate" — it is the book the reader just told us this is, so
  // offering it back under "Already in the catalogue?" was noise (owner
  // report, 13 Aug 2026: "it still shows the same book … but I am editing the
  // same one").
  /// What an in-form scan resolved: the catalogue row it filled this form
  /// from, the printing inside it, and the title to name in a question about
  /// it. Held because a scan *always* lands on a book the catalogue already
  /// has — `_applyScannedWork` says so in as many words — so saving this form
  /// as a new book is never right; see [_offerTheEntryTheScanResolved].
  String? _prefillWorkId;
  String? _prefillEditionId;
  String? _prefillWorkTitle;

  // Unsaved-changes guard: a fingerprint of the form as it was seeded, so any
  // divergence means "dirty". [_confirmedLeave] lets the post-save pops (and a
  // confirmed discard) through without re-asking.
  late String _cleanFingerprint;
  bool _confirmedLeave = false;
  bool _discardDialogOpen = false;

  /// The printing this form is editing.
  ///
  /// [_BookForm.editionId] when the caller resolved one — a scan and a
  /// duplicate-ISBN 409 both know exactly which printing they mean, and
  /// `editions.first` would quietly edit a different one (work_editions.dart;
  /// owner report, 13 Aug 2026). The fallback is for the callers that have
  /// nothing better, and for an id that no longer matches a row.
  Map<String, dynamic>? get _edition {
    final work = widget.initialWork;
    if (work == null) return null;
    final editions = editionsOf(work);
    if (editions.isEmpty) return null;
    final wanted = widget.editionId;
    if (wanted != null) {
      for (final edition in editions) {
        if (edition['id'] == wanted) return edition;
      }
    }
    return editions.first;
  }

  @override
  void initState() {
    super.initState();
    final work = widget.initialWork;
    final edition = _edition;
    final genreNames =
        (work?['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ?? <String>{};

    _authors.addAll(
      (work?['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
          const <Map<String, dynamic>>[],
    );
    _translators.addAll(
      (work?['translators'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
          const <Map<String, dynamic>>[],
    );
    // Edit mode: the Work's linked original; T6's "Add a translation": the
    // original carried in from its book page — which also seeds the author
    // (a translation shares its original's author).
    final original = (work?['original'] as Map?) ?? widget.initialOriginal;
    if (original != null) {
      _original = Map<String, dynamic>.from(original);
      _initialOriginalId = (work?['original'] as Map?)?['id'] as String?;
      if (_authors.isEmpty) {
        _authors.addAll(
          (original['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
              const <Map<String, dynamic>>[],
        );
      }
    }
    final publisher = edition?['publisher'] as Map?;
    if (publisher != null) _publisher = Map<String, dynamic>.from(publisher);
    _title = TextEditingController(text: work?['title'] as String? ?? widget.initialTitle ?? '');
    // Live cover preview (S7b): the typeset cover mirrors the title/author as
    // they're typed, so a keystroke redraws it.
    _title.addListener(_onCoverChanged);
    // Duplicate check rides the same field — but only when creating (nagging
    // about "duplicates" while editing the book itself would be noise).
    if (work == null) _title.addListener(_onTitleChangedForSimilar);
    _description = TextEditingController(text: work?['description'] as String? ?? '');
    _language = work?['language'] as String?;
    final seededSeries = (edition?['series'] as Map?)?.cast<String, dynamic>();
    _seriesPick = seededSeries;
    _series = TextEditingController(text: seededSeries?['name'] as String? ?? '');
    _hasSeries = seededSeries?['name'] != null;
    _seriesNumber = TextEditingController(text: edition?['series_number']?.toString() ?? '');
    _pages = TextEditingController(text: edition?['page_count']?.toString() ?? '');
    _isbn = TextEditingController(text: edition?['isbn'] as String? ?? widget.initialIsbn ?? '');
    _format = edition?['format'] as String?;
    _form = work?['form'] as String?;
    // Edit mode has content everywhere; a carried-in scanned ISBN lives inside
    // the details section, so it must be visible from the start too.
    _detailsExpanded = work != null || widget.initialIsbn != null;
    _coverUrl = edition?['cover_url'] as String?;
    _backCoverUrl = edition?['back_cover_url'] as String?;
    _initialCoverUrl = _coverUrl;
    _initialBackCoverUrl = _backCoverUrl;
    _initialPageCount = edition?['page_count'] as int?;
    _initialIsbn = edition?['isbn'] as String?;
    _initialFormat = edition?['format'] as String?;
    _initialPublisherId = (edition?['publisher'] as Map?)?['id'] as String?;
    _initialPublisherName = (edition?['publisher'] as Map?)?['name'] as String?;
    _initialSeriesName = seededSeries?['name'] as String?;
    _initialSeriesId = seededSeries?['id'] as String?;
    _initialSeriesNumber = edition?['series_number'] as int?;
    // A genre that isn't one of ours is the reader's own — it must come back
    // as a selected chip on edit, not vanish for being off-list.
    _selectedGenres = {...genreNames};
    _customGenreList.addAll(genreNames.where((g) => !_commonGenres.contains(g)));
    // Captured on the *other* screen, applied after the fingerprint is taken:
    // the seed is a change the reader has yet to save, so the form must open
    // dirty. Taking the fingerprint afterwards would let a back-tap drop the
    // photos without so much as a question.
    _cleanFingerprint = _fingerprint();
    _applySeed();
    _loadGenreVocabulary();
  }

  /// Fill this form's *empty* fields from details captured elsewhere (the add
  /// form's "it's this one — add what I have" fork).
  ///
  /// Empty-only, deliberately: this is the shared catalogue, and an entry that
  /// already answers a question keeps its answer. What this rescues is the
  /// common case — a stub entry with no cover, no blurb, no page count, and a
  /// reader standing there with the book and two fresh photographs of it.
  ///
  /// Empty-only used to mean *silently* empty-only, and that was the other
  /// half of the 5 Sep 2026 report: the reader's copy said one title and the
  /// entry said another (with a typo), so the captured title was dropped with
  /// no trace, and clearing the field and re-running the extraction was the
  /// only way to see it again. A value the entry already answers is now
  /// collected into [_carried] and offered instead — the catalogue still wins
  /// by default, but the reader can see what their copy said and take it in
  /// one tap.
  void _applySeed() {
    final seed = widget.seed;
    if (seed == null || seed.isEmpty) return;
    var filled = false;
    // Only an entry that already has answers can disagree with this copy;
    // in create mode the form is empty and every seeded value simply lands.
    final canDisagree = widget.initialWork != null;
    void offer(
      String label,
      String mine,
      String? theirs,
      VoidCallback apply, {
      bool photo = false,
    }) {
      if (!canDisagree || mine.trim().isEmpty || mine.trim() == (theirs ?? '').trim()) return;
      _carried.add(
        _Carried(label: label, mine: mine.trim(), theirs: theirs, apply: apply, photo: photo),
      );
    }

    void text(TextEditingController c, Object? value, {String? label}) {
      if (value == null) return;
      if (c.text.trim().isNotEmpty) {
        if (label != null) {
          final was = c.text;
          offer(label, '$value', was, () => c.text = '$value');
        }
        return;
      }
      c.text = '$value';
      filled = true;
    }

    final seededTitle = seed['title'] as String?;
    if (seededTitle != null) {
      offer('title', seededTitle, _title.text, () => _title.text = seededTitle.trim());
    }
    final seededFront = seed['cover_url'] as String?;
    if (_coverUrl == null) {
      _coverUrl = seededFront;
    } else if (seededFront != null && seededFront != _coverUrl) {
      offer('cover_front', seededFront, null, () => _coverUrl = seededFront, photo: true);
    }
    final seededBack = seed['back_cover_url'] as String?;
    if (_backCoverUrl == null) {
      _backCoverUrl = seededBack;
    } else if (seededBack != null && seededBack != _backCoverUrl) {
      offer('cover_back', seededBack, null, () => _backCoverUrl = seededBack, photo: true);
    }
    filled |= _coverUrl != _initialCoverUrl || _backCoverUrl != _initialBackCoverUrl;
    text(_description, seed['description'], label: 'description');
    text(_isbn, seed['isbn'], label: 'isbn');
    text(_pages, seed['page_count'], label: 'pages');
    final seededFormat = seed['format'] as String?;
    if (_format == null && seededFormat != null) {
      _format = seededFormat;
      filled = true;
    } else {
      offer('format', seededFormat ?? '', _format, () => _format = seededFormat);
    }
    final seededLanguage = seed['language'] as String?;
    if (_language == null && seededLanguage != null) {
      _language = seededLanguage;
      filled = true;
    } else {
      offer('language', seededLanguage ?? '', _language, () => _language = seededLanguage);
    }
    final seededForm = seed['form'] as String?;
    if (_form == null && seededForm != null) {
      _form = seededForm;
      filled = true;
    } else {
      offer('form', seededForm ?? '', _form, () => _form = seededForm);
    }
    final seededPublisher = seed['publisher'] as Map?;
    if (_publisher == null && seededPublisher != null) {
      _publisher = Map<String, dynamic>.from(seededPublisher);
      filled = true;
    } else if (seededPublisher != null) {
      offer(
        'publisher',
        seededPublisher['name'] as String? ?? '',
        _publisher?['name'] as String?,
        () => _publisher = Map<String, dynamic>.from(seededPublisher),
      );
    }
    final seededSeriesPick = seed['series'] as Map?;
    final seededSeriesName =
        seededSeriesPick?['name'] as String? ?? seed['series_name'] as String?;
    if (!_hasSeries) {
      if (seededSeriesName != null && seededSeriesName.isNotEmpty) {
        _seriesPick =
            seededSeriesPick == null ? null : Map<String, dynamic>.from(seededSeriesPick);
        _series.text = seededSeriesName;
        _hasSeries = true;
        text(_seriesNumber, seed['series_number']);
        filled = true;
      }
    } else if (seededSeriesName != null) {
      offer('series', seededSeriesName, _series.text, () {
        _seriesPick =
            seededSeriesPick == null ? null : Map<String, dynamic>.from(seededSeriesPick);
        _series.text = seededSeriesName;
      });
    }
    final genres = (seed['genre_names'] as List?)?.cast<String>() ?? const <String>[];
    if (_selectedGenres.isEmpty && genres.isNotEmpty) {
      _selectedGenres.addAll(genres);
      _customGenreList.addAll(genres.where((g) => !_commonGenres.contains(g)));
      filled = true;
    } else {
      // Genres are a set, not an answer — the offer adds what's missing rather
      // than replacing what the catalogue has.
      final extra = genres.where((g) => !_selectedGenres.contains(g)).toList();
      offer('genres', extra.join(', '), null, () {
        _selectedGenres.addAll(extra);
        _customGenreList.addAll(extra.where((g) => !_commonGenres.contains(g)));
      });
    }
    final authors = (seed['author_names'] as List?)?.cast<String>() ?? const <String>[];
    if (_authors.isEmpty && authors.isNotEmpty) {
      _authors.addAll([
        for (final name in authors) {'name': name},
      ]);
      filled = true;
    } else if (authors.isNotEmpty) {
      final held = [for (final a in _authors) a['name'] as String].join(', ');
      offer('authors', authors.join(', '), held, () {
        _authors
          ..clear()
          ..addAll([for (final name in authors) {'name': name}]);
      });
    }
    if (filled || _carried.isNotEmpty) {
      if (filled) _prefillSource = 'seed';
      _detailsExpanded = true;
    }
  }

  /// Everything the reader can change, joined into one comparable string —
  /// the unsaved-changes guard fires only when this diverges from the value
  /// captured right after the form was seeded.
  String _fingerprint() => [
    _title.text,
    _description.text,
    _seriesPick?['id'] as String? ?? _series.text,
    _seriesNumber.text,
    _pages.text,
    _isbn.text,
    _format ?? '',
    _language ?? '',
    _form ?? '',
    '$_hasSeries',
    (_selectedGenres.toList()..sort()).join('|'),
    [for (final a in _authors) a['name']].join('|'),
    [for (final t in _translators) t['name']].join('|'),
    _publisher?['name'] ?? '',
    _original?['id'] ?? '',
    _coverUrl ?? '',
    _backCoverUrl ?? '',
  ].join('\u0000');

  bool get _dirty => _fingerprint() != _cleanFingerprint;

  /// One exit path for the back arrow, the system back gesture and the edge
  /// swipe: leave immediately when nothing would be lost, otherwise ask.
  Future<void> _maybeLeave() async {
    if (_discardDialogOpen) return;
    if (_confirmedLeave || !_dirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    _discardDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.initialWork == null ? l10n.formDiscardTitle : l10n.formDiscardEditTitle),
        content: Text(l10n.formDiscardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.formDiscardConfirm,
              style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard == true && mounted) {
      _confirmedLeave = true;
      Navigator.of(context).pop();
    }
  }

  /// Both halves of the genre row's vocabulary, best-effort: the reader's own
  /// usage (local, offline) and the catalogue's list with counts (network).
  /// Neither blocks the form — a failure just leaves the hardcoded
  /// suggestions, which is exactly what the row showed before.
  Future<void> _loadGenreVocabulary() async {
    ref
        .read(readerGenresProvider.future)
        .then((genres) {
          if (mounted) setState(() => _readerGenres = genres);
        })
        .catchError((_) {});
    ref
        .read(catalogueGenresProvider.future)
        .then((genres) {
          if (mounted) setState(() => _catalogueGenres = genres);
        })
        .catchError((_) {});
  }

  void _onCoverChanged() {
    if (mounted) setState(() {});
  }

  /// Debounced duplicate lookup while the title is typed. Quiet by design:
  /// nothing blocks, nothing pops — matches slide in below the field and a
  /// dismiss hides them for the rest of this form.
  void _onTitleChangedForSimilar() {
    final q = _title.text.trim();
    if (_similarDismissed) {
      // A dismissal answers the question for *that* title only. Clearing the
      // field or typing a substantially different title re-arms the check —
      // unless an original is linked, which settles the question for good.
      final now = q.toLowerCase();
      final then = _similarDismissedQuery;
      final related = now.isNotEmpty && (now.contains(then) || then.contains(now));
      if (_original == null && !related) {
        _similarDismissed = false;
      } else {
        return;
      }
    }
    _similarDebounce?.cancel();
    if (q.length < 3) {
      if (_similar.isNotEmpty && mounted) setState(() => _similar = const []);
      return;
    }
    _similarDebounce = Timer(const Duration(milliseconds: 450), () => _fetchSimilar(q));
  }

  Future<void> _fetchSimilar(String q) async {
    final seq = ++_similarSeq;
    try {
      final results = await ref.read(apiClientProvider).similarWorks(q);
      // Drop stale responses (a newer keystroke started a newer lookup).
      if (!mounted || seq != _similarSeq || _title.text.trim() != q) return;
      setState(
        () => _similar = [
          for (final work in results)
            if (work['id'] != _prefillWorkId) work,
        ],
      );
    } catch (_) {
      // Best-effort suggestion — never surface an error for it.
    }
  }

  @override
  void dispose() {
    _similarDebounce?.cancel();
    _title.removeListener(_onCoverChanged);
    for (final c in [_title, _description, _series, _seriesNumber, _pages, _isbn]) {
      c.dispose();
    }
    _scroll.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _pickAuthor() => _openAuthorPicker();

  /// "Is this your book?" — jumps straight into the author picker with the
  /// add-new form already expanded and "This is me" pre-checked (owner
  /// report, 15 Jul 2026: the same flow buried two taps deep under "add a
  /// new author" wasn't discoverable). Pre-fills the search with the
  /// signed-in reader's name too, so if they've already self-linked an
  /// Author row on another book, it surfaces as a pick instead of inviting
  /// a duplicate.
  Future<void> _pickAuthorAsSelf() async {
    final fullName = ref.read(meProvider).valueOrNull?['full_name'] as String?;
    await _openAuthorPicker(
      extra: {'isMe': true, if (fullName != null && fullName.trim().isNotEmpty) 'name': fullName},
    );
  }

  Future<void> _openAuthorPicker({Object? extra}) async {
    final result = await context.push<Map<String, dynamic>>(Routes.authorPicker, extra: extra);
    if (result == null) return;
    final id = result['id'] as String?;
    final name = (result['name'] as String? ?? '').trim();
    if (name.isEmpty) return;
    // De-dupe by id when present, else by case-insensitive name.
    final already = _authors.any(
      (a) => id != null ? a['id'] == id : (a['name'] as String).toLowerCase() == name.toLowerCase(),
    );
    if (already) return;
    setState(() => _authors.add(result));
  }

  /// The Translator field (T4) — the same author picker, landing in its own
  /// list. A translator is an Author row: same pages, same typeahead, same
  /// "add new" path.
  Future<void> _pickTranslator() async {
    final result = await context.push<Map<String, dynamic>>(Routes.authorPicker);
    if (result == null) return;
    final id = result['id'] as String?;
    final name = (result['name'] as String? ?? '').trim();
    if (name.isEmpty) return;
    final already = _translators.any(
      (a) => id != null ? a['id'] == id : (a['name'] as String).toLowerCase() == name.toLowerCase(),
    );
    if (already) return;
    setState(() => _translators.add(result));
  }

  /// "Translated from" (T1) — open the original-picker (T2), carrying the
  /// form's author/type/genres as the stub seed (T3). The picked (or freshly
  /// stubbed) original lands as the gold card; on save the new Work joins its
  /// translation group.
  Future<void> _pickOriginal() async {
    final picked = await context.push<Map<String, dynamic>>(
      Routes.workPicker,
      extra: {
        'forOriginal': true,
        if (widget.initialWork != null) 'excludeWorkId': widget.initialWork!['id'] as String?,
        'seed': {
          'authors': [for (final a in _authors) Map<String, dynamic>.from(a)],
          'form': _form,
          'genre_names': _selectedGenres.toList(),
        },
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _original = picked;
      // A linked original settles the duplicate question — the similar panel
      // has nothing left to warn about.
      _similar = const [];
      _similarDismissed = true;
      if (_authors.isEmpty) {
        _authors.addAll(
          (picked['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
              const <Map<String, dynamic>>[],
        );
      }
    });
  }

  /// A save refused because the ISBN is already catalogued (409 `isbn_exists`).
  ///
  /// The title panel is a *guess* the reader may ignore; this is a fact, and it
  /// arrives at the one moment they can do nothing else about it — the server
  /// will refuse this book for as long as the number stays on it. So it is not
  /// reported as an error but offered as the door it actually is: the entry
  /// they meant, opened for editing with every cover and field they typed
  /// carried over ([_forkImproveEntry]). Staying put is the other real answer,
  /// because a mistyped digit lands here too.
  ///
  /// Returns true when it handled the failure, so the caller's snackbar — which
  /// blames the network — stays out of the way.
  Future<bool> _offerTheBookThisIsbnAlreadyNames(Object err) async {
    if (err is! DioException || err.response?.statusCode != 409) return false;
    final data = err.response?.data;
    if (data is! Map || data['code'] != 'isbn_exists') return false;
    // Only the server can name the row; without an id there is nowhere to go
    // and the plain error is the honest outcome (a soft-deleted edition still
    // holds the number, and no reader can open that).
    final workId = data['work_id'] as String?;
    if (workId == null) return false;

    await _offerExistingEntry(
      workId: workId,
      // The server resolved the printing that holds the number — improving any
      // other one would put the reader's details on the wrong copy.
      editionId: data['edition_id'] as String?,
      message: data['message'] as String? ?? '',
      stayLabel: AppLocalizations.of(context)!.formIsbnTakenStay,
    );
    // Handled either way: the reader has been told what happened in a sentence
    // that fits, so the caller's "check your connection" must not follow it.
    return true;
  }

  /// The form is holding a book the catalogue already has. Offer it.
  ///
  /// Returns true when the reader took the offer and we have navigated to that
  /// entry; false when they want to carry on with this form (or the screen went
  /// away underneath the question).
  Future<bool> _offerExistingEntry({
    required String workId,
    required String message,
    required String stayLabel,
    String? editionId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(l10n.formIsbnTakenTitle),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(stayLabel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.formIsbnTakenOpen),
          ),
        ],
      ),
    );
    if (open != true || !mounted) return false;
    _forkImproveEntry({'id': workId}, editionId: editionId);
    return true;
  }

  /// A save that would add a book the scan already found.
  ///
  /// `_applyScannedWork` states the fact plainly — "a scan resolves through the
  /// catalogue (an OpenLibrary hit is cached on the way past), so the book is
  /// always in it by the time we get here" — and acts on it by hiding the
  /// duplicate-match panel. It then let the save post a create anyway, so the
  /// one warning that would have caught the duplicate was suppressed *because*
  /// the app knew the duplicate was certain. That produced seven identical
  /// Dharmapuranams in a row, each rejected only by the ISBN's unique index
  /// (owner report, 4 Sep 2026) — and would have produced a real duplicate Work
  /// on any scanned printing that carries no ISBN.
  ///
  /// So it is asked here rather than reported afterwards: this is knowledge the
  /// form has held since the scan returned, and the reader should not have to
  /// spend a round trip to find it out. Their answer is believed — "it's a
  /// different book" clears the prefill so the question is not asked twice, and
  /// the server's 409 remains the backstop if it really is the same printing.
  ///
  /// Returns true when the save must not go on.
  Future<bool> _offerTheEntryTheScanResolved() async {
    final workId = _prefillWorkId;
    if (workId == null) return false;
    final l10n = AppLocalizations.of(context)!;
    final title = _prefillWorkTitle?.trim();
    final opened = await _offerExistingEntry(
      workId: workId,
      editionId: _prefillEditionId,
      message: title == null || title.isEmpty
          ? l10n.formScanAlreadyCataloguedUntitled
          : l10n.formScanAlreadyCatalogued(title),
      stayLabel: l10n.formIsbnTakenDifferent,
    );
    if (opened || !mounted) return true;
    setState(() {
      _prefillWorkId = null;
      _prefillEditionId = null;
      _prefillWorkTitle = null;
    });
    return false;
  }

  /// M1 — the fork. A similar-title match means one of several things, and
  /// only the reader knows which: their copy of that same book (→ shelf), that
  /// same book but the entry is thin and they have better details (→ improve
  /// it), a different printing (→ add edition), a translation (→ link as
  /// original and keep typing), the same story in another literary form — the
  /// screenplay, the play (→ its own book, prefilled), or a genuinely
  /// different book (→ dismiss the match).
  ///
  /// One of those answers is not the reader's to give, though, and the sheet
  /// used to ask it anyway. The similar panel's rows are *summaries* carrying
  /// one representative edition, so this resolves the full Work first and
  /// reads the form's ISBN against every printing on it: a number the entry
  /// does not hold means the reader is holding a printing the catalogue does
  /// not have, and "add my covers and details" is then structurally wrong —
  /// every field it carries is edition-level and would land on somebody else's
  /// row (owner report, 5 Sep 2026).
  Future<void> _openFork(Map<String, dynamic> summary) async {
    final id = summary['id'] as String;
    setState(() => _forkBusyId = id);
    // Best-effort: offline, the summary is all we have and the sheet falls
    // back to asking the way it always did.
    Map<String, dynamic>? full;
    try {
      full = await ref.read(apiClientProvider).getWork(id);
    } catch (_) {
      // Nothing to add — `standing` stays unknown below.
    }
    if (!mounted) return;
    setState(() => _forkBusyId = null);
    // An API deployed behind this app, or a body that isn't a Work, is not a
    // resolution — fall back to the summary and ask the way we always did.
    final resolved = full != null && full['id'] != null ? full : null;
    final work = resolved ?? summary;
    final verdict = resolved == null
        ? (standing: IsbnStanding.unknown, edition: null)
        : isbnStandingIn(resolved, _isbn.text);

    final choice = await showModalBottomSheet<String>(
      context: context,
      // Seven answers, a book row and sometimes a note above them do not fit a
      // half-screen sheet on a phone, and the default cap clips rather than
      // scrolls — the last option was simply unreachable (owner report,
      // 5 Sep 2026). The answers scroll inside _ForkSheet, but only once the
      // sheet is allowed past that cap. Every other sheet in this file already
      // sets this; this one was the exception.
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ForkSheet(
        work: work,
        hasCaptured: _hasCapturedDetails,
        duplicateCount: _similar.length,
        standing: verdict.standing,
        isbn: _isbn.text.trim(),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'shelf':
        await _forkAddToShelf(work, resolved: resolved != null);
      case 'improve':
        // Which printing the captured details belong to is settled, not
        // guessed: the one carrying this ISBN, or — when nothing identifies
        // one — the reader's own answer.
        var editionId = verdict.edition?['id'] as String?;
        if (editionId == null) {
          final editions = editionsOf(work);
          if (editions.length > 1) {
            final picked = await chooseEdition(context, editions);
            if (picked == null || !mounted) return;
            editionId = picked['id'] as String?;
          } else {
            editionId = editions.firstOrNull?['id'] as String?;
          }
        }
        _forkImproveEntry(work, editionId: editionId);
      case 'merge':
        await _forkMergeDuplicates(work);
      case 'form':
        await _forkDifferentForm(work, resolved: resolved != null);
      case 'edition':
        final added = await context.push<Map<String, dynamic>>(
          Routes.catalogAddEdition,
          extra: {
            'workId': work['id'] as String,
            'title': work['title'] as String?,
            // The covers and details already captured here belong to the
            // printing being described — carrying them saves photographing
            // the same book twice.
            'seed': _capturedFields(),
          },
        );
        if (added != null && mounted) {
          _confirmedLeave = true; // the new edition replaced what this form was for
          context.pushReplacement(
            Routes.bookDetailPath(work['id'] as String, added['id'] as String),
          );
        }
      case 'translation':
        setState(() {
          _original = work;
          _similar = const [];
          _similarDismissed = true;
          if (_authors.isEmpty) {
            _authors.addAll(
              (work['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
                  const <Map<String, dynamic>>[],
            );
          }
        });
      case 'different':
        setState(() {
          _similarDismissed = true;
          _similarDismissedQuery = _title.text.trim().toLowerCase();
        });
    }
  }

  /// Everything this form is holding that a *different* screen could use —
  /// the photographed covers first, then whatever was typed or read off them.
  ///
  /// The reader photographs both covers and has them read, then discovers the
  /// book is already catalogued. Every fork that leaves this screen used to
  /// drop that work on the floor (owner report, 13 Aug 2026); this is what
  /// they carry instead. Only free-text authors go — a picked author already
  /// exists on the entry or doesn't belong on it.
  /// Is there anything here a matched entry could actually gain? A cover is
  /// the usual answer, but a typed blurb, ISBN or page count counts too.
  bool get _hasCapturedDetails {
    final captured = _capturedFields();
    // A title alone is not something to carry — every entry already has one,
    // and offering "add what I have" for it would be noise.
    return captured.keys.any((k) => k != 'author_names' && k != 'title') ||
        (captured['author_names'] as List).isNotEmpty;
  }

  Map<String, dynamic> _capturedFields() {
    final pages = int.tryParse(_pages.text.trim());
    final isbn = _isbn.text.trim();
    final series = _series.text.trim();
    final description = _description.text.trim();
    final title = _title.text.trim();
    return {
      // Carried for the *offer* on the other side, never applied on its own:
      // a title is the shared catalogue's, and this copy only gets to say what
      // it reads. AddEditionScreen ignores it — a printing has no title.
      if (title.isNotEmpty) 'title': title,
      if (_coverUrl != null) 'cover_url': _coverUrl,
      if (_backCoverUrl != null) 'back_cover_url': _backCoverUrl,
      if (description.isNotEmpty) 'description': description,
      if (isbn.isNotEmpty) 'isbn': isbn,
      'page_count': ?pages,
      if (_format != null) 'format': _format,
      if (_language != null) 'language': _language,
      if (_form != null) 'form': _form,
      if (_publisher != null) 'publisher': _publisher,
      if (_hasSeries && _seriesPick != null) 'series': _seriesPick,
      if (_hasSeries && _seriesPick == null && series.isNotEmpty) 'series_name': series,
      if (_hasSeries) 'series_number': ?int.tryParse(_seriesNumber.text.trim()),
      if (_selectedGenres.isNotEmpty) 'genre_names': _selectedGenres.toList(),
      'author_names': [
        for (final a in _authors)
          if (a['id'] == null) a['name'] as String,
      ],
    };
  }

  /// The fork's "it's this one, my details are better" — open the matched
  /// entry for editing with everything captured here filled in.
  ///
  /// This is the option the sheet was missing. A reader who had just
  /// photographed both covers of a book whose catalogue entry is a bare stub
  /// had only "I own this one", which shelves the stub and throws the photos
  /// away. Seeded values land only in the entry's *empty* fields — the shared
  /// catalogue's existing answer always beats this copy's.
  ///
  /// `pushReplacement`, because this form's reason to exist is gone: the book
  /// is not being added, it is being improved, and backing into a stale
  /// half-filled add form would invite the duplicate all over again.
  /// [editionId] names the printing being improved when the caller resolved
  /// one. The similar-title fork does not — a title match says nothing about
  /// which printing — but a scan and a duplicate-ISBN 409 both do, and without
  /// it the reader's page count and covers land on `editions.first`.
  void _forkImproveEntry(Map<String, dynamic> work, {String? editionId}) {
    _confirmedLeave = true;
    context.pushReplacement(
      Routes.catalogAdd,
      extra: <String, dynamic>{
        'workId': work['id'] as String,
        'seed': _capturedFields(),
        'editionId': ?editionId,
      },
    );
  }

  /// The fork's "these are all the same book" — fold the typo'd rows together.
  ///
  /// One book typed wrong three times is three catalogue rows, and every one of
  /// them is *true*: same book, same author, a letter out of place (owner
  /// request, 4 Sep 2026). Nothing in the app could say so; only the admin
  /// console could fold them. The reader holding the book is the one who knows.
  ///
  /// The reader picks which row survives — the fullest one, usually, not the
  /// one they happened to tap — and the rest are absorbed into it: their
  /// editions, ratings and reviews move across and they are soft-deleted, never
  /// destroyed. Then the survivor opens for improving, carrying everything this
  /// form was holding, because the point was never the merge on its own.
  ///
  /// The server refuses any row another reader contributed, so a merge that
  /// comes back 403 is not a bug to hide — it names the book it would not fold.
  Future<void> _forkMergeDuplicates(Map<String, dynamic> tapped) async {
    final choice = await showModalBottomSheet<_MergeChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MergeSheet(works: _similar, initialSurvivorId: tapped['id'] as String?),
    );
    if (choice == null || !mounted || choice.absorbIds.isEmpty) return;

    setState(() => _saving = true);
    try {
      final merged = await ref
          .read(apiClientProvider)
          .mergeWorks(choice.survivorId, choice.absorbIds);
      if (!mounted) return;
      final survivor = merged['work'] as Map<String, dynamic>;
      final count = (merged['merged'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.forkMergedCount(count)),
          duration: const Duration(seconds: 4),
        ),
      );
      // Straight on to improving what survived — the merge tidied the shelf,
      // it did not put the reader's covers and page count anywhere.
      _forkImproveEntry(survivor);
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.forkMergeFailed, err);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The fork's "mine's a different form" — the screenplay of a novel, the
  /// play of a story (owner report, 13 Aug 2026: there was no way to record
  /// the Naalukett screenplay next to the Naalukett novel).
  ///
  /// It stays in this form as a *new* Work rather than becoming an edition of
  /// the matched one: rule 17 attaches ratings and reviews to the Work, and a
  /// screenplay is not the novel — different text, different page count,
  /// different thing to have an opinion about. What it does share is carried
  /// over so nothing is retyped, and then the one field that actually differs
  /// is asked for.
  Future<void> _forkDifferentForm(
    Map<String, dynamic> summary, {
    bool resolved = false,
  }) async {
    // The similar panel is a list of summaries — genres and language live on
    // the full Work. Best-effort: a failed fetch just carries less.
    Map<String, dynamic> work = summary;
    if (!resolved) {
      try {
        work = await ref.read(apiClientProvider).getWork(summary['id'] as String);
      } catch (_) {
        // Offline or a hiccup — the summary's authors are still worth carrying.
      }
    }
    if (!mounted) return;
    setState(() {
      _similar = const [];
      _similarDismissed = true;
      _similarDismissedQuery = _title.text.trim().toLowerCase();
      if (_title.text.trim().isEmpty) _title.text = work['title'] as String? ?? '';
      if (_authors.isEmpty) {
        _authors.addAll(
          (work['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
              const <Map<String, dynamic>>[],
        );
      }
      _language ??= work['language'] as String?;
      if (_selectedGenres.isEmpty) {
        final names =
            (work['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ??
            <String>{};
        _selectedGenres.addAll(names);
        _customGenreList.addAll(names.where((g) => !_commonGenres.contains(g)));
      }
      // A different literary form is a *new* Work by design (rule 17), so the
      // scanned book is no longer what this form is about — forget it, or the
      // save would offer to improve the novel the screenplay came from.
      _prefillWorkId = null;
      _prefillEditionId = null;
      _prefillWorkTitle = null;
      // The one thing that is *not* shared — ask for it rather than inherit it.
      _form = null;
      _detailsExpanded = true;
    });
    await _openTypePicker();
  }

  /// The fork's "I own this one" — same shape as the scanner's Add: cache the
  /// catalog data, create the entry (idempotent), open the book.
  ///
  /// Which printing, though, is the reader's to answer when the catalogue
  /// holds more than one: they differ in page count, and a wrong one makes
  /// every progress figure lie.
  Future<void> _forkAddToShelf(Map<String, dynamic> summary, {bool resolved = false}) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final work = resolved
          ? summary
          : await ref.read(apiClientProvider).getWork(summary['id'] as String);
      if (!mounted) return;
      final edition = await chooseEdition(context, editionsOf(work));
      if (edition == null || !mounted) return;
      final editionId = edition['id'] as String;
      final repo = await ref.read(libraryRepositoryProvider.future);
      final existing = await repo.getByEditionId(editionId);
      if (existing == null) {
        await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
        await repo.add(editionId: editionId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.forkOwnThisAdded)));
      _confirmedLeave = true; // the fork replaced this screen — nothing to guard
      context.pushReplacement(Routes.bookDetailPath(work['id'] as String, editionId));
    } catch (err) {
      if (mounted) showQuietError(context, l10n.quickAddFailed, err);
    }
  }

  // ── Type & Genre rows (M10) ───────────────────────────────────────────
  // The rows show at most [_kVisibleChips]; the picker sheet holds the rest.
  // Selected values always survive the cut, so nothing the reader has chosen
  // can hide behind the "All N" door.
  static const _kVisibleChips = 6;

  /// Every Type on offer: the closed vocabulary plus the reader's own custom
  /// value when it's off-list, so an existing custom Type never vanishes.
  List<String> get _typeOptions => [
    ...kWorkForms,
    if (_form != null && !kWorkForms.contains(_form)) _form!,
  ];

  List<String> get _visibleTypes {
    final options = _typeOptions;
    // The selected Type leads, so it's never the one hidden by the cut.
    final ordered = [?_form, ...options.where((f) => f != _form)];
    return ordered.take(_kVisibleChips).toList();
  }

  /// Every genre on offer, ordered by how useful it is to *this* reader:
  /// what they've selected here, then the genres they actually use across
  /// their shelves, then the common suggestions, then the rest of the
  /// catalogue. De-duplicated case-insensitively so "Fiction" from their
  /// library doesn't sit next to "fiction" from the catalogue.
  List<String> get _genreOptions {
    final seen = <String>{};
    final ordered = <String>[];
    void add(String genre) {
      final key = genre.toLowerCase();
      if (genre.isEmpty || !seen.add(key)) return;
      ordered.add(genre);
    }

    _selectedGenres.forEach(add);
    _customGenreList.forEach(add);
    _readerGenres.forEach(add);
    _commonGenres.forEach(add);
    for (final g in _catalogueGenres) {
      add(g['name'] as String? ?? '');
    }
    return ordered;
  }

  List<String> get _visibleGenres => _genreOptions.take(_kVisibleChips).toList();

  /// Open the full Type picker — single-select over [kWorkForms], plus a
  /// create row.
  ///
  /// The list is *suggested, not closed*: that is what the server does
  /// (`normalize_form` folds a typed value onto a known spelling instead of
  /// rejecting it) and what it was asked to do — "a reader whose book is a
  /// form we didn't think of must be able to say so". This sheet shipped with
  /// `allowCreate: false`, which quietly took that back: a reader holding the
  /// തിരക്കഥ of a novel had nowhere to put it (owner report, 13 Aug 2026). An
  /// off-list value already on the book stays pickable via [_typeOptions], so
  /// old data never vanishes either.
  Future<void> _openTypePicker() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ChipPickerSheet(
        title: AppLocalizations.of(ctx)!.pickerTypeTitle,
        options: [for (final f in _typeOptions) PickerOption(f)],
        selected: {?_form},
        multiSelect: false,
        allowCreate: true,
        createSharedNote: AppLocalizations.of(ctx)!.pickerCreateTypeNote,
      ),
    );
    if (picked == null || !mounted) return;
    final chosen = picked.isEmpty ? null : picked.first.trim().replaceAll(RegExp(r'\s+'), ' ');
    setState(() {
      if (chosen == null || chosen.isEmpty) {
        _form = null;
        return;
      }
      // Mirror the server's fold so a typed "novel" highlights the Novel chip
      // immediately instead of waiting for a round-trip to say it was really
      // "Novel" all along.
      _form = kWorkForms.firstWhere(
        (f) => f.toLowerCase() == chosen.toLowerCase(),
        orElse: () => chosen,
      );
    });
  }

  /// Open the full Genre picker — multi-select over the whole catalogue with
  /// book counts, because genres get no case-folding on write and this sheet
  /// is the only thing preventing three spellings of one genre (M11).
  Future<void> _openGenrePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final counts = {
      for (final g in _catalogueGenres) (g['name'] as String? ?? ''): g['work_count'] as int?,
    };
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ChipPickerSheet(
        title: l10n.pickerGenreTitle,
        options: [for (final g in _genreOptions) PickerOption(g, count: counts[g])],
        selected: {..._selectedGenres},
        createSharedNote: l10n.pickerCreateSharedNote,
        allowCreate: true,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Anything picked that isn't a known option is the reader's own — it has
      // to join the custom list or it won't render as a chip.
      final known = {
        ..._readerGenres.map((g) => g.toLowerCase()),
        ..._commonGenres.map((g) => g.toLowerCase()),
        ..._catalogueGenres.map((g) => (g['name'] as String? ?? '').toLowerCase()),
      };
      _selectedGenres
        ..clear()
        ..addAll(picked);
      _customGenreList
        ..clear()
        ..addAll(picked.where((g) => !known.contains(g.toLowerCase())));
    });
  }

  /// Choose the series from the catalog rather than typing it. Seeded with
  /// whatever is in the field — a scanned or extracted name should be shown
  /// its existing matches before it becomes a new row.
  Future<void> _pickSeries() async {
    final result = await context.push<Map<String, dynamic>>(
      Routes.seriesPicker,
      extra: <String, dynamic>{'name': _series.text.trim()},
    );
    if (result == null) return;
    setState(() {
      _seriesPick = result;
      _series.text = result['name'] as String? ?? '';
    });
  }

  Future<void> _pickPublisher() async {
    final result = await context.push<Map<String, dynamic>>(Routes.publisherPicker);
    if (result == null) return;
    setState(() => _publisher = result);
  }

  /// Scan a barcode and prefill the form from the looked-up book, so the ISBN
  /// (and everything the catalog knows) is captured by camera rather than typed.
  /// Every field stays editable afterwards. A not-found scan can still return
  /// just the raw ISBN so the user only types the rest.
  Future<void> _scanIsbn() async {
    setState(() => _scanning = true);
    try {
      final result = await context.push<Map<String, dynamic>>(Routes.catalogScanResult);
      if (result == null || !mounted) return;
      // A full work carries a title; the ISBN-only fallback carries just 'isbn'.
      if (result['title'] != null) {
        _applyScannedWork(result);
      } else if (result['isbn'] is String) {
        setState(() => _isbn.text = result['isbn'] as String);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Only photos the user uploaded through this app (our covers bucket) can be
  /// sent for extraction — an OpenLibrary cover URL, say, would be rejected by
  /// the server anyway, so the button never lights up for one.
  bool _isOwnUpload(String? url) =>
      url != null && url.contains('/storage/v1/object/public/covers/');

  /// The "read the covers" rescue path (S7b): send the photographed cover
  /// URL(s) to `POST /catalog/cover-extract` and prefill whatever came back —
  /// but only into fields that are still empty. The user's own typing always
  /// wins, and everything stays editable.
  ///
  /// [backUrl] overrides the form's back-cover slot — the scan flow reads a
  /// freshly captured photo that deliberately is NOT the slot's value yet.
  /// Returns whether the extraction call itself succeeded; "nothing readable"
  /// still counts (the photo reached the reader — the fields were simply full,
  /// or the text unreadable), a transport/server error does not.
  Future<bool> _fillFromPhotos({String? backUrl}) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Read before the awaits: the blurb lands frames later, and a `ref` read
    // after an await is a read on a widget that may be gone.
    final api = ref.read(apiClientProvider);
    setState(() => _extracting = true);

    // Both halves leave together, so the blurb is already being transcribed
    // while the reader reads the title.
    final parts = startCoverExtract(
      api,
      frontUrl: _isOwnUpload(_coverUrl) ? _coverUrl : null,
      backUrl: backUrl ?? (_isOwnUpload(_backCoverUrl) ? _backCoverUrl : null),
    );

    var filled = false;
    try {
      filled = _applyExtracted(await parts.identity);
    } on DioException catch (err) {
      final data = err.response?.data;
      final code = data is Map ? data['code'] : null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            code == 'extraction_disabled' ? l10n.formExtractUnavailable : l10n.formExtractFailed,
          ),
        ),
      );
      return false;
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractFailed)));
      return false;
    } finally {
      // Dropped as soon as the identity fields are in — the reader is not kept
      // waiting behind a blurb they can watch arrive.
      if (mounted) setState(() => _extracting = false);
    }

    // …and the blurb behind them. Never throws (see startCoverExtract).
    if (!mounted) return true;
    if (_applyExtracted(await parts.description)) filled = true;
    // Said only once both halves have settled: a read that found no title but
    // did find a blurb has not "found nothing".
    if (mounted && !filled) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractNothing)));
    }
    return true;
  }

  /// "Read the back": get the blurb (and the printed literary form —
  /// "നോവൽ" → Novel) off the book's back cover into the empty fields. Still
  /// fills only empty fields, so your own text is never clobbered.
  ///
  /// Reworked 2 Sep 2026 (owner request). When the form already holds an
  /// uploaded back cover, a sheet asks whether to read *that* or point the
  /// camera at the book — re-photographing what the form already has is the
  /// camera as a punishment. A fresh capture goes straight to the camera with
  /// NO crop step (the photo is taken to be read, not shelved — between the
  /// shutter and the answer there is nothing to decide), and it no longer
  /// clobbers the back-cover slot on its way in: only after a successful read,
  /// and only with the reader's say-so, does it become the back cover — the
  /// photo was framed to be read, not to be shown on a shelf, so whatever the
  /// slot holds the question is asked (owner decision, 2 Sep 2026).
  Future<void> _scanBackCover() async {
    final l10n = AppLocalizations.of(context)!;
    // Only an own upload can be re-read: the extractor accepts covers-bucket
    // URLs alone, so an external back cover has nothing to offer here.
    if (_isOwnUpload(_backCoverUrl)) {
      final choice = await showScanBackSheet(context);
      if (choice == null || !mounted) return;
      if (choice == ScanBackChoice.uploaded) {
        await _fillFromPhotos();
        return;
      }
    }

    setState(() => _uploadingBack = true);
    String? url;
    try {
      url = await pickUploadPhoto(source: ImageSource.camera, folder: 'covers');
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.coverUploadFailed, err);
      }
    } finally {
      if (mounted) setState(() => _uploadingBack = false);
    }
    if (url == null || !mounted) return;

    // Read the fresh photo, not the slot — the slot may still hold the old
    // cover, and must keep holding it if the reader says so below.
    final ok = await _fillFromPhotos(backUrl: url);
    if (!ok || !mounted) return;

    final hasExisting = _backCoverUrl != null;
    final use = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.scanBackReplaceTitle),
        content: Text(hasExisting ? l10n.scanBackReplaceBody : l10n.scanBackSetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(hasExisting ? l10n.scanBackKeep : l10n.scanBackSkip),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hasExisting ? l10n.scanBackReplace : l10n.scanBackSet),
          ),
        ],
      ),
    );
    if (use == true && mounted) setState(() => _backCoverUrl = url);
  }

  /// Prefill empty fields from the extraction result. Returns whether anything
  /// was actually filled (nothing readable → the caller says so).
  bool _applyExtracted(Map<String, dynamic> fields) {
    var filled = false;
    setState(() {
      final title = fields['title'] as String?;
      if (title != null && _title.text.trim().isEmpty) {
        _title.text = title;
        filled = true;
      }
      final authors = (fields['authors'] as List?)?.cast<String>() ?? const <String>[];
      if (_authors.isEmpty && authors.isNotEmpty) {
        // Name-only entries — the save payload already routes id-less authors
        // through `author_names` (server get-or-creates them).
        _authors.addAll([
          for (final name in authors) {'name': name},
        ]);
        filled = true;
      }
      final publisher = fields['publisher'] as String?;
      if (publisher != null && _publisher == null) {
        // The server resolves a read name onto the catalogue's canonical house
        // when it knows one, and sends its id — carry the id, so the save
        // lands on that row instead of a fourth "DC Books" beside it.
        final publisherId = fields['publisher_id'] as String?;
        _publisher = {'name': publisher, 'id': ?publisherId};
        filled = true;
      }
      final description = fields['description'] as String?;
      if (description != null && _description.text.trim().isEmpty) {
        _description.text = description;
        filled = true;
      }
      final seriesName = fields['series_name'] as String?;
      if (seriesName != null && _series.text.trim().isEmpty) {
        _series.text = seriesName;
        _hasSeries = true;
        filled = true;
      }
      final seriesNumber = fields['series_number'];
      if (_hasSeries && seriesNumber is int && _seriesNumber.text.trim().isEmpty) {
        _seriesNumber.text = '$seriesNumber';
        filled = true;
      }
      final language = fields['language'] as String?;
      if (language != null && _language == null && kLanguages.contains(language)) {
        _language = language;
        filled = true;
      }
      final form = fields['form'] as String?;
      if (form != null && _form == null && kWorkForms.contains(form)) {
        _form = form;
        filled = true;
      }
      // Server only returns a checksum-valid ISBN-13 (best-effort off the
      // barcode); fill it only if the field's empty — the Scan button stays
      // the exact path.
      final isbn = fields['isbn'] as String?;
      if (isbn != null && _isbn.text.trim().isEmpty) {
        _isbn.text = isbn;
        filled = true;
      }
      if (filled) {
        _prefillSource = 'photos';
        _detailsExpanded = true; // the grouped fields now have content — show them
      }
    });
    return filled;
  }

  void _applyScannedWork(Map<String, dynamic> work) {
    final edition = scannedEdition(work);
    final genreNames =
        (work['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ?? <String>{};

    setState(() {
      _prefillSource = 'scan';
      // A scan resolves through the catalogue (an OpenLibrary hit is cached on
      // the way past), so the book is always in it by the time we get here —
      // which is exactly why it must not then be offered back as a match.
      _prefillWorkId = work['id'] as String?;
      _prefillEditionId = edition?['id'] as String?;
      _prefillWorkTitle = work['title'] as String?;
      _similar = [
        for (final w in _similar)
          if (w['id'] != _prefillWorkId) w,
      ];
      _detailsExpanded = true;
      _title.text = work['title'] as String? ?? _title.text;
      final language = work['language'] as String?;
      if (language != null && language.isNotEmpty) _language = language;
      final form = work['form'] as String?;
      if (form != null && kWorkForms.contains(form)) _form = form;

      _authors
        ..clear()
        ..addAll(
          (work['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
              const <Map<String, dynamic>>[],
        );

      if (edition != null) {
        final series = (edition['series'] as Map?)?['name'] as String?;
        if (series != null && series.isNotEmpty) {
          _series.text = series;
          _hasSeries = true; // a scanned series reveals the fields
        }
        final seriesNumber = edition['series_number'];
        if (seriesNumber != null) _seriesNumber.text = seriesNumber.toString();
        final pages = edition['page_count'];
        if (pages != null) _pages.text = pages.toString();
        final isbn = edition['isbn'] as String?;
        if (isbn != null && isbn.isNotEmpty) _isbn.text = isbn;
        final format = edition['format'] as String?;
        if (format != null && kEditionFormats.contains(format)) _format = format;
        final cover = edition['cover_url'] as String?;
        if (cover != null) _coverUrl = cover;
        final back = edition['back_cover_url'] as String?;
        if (back != null) _backCoverUrl = back;
        final publisher = edition['publisher'] as Map?;
        if (publisher != null) _publisher = Map<String, dynamic>.from(publisher);
      }

      _selectedGenres
        ..clear()
        ..addAll(genreNames);
      _customGenreList
        ..clear()
        ..addAll(genreNames.where((g) => !_commonGenres.contains(g)));
    });
  }

  /// Tapping a cover slot opens the options sheet (adapts to whether a photo is
  /// already set). Camera/gallery capture → crop → upload; "adjust" re-crops the
  /// existing photo; "remove" clears it. Cancelling anywhere — the sheet, the
  /// camera, or the crop — is a clean no-op, so a mis-tap never forces a capture.
  /// New books have no edition id yet, so images land under `covers/<uuid>.jpg`.
  ///
  /// A camera capture on a book with *no* covers yet chains: once the first
  /// side lands, a sheet offers the other side straight away, so both covers
  /// come from one camera run instead of tap-slot → capture → come back →
  /// tap-other-slot → capture (owner request, 9 Aug 2026).
  Future<void> _onCoverTap({required bool back}) async {
    final current = back ? _backCoverUrl : _coverUrl;
    final bothEmpty = _coverUrl == null && _backCoverUrl == null;
    final action = await showCoverActionSheet(context, hasImage: current != null);
    if (action == null || !mounted) return;

    if (action == CoverAction.remove) {
      setState(() => back ? _backCoverUrl = null : _coverUrl = null);
      return;
    }

    if (action == CoverAction.camera) {
      final captured = await _captureCoverCamera(back: back);
      if (captured && bothEmpty && mounted && (back ? _coverUrl == null : _backCoverUrl == null)) {
        final next = await showChainedCoverSheet(context, nextIsBack: !back);
        if (next && mounted) await _captureCoverCamera(back: !back);
      }
      return;
    }

    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final String? url;
      switch (action) {
        case CoverAction.gallery:
          url = await pickCropUploadImage(
            source: ImageSource.gallery,
            folder: 'covers',
            ratio: CropRatio.cover,
          );
        case CoverAction.adjust:
          url = await recropUploadImage(url: current!, folder: 'covers', ratio: CropRatio.cover);
        case CoverAction.rotate:
          url = await rotateUploadImage(
            context: context,
            url: current!,
            folder: 'covers',
            ratio: CropRatio.cover,
          );
        case CoverAction.camera:
        case CoverAction.remove:
          url = null; // handled above
      }
      if (mounted && url != null) {
        setState(() => back ? _backCoverUrl = url : _coverUrl = url);
      }
    } catch (err) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final base = action == CoverAction.adjust ? l10n.coverAdjustFailed : l10n.coverUploadFailed;
        // Include a concise real reason — cover upload/crop couldn't be tested
        // on a real device before shipping, so surface what actually failed.
        showQuietError(context, base, err);
      }
    } finally {
      if (mounted) setState(() => back ? _uploadingBack = false : _uploadingFront = false);
    }
  }

  /// One camera capture → crop → upload into the [back] slot. Returns whether
  /// a photo actually landed (false on cancel or failure) so the caller knows
  /// whether chaining to the other side makes sense.
  Future<bool> _captureCoverCamera({required bool back}) async {
    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final url = await pickCropUploadImage(
        source: ImageSource.camera,
        folder: 'covers',
        ratio: CropRatio.cover,
      );
      if (mounted && url != null) {
        setState(() => back ? _backCoverUrl = url : _coverUrl = url);
      }
      return url != null;
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.coverUploadFailed, err);
      }
      return false;
    } finally {
      if (mounted) setState(() => back ? _uploadingBack = false : _uploadingFront = false);
    }
  }

  /// [work] with [edition] swapped in for the edition of the same id — the
  /// Work returned by `updateWork` predates the edition patch that follows it,
  /// so anything cached from it would carry the pre-edit edition.
  Map<String, dynamic> _withEdition(Map<String, dynamic> work, Map<String, dynamic>? edition) {
    final id = edition?['id'];
    if (edition == null || id == null) return work;
    final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return {
      ...work,
      'editions': [
        for (final e in editions)
          if (e['id'] == id) edition else e,
      ],
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    // Read before the awaits — this widget may be gone by the time the cache
    // mirror below runs, and `ref` isn't safe to touch after dispose.
    final db = ref.read(appDatabaseProvider);
    final genres = _selectedGenres.toList();
    final publisherId = _publisher?['id'] as String?;
    final payload = {
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'language': _language,
      'form': _form,
      // Ids for picker-chosen authors; names only for anything without one.
      'author_ids': [
        for (final a in _authors)
          if (a['id'] != null) a['id'] as String,
      ],
      'author_names': [
        for (final a in _authors)
          if (a['id'] == null) a['name'] as String,
      ],
      'translator_ids': [
        for (final t in _translators)
          if (t['id'] != null) t['id'] as String,
      ],
      'translator_names': [
        for (final t in _translators)
          if (t['id'] == null) t['name'] as String,
      ],
      // "Translated from" — only meaningful on create; the server joins the
      // original's translation group and records the direction. Edit mode
      // links post-save instead (updateWork doesn't accept it).
      'original_work_id': _original?['id'],
      'genre_names': genres,
      'publisher_id': publisherId,
      'publisher_name': publisherId == null ? (_publisher?['name'] as String?) : null,
      'series_id': _hasSeries ? (_seriesPick?['id'] as String?) : null,
      // Only when nothing was picked: a name off a scanned cover still beats
      // losing the series, and the server get-or-creates it.
      'series_name': _hasSeries && _seriesPick == null && _series.text.trim().isNotEmpty
          ? _series.text.trim()
          : null,
      'series_number': _hasSeries ? int.tryParse(_seriesNumber.text.trim()) : null,
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
      'page_count': int.tryParse(_pages.text.trim()),
      'format': _format,
      // On create these land on the new edition. Never null a cover out on edit.
      if (_coverUrl != null) 'cover_url': _coverUrl,
      if (_backCoverUrl != null) 'back_cover_url': _backCoverUrl,
    };

    Map<String, dynamic>? created;
    try {
      final api = ref.read(apiClientProvider);
      final workId = widget.initialWork?['id'] as String?;
      if (workId == null) {
        // Before the round trip, not after it: the scan already told us this
        // book is in the catalogue.
        if (await _offerTheEntryTheScanResolved()) return;
        created = await api.createWork(payload);
      } else {
        final result = await api.updateWork(workId, payload);
        // A newly attached original (the edit form's Translated-from row) —
        // updateWork doesn't carry it, so link it explicitly. Additive only:
        // there's no unlink flow yet.
        final originalId = _original?['id'] as String?;
        if (originalId != null && originalId != _initialOriginalId) {
          await api.linkTranslation(workId, originalId, relation: 'original');
        }
        // Everything below lives on the Edition, not the Work — `updateWork`
        // accepts none of it, so until now an edit that added a page count (or
        // an ISBN, format, publisher, series) was silently thrown away: the
        // form said saved and nothing changed (owner report, 17 Jul 2026).
        // Only what actually changed is sent, so a save can't clobber a field
        // the reader never touched.
        final editionId = _edition?['id'] as String?;
        Map<String, dynamic>? patchedEdition;
        if (editionId != null) {
          final pageCount = int.tryParse(_pages.text.trim());
          final isbn = _isbn.text.trim().isEmpty ? null : _isbn.text.trim();
          final seriesId = _hasSeries ? (_seriesPick?['id'] as String?) : null;
          final seriesName = _hasSeries && _seriesPick == null && _series.text.trim().isNotEmpty
              ? _series.text.trim()
              : null;
          final seriesNumber = _hasSeries ? int.tryParse(_seriesNumber.text.trim()) : null;
          final publisherName = _publisher?['name'] as String?;
          final edPatch = <String, dynamic>{
            if (_coverUrl != null && _coverUrl != _initialCoverUrl) 'cover_url': _coverUrl,
            if (_backCoverUrl != null && _backCoverUrl != _initialBackCoverUrl)
              'back_cover_url': _backCoverUrl,
            if (pageCount != null && pageCount != _initialPageCount) 'page_count': pageCount,
            if (isbn != null && isbn != _initialIsbn) 'isbn': isbn,
            // Never null an existing format out — same rule as covers.
            if (_format != null && _format != _initialFormat) 'format': _format,
            if (seriesId != null && seriesId != _initialSeriesId) 'series_id': seriesId,
            if (seriesId == null && seriesName != null && seriesName != _initialSeriesName)
              'series_name': seriesName,
            if (seriesNumber != null && seriesNumber != _initialSeriesNumber)
              'series_number': seriesNumber,
            // Publisher rides as an id when picked from the catalog, else by
            // name for the server to resolve — same shape as create. The
            // name branch used to require `_initialPublisherId != null`,
            // which meant a publisher could be *changed* by name but never
            // *added* by one: the exact case the extraction fills in on an
            // entry that has no publisher at all.
            if (publisherId != null && publisherId != _initialPublisherId)
              'publisher_id': publisherId,
            if (publisherId == null &&
                publisherName != null &&
                publisherName != _initialPublisherName)
              'publisher_name': publisherName,
          };
          if (edPatch.isNotEmpty) {
            patchedEdition = await api.updateEdition(editionId, edPatch);
          }
        }
        // Mirror the edit into the offline cache the shelf reads from —
        // otherwise a new Type/title/page count saves server-side but the
        // library grid and its filters keep showing the stale row (16 Jul
        // 2026). Splice the patched edition back in first: `result` was
        // fetched *before* the edition patch, so caching it as-is would write
        // the very page count we just changed straight back as stale.
        final updated = result['work'];
        if (updated is Map<String, dynamic>) {
          unawaited(
            refreshCachedWork(db, _withEdition(updated, patchedEdition)).catchError((_) {}),
          );
        }
        ref.invalidate(workProvider(workId));
        if (mounted) {
          // Someone else's book: the edit went to its contributor's approval
          // queue instead of the live catalog — say so, or "saved" silence
          // reads as the change having vanished.
          if (result['applied'] == false) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.editPendingApproval),
                duration: const Duration(seconds: 5),
              ),
            );
          }
          _confirmedLeave = true; // saved — nothing left for the guard to protect
          context.pop();
        }
      }
    } catch (err) {
      if (mounted && !await _offerTheBookThisIsbnAlreadyNames(err)) {
        if (mounted) showQuietError(context, AppLocalizations.of(context)!.formSaveFailed, err);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (created != null && mounted) {
      // Saved — leaving now loses nothing, so the guard stands down.
      _confirmedLeave = true;
      // Pick mode: someone is waiting on this book (the borrow sheet's "not in
      // the catalog?" path). Hand it straight back and close — the standalone
      // popup's "Add to library"/"Create another" are the wrong next steps
      // mid-flow, and the caller selects it for them.
      if (widget.returnCreated) {
        context.pop(created);
        return;
      }
      // Create mode lands on the confirmation popup instead of silently
      // popping: what was made, plus "Add to library" / "Create another"; the
      // screen itself only closes on the popup's Close.
      await _showCreatedDialog(created);
    }
  }

  /// Wipes the form back to a blank create state — the popup's
  /// "Create another".
  void _resetForm() {
    setState(() {
      _formKey.currentState?.reset();
      _title.clear();
      _description.clear();
      _seriesPick = null;
      _series.clear();
      _seriesNumber.clear();
      _pages.clear();
      _isbn.clear();
      _customGenreList.clear();
      _authors.clear();
      _translators.clear();
      _original = null;
      _publisher = null;
      _language = null;
      _form = null;
      _format = null;
      _hasSeries = false;
      _detailsExpanded = false;
      _prefillSource = null;
      _selectedGenres.clear();
      _coverUrl = null;
      _backCoverUrl = null;
      _initialCoverUrl = null;
      _initialBackCoverUrl = null;
      _similar = const [];
      _similarDismissed = false;
      _similarDismissedQuery = '';
      // The book that was just saved is not this one. Leaving the scan's
      // prefill behind would have the next save offer to improve the previous
      // reader's book — the identity has to be wiped with the fields.
      _prefillWorkId = null;
      _prefillEditionId = null;
      _prefillWorkTitle = null;
    });
    // A blank form has nothing to lose — re-baseline the unsaved guard.
    _cleanFingerprint = _fingerprint();
    _confirmedLeave = false;
    // Back to the top, cursor in the title: a fresh record starts where a
    // reader would start one.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _titleFocus.requestFocus();
  }

  /// The just-created book's confirmation popup: its metadata, an
  /// "Add to library" whose label walks Add → Adding… → Added ✓, and
  /// "Create another". Deliberately not barrier-dismissible — the screen
  /// closes only from the Close action.
  Future<void> _showCreatedDialog(Map<String, dynamic> work) async {
    final l10n = AppLocalizations.of(context)!;
    final edition =
        ((work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? const []).firstOrNull;
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authorNames = authors.map((a) => a['name'] as String? ?? '').join(', ');
    final publisher = (edition?['publisher'] as Map?)?['name'] as String?;
    final metaParts = [
      ?publisher,
      if (edition?['page_count'] != null) '${edition!['page_count']} pp',
      ?edition?['format'] as String?,
    ];
    final isbn = edition?['isbn'] as String?;

    // idle → adding → added; lives outside the builder so sheet rebuilds keep it.
    var phase = 'idle';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> addToLibrary() async {
            if (phase != 'idle' || edition == null) return;
            setDialogState(() => phase = 'adding');
            try {
              // Cache first so the library grid's cover tile finds the catalog
              // data the moment the entry appears (rule 2).
              await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
              final repo = await ref.read(libraryRepositoryProvider.future);
              await repo.add(editionId: edition['id'] as String);
              setDialogState(() => phase = 'added');
            } catch (err) {
              setDialogState(() => phase = 'idle');
              if (ctx.mounted) showQuietError(ctx, l10n.quickAddFailed, err);
            }
          }

          return Dialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: AppColors.moss),
                      SizedBox(width: 8),
                      Text(
                        l10n.createdDialogTitle.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TypesetCover(
                        title: work['title'] as String? ?? '',
                        author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                        coverUrl: edition?['cover_url'] as String?,
                        width: 52,
                        height: 76,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              work['title'] as String? ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                            if (authorNames.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  authorNames,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                                ),
                              ),
                            if (metaParts.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  metaParts.join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                                ),
                              ),
                            if (isbn != null && isbn.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'ISBN $isbn',
                                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  if (edition != null)
                    ElevatedButton.icon(
                      onPressed: phase == 'idle' ? addToLibrary : null,
                      style: ElevatedButton.styleFrom(
                        // "Added ✓" keeps its ink on the disabled button — the
                        // state must stay readable, not fade out.
                        disabledBackgroundColor: phase == 'added'
                            ? AppColors.moss.withValues(alpha: 0.14)
                            : null,
                        disabledForegroundColor: phase == 'added' ? AppColors.moss : null,
                      ),
                      icon: phase == 'adding'
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.inkSoft,
                              ),
                            )
                          : Icon(
                              phase == 'added' ? Icons.check : Icons.library_add_outlined,
                              size: 16,
                            ),
                      label: Text(switch (phase) {
                        'adding' => l10n.createdAdding,
                        'added' => l10n.createdAdded,
                        _ => l10n.createdAddToLibrary,
                      }),
                    ),
                  SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _resetForm();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.oxblood,
                      side: BorderSide(color: AppColors.line),
                    ),
                    icon: Icon(Icons.add, size: 16),
                    label: Text(l10n.createdCreateAnother),
                  ),
                  SizedBox(height: 2),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      if (mounted) context.pop();
                    },
                    child: Text(
                      l10n.createdClose,
                      style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = widget.initialWork != null;

    final form = Form(
      key: _formKey,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.ink),
                onPressed: _maybeLeave,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? l10n.formTitleEdit : l10n.formTitleAdd,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      l10n.formSubtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // M5 — editing a shared entry is announced *before* typing, not
          // after saving. Ownership isn't in the payload, so the phrasing
          // covers both cases: the reader's own book publishes live, another
          // reader's goes to its contributor for review.
          if (isEdit) ...[
            SizedBox(height: 8),
            _EditReviewBanner(message: l10n.formEditReviewBanner),
          ],
          // The capture strip — the two paths that fill the form lead,
          // full-width, before any field (they used to hide mid-form: scan as
          // a small icon inside the ISBN field, photos only after an upload).
          if (!isEdit) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? null : _scanIsbn,
                    icon: _scanning
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.paper,
                            ),
                          )
                        : Icon(Icons.qr_code_scanner, size: 18),
                    label: Text(l10n.formCaptureScan),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      textStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploadingFront ? null : () => _onCoverTap(back: false),
                    icon: Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(l10n.formCapturePhoto),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      textStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 5),
            Center(
              child: Text(
                l10n.formCaptureHelp,
                style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
              ),
            ),
          ],
          // Prefilled data is announced, not silent — a quiet dismissible
          // banner saying where it came from and that everything is editable.
          if (_prefillSource != null) ...[
            SizedBox(height: 10),
            _PrefillBanner(
              message: switch (_prefillSource) {
                'scan' => l10n.formPrefillScan,
                'seed' => l10n.formPrefillCarried,
                _ => l10n.formPrefillPhotos,
              },
              onDismiss: () => setState(() => _prefillSource = null),
            ),
          ],
          // What this copy said where the entry already had its own answer.
          // The catalogue keeps its answer until the reader says otherwise —
          // but they can see it, which is the whole difference.
          if (_carried.isNotEmpty) ...[
            SizedBox(height: 10),
            _CarriedPanel(
              items: List.unmodifiable(_carried),
              onUse: (item) => setState(() {
                item.apply();
                _carried.remove(item);
              }),
              onDismiss: () => setState(_carried.clear),
            ),
          ],
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverSlot(
                label: l10n.formCoverFront,
                imageUrl: _coverUrl,
                busy: _uploadingFront,
                // Front falls back to the live typeset preview from title/author.
                title: _title.text.isEmpty ? '…' : _title.text,
                author: _authors.isEmpty ? null : _authors.first['name'] as String?,
                width: 64,
                height: 96,
                onTap: () => _onCoverTap(back: false),
              ),
              SizedBox(width: 12),
              CoverSlot(
                label: l10n.formCoverBack,
                imageUrl: _backCoverUrl,
                busy: _uploadingBack,
                onTap: () => _onCoverTap(back: true),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.formCoverHelp,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.3),
                ),
              ),
            ],
          ),
          // Once a photo is up, offer to read the details off it — the rescue
          // path for books no catalog knows. Prefills only empty fields.
          if (_isOwnUpload(_coverUrl) || _isOwnUpload(_backCoverUrl)) ...[
            SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: (_extracting || _uploadingBack) ? null : _fillFromPhotos,
                icon: _extracting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.oxblood),
                      )
                    : Icon(Icons.auto_awesome, size: 16, color: AppColors.oxblood),
                label: Text(l10n.formFillFromPhotos),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          SizedBox(height: 16),
          FormTextField(
            label: l10n.formFieldTitle,
            controller: _title,
            focusNode: _titleFocus,
            validator: (v) => (v == null || v.trim().isEmpty) ? l10n.formTitleRequired : null,
          ),
          // Quiet duplicate check (create mode): near-matches already in the
          // catalog slide in under the title. Tapping one opens the M1 fork —
          // shelf copy / new edition / translation / different book — because
          // "Kitabi already has this book" means four different things.
          if (!isEdit && !_similarDismissed && _similar.isNotEmpty) ...[
            SizedBox(height: 8),
            _SimilarWorksPanel(
              works: _similar,
              busyId: _forkBusyId,
              onDismiss: () => setState(() {
                _similarDismissed = true;
                _similarDismissedQuery = _title.text.trim().toLowerCase();
              }),
              onPick: _openFork,
            ),
          ],
          SizedBox(height: 10),
          _AuthorField(
            authors: _authors,
            onAdd: _pickAuthor,
            onAddSelf: _pickAuthorAsSelf,
            onRemove: (author) => setState(() => _authors.remove(author)),
          ),
          SizedBox(height: 10),
          _LanguageField(
            label: l10n.formFieldLanguage,
            value: _language,
            unsetLabel: l10n.formLanguageUnset,
            // The reader's own languages first; note points to profile to
            // manage the list. Falls back to all if none set yet.
            languages:
                (ref.watch(meProvider).valueOrNull?['preferred_languages'] as List?)
                    ?.cast<String>() ??
                const [],
            note: l10n.formLanguageProfileNote,
            onChanged: (v) => setState(() => _language = v),
          ),
          // "Translated from" (T1/T4) — directly under Language because it is
          // a language question. Dashed while empty, the gold provenance card
          // once linked; the Translator field appears only alongside a link.
          SizedBox(height: 12),
          _TranslatedFromField(
            original: _original,
            onLink: _pickOriginal,
            // Clearable while creating; edit mode is additive-only (there's
            // no unlink endpoint yet), so a loaded link can't be removed.
            onClear: widget.initialWork == null ? () => setState(() => _original = null) : null,
          ),
          if (_original != null) ...[
            SizedBox(height: 10),
            _TranslatorField(
              translators: _translators,
              onAdd: _pickTranslator,
              onRemove: (t) => setState(() => _translators.remove(t)),
            ),
          ],
          // Type and genre are primary — they power the library filter — but
          // the rows are a *shortcut*, not the vocabulary (mockup M10): a
          // handful of chips, then a "Search or add" chip at the end of the row
          // opening the full picker. The door moved out of the label and into
          // the row itself (owner request, 22 Jul 2026) — it reads as the next
          // chip after the last option, which is where a reader who wants
          // something not shown is already looking. That's what keeps the form
          // the same size whether the catalogue carries 10 genres or 500; the
          // honest total now greets them in the picker's own subtitle.
          SizedBox(height: 12),
          Text(l10n.formFieldType, style: formFieldLabelStyle),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final form in _visibleTypes)
                FilterChip(
                  label: Text(form, style: TextStyle(fontSize: 12)),
                  showCheckmark: false,
                  selected: _form == form,
                  onSelected: (sel) => setState(() => _form = sel ? form : null),
                  selectedColor: AppColors.oxblood,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _form == form ? AppColors.paper : AppColors.ink,
                  ),
                  side: BorderSide(color: _form == form ? AppColors.oxblood : AppColors.line),
                ),
              _MoreChip(onTap: _openTypePicker),
            ],
          ),
          SizedBox(height: 12),
          Text(l10n.formFieldGenrePrimary, style: formFieldLabelStyle),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final genre in _visibleGenres)
                FilterChip(
                  label: Text(localizedGenre(l10n, genre), style: TextStyle(fontSize: 12)),
                  showCheckmark: false,
                  selected: _selectedGenres.contains(genre),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _selectedGenres.add(genre);
                    } else {
                      _selectedGenres.remove(genre);
                      // A custom genre deselected has nowhere to live — drop it
                      // rather than leave a dead chip on the row.
                      _customGenreList.remove(genre);
                    }
                  }),
                  selectedColor: AppColors.oxblood,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _selectedGenres.contains(genre) ? AppColors.paper : AppColors.ink,
                  ),
                  side: BorderSide(
                    color: _selectedGenres.contains(genre) ? AppColors.oxblood : AppColors.line,
                  ),
                ),
              _MoreChip(onTap: _openGenrePicker),
            ],
          ),
          if (_readerGenres.isNotEmpty) ...[
            SizedBox(height: 5),
            Text(l10n.formGenreYoursNote, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          ],
          // Everything less essential folds into one disclosure — collapsed on
          // a fresh create, open on edit or when a scan/photo-read filled it.
          SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: _detailsExpanded ? AppColors.card : AppColors.paperDeep,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.formMoreDetails,
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(
                              _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                              color: AppColors.inkSoft,
                            ),
                          ],
                        ),
                        if (!_detailsExpanded)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              l10n.formMoreDetailsSummary,
                              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_detailsExpanded)
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SeriesToggle(
                          label: l10n.formSeriesToggle,
                          sublabel: l10n.formSeriesToggleSub,
                          value: _hasSeries,
                          onChanged: (v) => setState(() => _hasSeries = v),
                        ),
                        if (_hasSeries) ...[
                          SizedBox(height: 8),
                          // A grouped well so the two series fields read as one
                          // unit belonging to the toggle, not two loose inputs.
                          Container(
                            padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                            decoration: BoxDecoration(
                              color: AppColors.paperDeep,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.formSeriesHint,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.inkSoft,
                                    height: 1.3,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 14,
                                      // Picked, not typed: one ordering per
                                      // series only survives if the reader
                                      // chooses the existing row. A name that
                                      // arrived from a scan still shows here,
                                      // and tapping opens the picker seeded
                                      // with it.
                                      child: PickerButtonField(
                                        label: l10n.formFieldSeries,
                                        value: _series.text.isEmpty ? null : _series.text,
                                        placeholder: l10n.formSeriesPick,
                                        onTap: _pickSeries,
                                        onClear: _series.text.isEmpty
                                            ? null
                                            : () => setState(() {
                                                _seriesPick = null;
                                                _series.clear();
                                              }),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      flex: 9,
                                      child: FormTextField(
                                        label: l10n.formFieldBookNumber,
                                        controller: _seriesNumber,
                                        keyboardType: TextInputType.number,
                                        fillColor: AppColors.card,
                                        helper: l10n.formBookNumberHelp,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 14,
                              child: PickerButtonField(
                                label: l10n.formFieldPublisher,
                                value: _publisher?['name'] as String?,
                                placeholder: l10n.formPublisherChoose,
                                onTap: _pickPublisher,
                                onClear: _publisher == null
                                    ? null
                                    : () => setState(() => _publisher = null),
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              flex: 10,
                              child: FormTextField(
                                label: l10n.formFieldPages,
                                controller: _pages,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 14,
                              child: IsbnScanField(
                                controller: _isbn,
                                onScan: _scanIsbn,
                                scanning: _scanning,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              flex: 10,
                              child: FormatField(
                                value: _format,
                                onChanged: (v) => setState(() => _format = v),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        FormTextField(
                          label: l10n.formFieldDescription,
                          controller: _description,
                          maxLines: 4,
                          helper: l10n.formDescriptionHelp,
                          expandable: true,
                          // Read the blurb (and the printed type) straight off
                          // the back cover — a link beside the field it fills,
                          // not a button lost among the covers.
                          labelAction: InkWell(
                            onTap: (_extracting || _uploadingBack) ? null : _scanBackCover,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(8, 2, 4, 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  (_extracting || _uploadingBack)
                                      ? SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.oxblood,
                                          ),
                                        )
                                      : Icon(
                                          Icons.document_scanner_outlined,
                                          size: 12,
                                          color: AppColors.oxblood,
                                        ),
                                  SizedBox(width: 4),
                                  Text(
                                    l10n.formScanBackCover,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.oxblood,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // The form scrolls; Save never does — a sticky bar keeps it (and its
    // one-line consequence note) visible without scrolling a long form.
    // While the covers are being read, a full-screen "reading your cover"
    // overlay sits above everything (the scan takes a few seconds on the
    // vision model) — far more legible than the little button spinner.
    //
    // PopScope guards the system back gesture and edge swipe; the header's
    // back arrow routes through the same [_maybeLeave], so one swipe can
    // never silently discard a half-typed book.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(child: form),
              FormSaveBar(
                saving: _saving,
                onSave: _save,
                label: l10n.formSave,
                // The create hint promises the shared catalogue; the edit path
                // says where an edit actually goes (M5).
                hint: isEdit ? l10n.formSaveHintEdit : l10n.formSaveHint,
              ),
            ],
          ),
          if (_extracting)
            _ExtractingOverlay(
              coverUrl: _coverUrl ?? _backCoverUrl,
              title: _title.text.isEmpty ? '…' : _title.text,
              author: _authors.isEmpty ? null : _authors.first['name'] as String?,
            ),
        ],
      ),
    );
  }
}

/// M5 — the quiet gold notice at the top of the *edit* form: this is a shared
/// entry, and an edit to another reader's contribution goes to them for
/// review. Shown before typing, not sprung after saving.
class _EditReviewBanner extends StatelessWidget {
  const _EditReviewBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, size: 14, color: AppColors.goldInk),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.goldInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dismissible gold provenance banner — shown after a barcode scan or a
/// cover-photo read prefilled the form, so prefilled data is announced.
/// One thing the reader's copy said that the catalogue entry already answers
/// differently — offered, never applied on its own.
///
/// The seed's rule stands (an entry that answers a question keeps its answer),
/// but a *silently* dropped value left the reader clearing fields and
/// re-running the extraction to find out what their book actually said (owner
/// report, 5 Sep 2026).
class _Carried {
  const _Carried({
    required this.label,
    required this.mine,
    required this.theirs,
    required this.apply,
    this.photo = false,
  });

  /// Which field this is — a key the panel turns into a localised name.
  final String label;

  /// What this copy says. For [photo] rows it is an image URL, not prose.
  final String mine;

  /// What the entry says, when it says anything.
  final String? theirs;

  /// Take this copy's answer. Called inside the form's own `setState`.
  final VoidCallback apply;

  final bool photo;
}

/// "From your copy" — every captured value the entry already answers, each
/// with what it says now, and a tap to take this copy's instead.
class _CarriedPanel extends StatelessWidget {
  const _CarriedPanel({required this.items, required this.onUse, required this.onDismiss});

  final List<_Carried> items;
  final void Function(_Carried item) onUse;
  final VoidCallback onDismiss;

  String _name(AppLocalizations l10n, String label) => switch (label) {
        'title' => l10n.carriedFieldTitle,
        'authors' => l10n.carriedFieldAuthors,
        'description' => l10n.carriedFieldDescription,
        'isbn' => l10n.carriedFieldIsbn,
        'pages' => l10n.carriedFieldPages,
        'format' => l10n.carriedFieldFormat,
        'language' => l10n.carriedFieldLanguage,
        'form' => l10n.carriedFieldType,
        'publisher' => l10n.carriedFieldPublisher,
        'series' => l10n.carriedFieldSeries,
        'genres' => l10n.carriedFieldGenres,
        'cover_front' => l10n.carriedFieldCoverFront,
        _ => l10n.carriedFieldCoverBack,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(12),
        // Uniform border — a thicker accent side here would throw at paint
        // time and draw a blank box (CLAUDE.md, 21 Jul 2026).
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows, size: 14, color: AppColors.gold),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.carriedHeader,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          Text(
            l10n.carriedHelp,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.25),
          ),
          SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.photo) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        item.mine,
                        width: 26,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => SizedBox(width: 26, height: 38),
                      ),
                    ),
                    SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name(l10n, item.label).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          item.photo ? l10n.carriedYourPhoto : item.mine,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        if (item.theirs != null && item.theirs!.trim().isNotEmpty)
                          Text(
                            l10n.carriedEntrySays(item.theirs!.trim()),
                            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  TextButton(
                    onPressed: () => onUse(item),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.oxblood,
                      textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    child: Text(l10n.carriedUse),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  // The gold-on-goldSoft ink the status pills already use for "To read".
  static Color get _ink => AppColors.goldInk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.goldSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: _ink),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: _ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The quiet duplicate-check panel (S7b): near-matches from the catalog for
/// the title being typed. A soft paperDeep well — no dialog, no focus steal —
/// with compact tappable rows and an ✕ that dismisses it for this form.
class _SimilarWorksPanel extends StatelessWidget {
  const _SimilarWorksPanel({
    required this.works,
    required this.onDismiss,
    required this.onPick,
    this.busyId,
  });

  final List<Map<String, dynamic>> works;
  final VoidCallback onDismiss;
  final void Function(Map<String, dynamic> work) onPick;

  /// The row whose printings are being fetched. Tapping a row now costs a
  /// round trip before the sheet can open, and a tap that does nothing for
  /// half a second reads as a broken row.
  final String? busyId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 14, color: AppColors.gold),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.formSimilarHeader,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          Text(
            l10n.formSimilarHelp,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.25),
          ),
          SizedBox(height: 8),
          for (final work in works)
            _SimilarWorkRow(
              work: work,
              busy: busyId != null && busyId == work['id'],
              // One at a time: a second fetch would race the first's sheet.
              onTap: busyId == null ? () => onPick(work) : null,
            ),
        ],
      ),
    );
  }
}

class _SimilarWorkRow extends StatelessWidget {
  const _SimilarWorkRow({required this.work, required this.onTap, this.busy = false});

  final Map<String, dynamic> work;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authorNames = authors.map((a) => a['name'] as String).join(', ');
    final edition = work['edition'] as Map<String, dynamic>?;
    final year = work['first_publish_year'];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            TypesetCover(
              title: work['title'] as String? ?? '',
              author: authorNames.isEmpty ? null : authorNames,
              coverUrl: edition?['cover_url'] as String?,
              width: 26,
              height: 38,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work['title'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                  if (authorNames.isNotEmpty || year != null)
                    Text(
                      [
                        if (authorNames.isNotEmpty) authorNames,
                        if (year != null) '$year',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                    ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
              )
            else
              Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Full-screen "reading your cover" state shown while `POST /catalog/cover-extract`
/// runs (a few seconds on the vision model). A gold scan line sweeps down the
/// cover — an OCR-in-progress feel — over a paper scrim, with a literary
/// fleuron and a plain-words subtitle. Absorbs touches so the form beneath is
/// inert; honours reduced motion (holds a static line).
class _ExtractingOverlay extends StatefulWidget {
  const _ExtractingOverlay({required this.coverUrl, required this.title, this.author});

  final String? coverUrl;
  final String title;
  final String? author;

  @override
  State<_ExtractingOverlay> createState() => _ExtractingOverlayState();
}

class _ExtractingOverlayState extends State<_ExtractingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _c.stop();
      _c.value = 0.5; // a settled line, no sweep
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const w = 132.0;
    const h = 198.0;
    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: AppColors.paper.withValues(alpha: 0.94),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TypesetCover(
                          title: widget.title,
                          author: widget.author,
                          coverUrl: widget.coverUrl,
                          width: w,
                          height: h,
                        ),
                        // A soft ink veil so the gold scan line reads clearly
                        // over a bright cover photo.
                        Container(color: AppColors.ink.withValues(alpha: 0.18)),
                        AnimatedBuilder(
                          animation: _c,
                          builder: (context, _) => Positioned(
                            top: (h - 2) * _c.value,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.gold.withValues(alpha: 0),
                                    AppColors.gold,
                                    AppColors.gold.withValues(alpha: 0),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withValues(alpha: 0.7),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text('❦', style: TextStyle(color: AppColors.gold, fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                  l10n.formExtractingTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 18, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    l10n.formExtractingSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Author input (S7b) — chips for the authors already chosen (each carries its
/// catalog id) plus a button that opens the full author picker page, where you
/// search existing authors (with portrait + language) or add a new one.
class _AuthorField extends StatelessWidget {
  const _AuthorField({
    required this.authors,
    required this.onAdd,
    required this.onAddSelf,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> authors;
  final VoidCallback onAdd;
  final VoidCallback onAddSelf;
  final void Function(Map<String, dynamic>) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldAuthor, style: formFieldLabelStyle),
        SizedBox(height: 4),
        // Once an author is chosen the big button collapses into a compact ＋
        // chip riding the same wrap — the chips are the field now.
        if (authors.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final author in authors)
                Chip(
                  label: Text(author['name'] as String, style: TextStyle(fontSize: 12)),
                  onDeleted: () => onRemove(author),
                  backgroundColor: AppColors.goldSoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                onPressed: onAdd,
                tooltip: l10n.formAuthorAddAnother,
                label: Icon(Icons.person_add_alt, size: 16, color: AppColors.oxblood),
                backgroundColor: AppColors.card,
                side: BorderSide(color: AppColors.line),
                visualDensity: VisualDensity.compact,
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: Icon(Icons.person_add_alt, size: 18),
              label: Text(l10n.formAuthorAddButton),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 2),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddSelf,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars_rounded, size: 15, color: AppColors.oxblood),
                SizedBox(width: 5),
                Text(
                  l10n.formAuthorAddSelf,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oxblood,
                  ),
                ),
              ],
            ),
          ),
        ),
        // The co-author hint has done its job once authors exist — drop it.
        if (authors.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Text(
              l10n.formAuthorHelp,
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
            ),
          ),
      ],
    );
  }
}

/// The "Part of a series" toggle that reveals/hides the series fields, with a
/// one-line sub-label so it's clear when to switch it on.
class _SeriesToggle extends StatelessWidget {
  const _SeriesToggle({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Icon(Icons.collections_bookmark_outlined, size: 16, color: AppColors.inkSoft),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                SizedBox(height: 1),
                Text(
                  sublabel,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.2),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.paper,
            activeTrackColor: AppColors.oxblood,
          ),
        ],
      ),
    );
  }
}

// The themed select field + option-picker sheet used to live here as
// _SelectField/_openSelectSheet; they moved to core/widgets/select_sheet.dart
// (public SelectField/openSelectSheet, now with type-to-filter on long lists)
// so the original-stub sheet in work_picker_screen shares the exact picker.

/// The language picker — a nullable select (language is optional) with a
/// leading "not set" item. Lists the reader's [languages] (their profile
/// preferences) first, then every other language Kitabi knows — a translated
/// original can be in any language, not just the reader's own. Always keeps
/// the current value even if it's outside that list, so editing an old book
/// never drops its language. A [note] points the reader to their profile.
class _LanguageField extends StatelessWidget {
  const _LanguageField({
    required this.label,
    required this.value,
    required this.unsetLabel,
    required this.languages,
    required this.note,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final String unsetLabel;
  final List<String> languages;
  final String note;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final base = languageOptions(languages);
    final options = [...base, if (value != null && !base.contains(value)) value!];
    return SelectField(
      label: label,
      displayValue: value ?? unsetLabel,
      isPlaceholder: value == null,
      note: note,
      onTap: () => openSelectSheet(
        context,
        title: l10n.pickerChoose(label.toLowerCase()),
        current: value,
        options: [
          SelectOption(null, unsetLabel, subdued: true),
          for (final option in options) SelectOption(option, option),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// T1/T4 — the "Translated from" row. Empty: a dashed slip-paper invitation
/// (the personal-notes idiom — nothing attached yet). Linked: the same
/// gold-ruled provenance card the prefill banner uses, with the original's
/// cover, title and language/year, and an ✕ while the link is still local.
class _TranslatedFromField extends StatelessWidget {
  const _TranslatedFromField({required this.original, required this.onLink, this.onClear});

  final Map<String, dynamic>? original;
  final VoidCallback onLink;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final original = this.original;

    if (original == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.formFieldTranslatedFrom, style: formFieldLabelStyle),
          SizedBox(height: 4),
          InkWell(
            onTap: onLink,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFD8C9A8), style: BorderStyle.solid),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 16, color: AppColors.oxblood),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          l10n.formLinkOriginal,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.oxblood,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    l10n.formTranslatedFromHelp,
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final edition = original['edition'] as Map<String, dynamic>?;
    final authors = (original['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final language = original['language'] as String? ?? edition?['language'] as String?;
    final year = original['first_publish_year'];
    final subtitle = [?language, if (year != null) '$year'].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldTranslatedFrom, style: formFieldLabelStyle),
        SizedBox(height: 4),
        // Left accent rule as an inner clipped bar — borderRadius plus a
        // non-uniform Border throws at paint time.
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.only(right: 9),
          child: Row(
            children: [
              Container(width: 3, height: 56, color: AppColors.gold),
              SizedBox(width: 9),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: TypesetCover(
                  title: original['title'] as String? ?? '',
                  author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                  coverUrl: edition?['cover_url'] as String?,
                  width: 26,
                  height: 38,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      original['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// T4 — translator credits, shown only while an original is linked. The same
/// chip idiom as the author field, feeding the same author picker.
class _TranslatorField extends StatelessWidget {
  const _TranslatorField({required this.translators, required this.onAdd, required this.onRemove});

  final List<Map<String, dynamic>> translators;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldTranslator, style: formFieldLabelStyle),
        SizedBox(height: 4),
        if (translators.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final translator in translators)
                Chip(
                  label: Text(translator['name'] as String, style: TextStyle(fontSize: 12)),
                  onDeleted: () => onRemove(translator),
                  backgroundColor: AppColors.goldSoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                onPressed: onAdd,
                tooltip: l10n.formAddTranslator,
                label: Icon(Icons.person_add_alt, size: 16, color: AppColors.oxblood),
                backgroundColor: AppColors.card,
                side: BorderSide(color: AppColors.line),
                visualDensity: VisualDensity.compact,
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: Icon(Icons.person_add_alt, size: 18),
              label: Text(l10n.formAddTranslator),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 5, left: 2),
          child: Text(
            l10n.formTranslatorHelp,
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
          ),
        ),
      ],
    );
  }
}

/// M1 — "Kitabi already has this book. So what are you adding?" The four-way
/// fork, phrased in the reader's words; pops one of
/// 'shelf' | 'edition' | 'translation' | 'different'.
/// The one-line "here is what we already worked out" note on the fork sheet.
/// Gold well, gold ink — the same voice the prefill banner uses for "this was
/// filled in for you", because it is the same kind of statement.
class _ForkNote extends StatelessWidget {
  const _ForkNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.goldInk),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.goldInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForkSheet extends StatelessWidget {
  const _ForkSheet({
    required this.work,
    required this.hasCaptured,
    this.duplicateCount = 0,
    this.standing = IsbnStanding.unknown,
    this.isbn = '',
  });

  final Map<String, dynamic> work;

  /// How many near-matches the panel is showing. Two or more is the shape of a
  /// typo'd title split across rows, and the only case where "these are all the
  /// same book" is a sensible thing to offer.
  final int duplicateCount;

  /// Whether the form is holding covers or details worth carrying onto the
  /// matched entry — the difference between "improve this entry" being the
  /// right answer and being noise.
  final bool hasCaptured;

  /// Where the form's ISBN stands against this entry's printings. On
  /// [IsbnStanding.newPrinting] the sheet stops offering "add my covers and
  /// details": the number in the reader's hand is not one this entry holds, so
  /// every captured field describes a printing that does not exist yet, and
  /// writing them onto an existing edition would overwrite a shared row.
  final IsbnStanding standing;
  final String isbn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final edition =
        (work['editions'] as List?)?.cast<Map<String, dynamic>>().firstOrNull ??
        work['edition'] as Map<String, dynamic>?;
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final year = work['first_publish_year'];
    final meta = [?author, if (year != null) '$year'].join(' · ');

    Widget option({
      required String value,
      required String title,
      String? help,
      required Color accent,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            onTap: () => Navigator.of(context).pop(value),
            borderRadius: BorderRadius.circular(11),
            // Left accent rule as an inner clipped bar — borderRadius plus a
            // non-uniform Border throws at paint time.
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(width: 3, color: accent),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            if (help != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  help,
                                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(l10n.forkAlreadyHere, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Row(
              children: [
                TypesetCover(
                  title: work['title'] as String? ?? '',
                  author: author,
                  coverUrl: edition?['cover_url'] as String?,
                  width: 30,
                  height: 44,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work['title'] as String? ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (meta.isNotEmpty)
                        Text(meta, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ],
            ),
            if (standing == IsbnStanding.newPrinting) ...[
              SizedBox(height: 10),
              _ForkNote(text: l10n.forkNewIsbnNote),
            ],
            SizedBox(height: 12),
            Text(
              l10n.forkQuestion.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: AppColors.inkSoft,
              ),
            ),
            SizedBox(height: 6),
            // The answers scroll; the book above them does not. Scrolling the
            // heading away would leave a list of choices with nothing saying
            // what they are choices *about*.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A number this entry does not hold answers the question
                    // for the reader: they are describing a printing the
                    // catalogue has never seen. It leads, it says why, and
                    // "add my covers and details" — which would write this
                    // printing's cover, pages and ISBN onto another one — is
                    // not on the sheet at all.
                    if (standing == IsbnStanding.newPrinting) ...[
                      option(
                        value: 'edition',
                        title: l10n.forkDifferentPrinting,
                        help: isbn.isEmpty
                            ? l10n.forkDifferentPrintingHelp
                            : l10n.forkNewIsbnHelp(isbn),
                        accent: AppColors.gold,
                      ),
                      option(value: 'shelf', title: l10n.forkOwnThis, accent: AppColors.moss),
                    ] else ...[
                      option(value: 'shelf', title: l10n.forkOwnThis, accent: AppColors.moss),
                      // Offered only when there is something to carry over — otherwise
                      // it is "I own this one" with extra steps.
                      if (hasCaptured)
                        option(
                          value: 'improve',
                          title: l10n.forkImproveThis,
                          help: l10n.forkImproveThisHelp,
                          accent: AppColors.moss,
                        ),
                      option(
                        value: 'edition',
                        title: l10n.forkDifferentPrinting,
                        help: l10n.forkDifferentPrintingHelp,
                        accent: AppColors.gold,
                      ),
                    ],
                    // Only with something to merge *with*. One match is a match; several
                    // near-identical ones are a title that got typed wrong more than
                    // once, which is a different problem and needs a different answer.
                    if (duplicateCount > 1)
                      option(
                        value: 'merge',
                        title: l10n.forkSameBookTwice,
                        help: l10n.forkSameBookTwiceHelp(duplicateCount),
                        accent: AppColors.oxblood,
                      ),
                    option(
                      value: 'translation',
                      title: l10n.forkTranslation,
                      help: l10n.forkTranslationHelp,
                      accent: AppColors.oxblood,
                    ),
                    option(
                      value: 'form',
                      title: l10n.forkDifferentForm,
                      help: l10n.forkDifferentFormHelp,
                      accent: AppColors.oxblood,
                    ),
                    option(
                      value: 'different',
                      title: l10n.forkDifferentBook,
                      accent: AppColors.line,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// M10 — the last chip on a Type/Genre row: the door to the full picker, where
/// the reader can search the whole vocabulary or add a term that isn't in it.
///
/// It sits *in* the row rather than beside the label (owner request, 22 Jul
/// 2026, replacing the "All 11 ⌕" pill) because a reader who can't find what
/// they want is already looking at the end of the chips, not back up at the
/// heading. Deliberately styled apart from the options either side of it —
/// dashed-feel tinted fill, oxblood text — so it never reads as a selectable
/// value called "Search or add".
class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            // Uniform border: a non-uniform one here would throw at paint time
            // and draw a blank chip (CLAUDE.md, 21 Jul 2026).
            border: Border.all(color: AppColors.gold),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 14, color: AppColors.oxblood),
              SizedBox(width: 5),
              Text(
                l10n.formPickerMore,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.oxblood,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What [_MergeSheet] hands back: the row that stays, and the rows folded into
/// it.
class _MergeChoice {
  const _MergeChoice({required this.survivorId, required this.absorbIds});
  final String survivorId;
  final List<String> absorbIds;
}

/// "Which of these should stay?"
///
/// Two decisions in one sheet, because they are one decision: the reader picks
/// the row that survives, and every other row they tick is folded into it. The
/// survivor is a radio and the rest are checkboxes so that is legible at a
/// glance — and a row cannot be both, which is the one combination that means
/// nothing.
///
/// Everything is ticked by default *except* nothing: the reader came here
/// saying these are duplicates, and unticking is the rarer correction. What is
/// not defaulted is the survivor — that is the judgement call, so it starts on
/// the row they tapped and invites a change.
class _MergeSheet extends StatefulWidget {
  const _MergeSheet({required this.works, this.initialSurvivorId});

  final List<Map<String, dynamic>> works;
  final String? initialSurvivorId;

  @override
  State<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends State<_MergeSheet> {
  late String _survivorId;
  late Set<String> _absorb;

  @override
  void initState() {
    super.initState();
    _survivorId = widget.initialSurvivorId ?? widget.works.first['id'] as String;
    _absorb = {
      for (final w in widget.works)
        if (w['id'] != _survivorId) w['id'] as String,
    };
  }

  void _pickSurvivor(String id) {
    setState(() {
      _survivorId = id;
      // A row cannot be absorbed into itself, and the one it displaces goes
      // back on the list rather than silently dropping out of the merge.
      _absorb = {
        for (final w in widget.works)
          if (w['id'] != id) w['id'] as String,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.mergeSheetTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(l10n.mergeSheetHelp, style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final work in widget.works)
                    _MergeRow(
                      work: work,
                      isSurvivor: work['id'] == _survivorId,
                      absorbed: _absorb.contains(work['id']),
                      onKeep: () => _pickSurvivor(work['id'] as String),
                      onToggle: (on) => setState(() {
                        final id = work['id'] as String;
                        on ? _absorb.add(id) : _absorb.remove(id);
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _absorb.isEmpty
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(_MergeChoice(survivorId: _survivorId, absorbIds: _absorb.toList())),
                style: FilledButton.styleFrom(backgroundColor: AppColors.oxblood),
                child: Text(l10n.mergeSheetConfirm(_absorb.length)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.bookCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MergeRow extends StatelessWidget {
  const _MergeRow({
    required this.work,
    required this.isSurvivor,
    required this.absorbed,
    required this.onKeep,
    required this.onToggle,
  });

  final Map<String, dynamic> work;
  final bool isSurvivor;
  final bool absorbed;
  final VoidCallback onKeep;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final year = work['first_publish_year'];
    final meta = [?author, if (year != null) '$year'].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: isSurvivor ? AppColors.oxblood : AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (meta.isNotEmpty)
                      Text(meta, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              if (isSurvivor)
                Text(
                  l10n.mergeKeepThis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.oxblood,
                  ),
                )
              else ...[
                TextButton(
                  onPressed: onKeep,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n.mergeKeepInstead, style: const TextStyle(fontSize: 11)),
                ),
                Checkbox(
                  value: absorbed,
                  onChanged: (v) => onToggle(v ?? false),
                  activeColor: AppColors.oxblood,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
