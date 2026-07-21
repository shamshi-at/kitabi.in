import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/image_crop.dart';
import '../../../core/languages.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import '../catalog_image_upload.dart';
import '../providers/catalog_providers.dart';
import '../work_forms.dart';
import '../../../core/widgets/net_image.dart';

/// S4d — form to add a new catalog Work + first Edition, or edit an existing one:
/// title, authors, publisher, genres, and edition-level fields (ISBN, format,
/// cover). Contributions flow through the API when online (catalog is
/// server-authoritative, CLAUDE.md rule 2).
const _formats = ['Paperback', 'Hardcover', 'eBook', 'Audiobook'];

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
    this.initialIsbn,
    this.initialTitle,
    this.initialOriginal,
    this.returnCreated = false,
  });

  final String? workId;

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
          loading: () => Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (body) => _BookForm(initialWork: body),
        ),
      ),
    );
  }
}

class _BookForm extends ConsumerStatefulWidget {
  const _BookForm({
    this.initialWork,
    this.initialIsbn,
    this.initialTitle,
    this.initialOriginal,
    this.returnCreated = false,
  });

  final Map<String, dynamic>? initialWork;
  final String? initialIsbn;
  final String? initialTitle;
  final Map<String, dynamic>? initialOriginal;
  final bool returnCreated;

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _series;
  late final TextEditingController _seriesNumber;
  late final TextEditingController _pages;
  late final TextEditingController _isbn;
  // Genres the reader added themselves — chips on the same row as the
  // suggestions (they used to live in a free-text field underneath).
  final List<String> _customGenreList = [];
  late String _format;
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
  String? _initialSeriesName;
  int? _initialSeriesNumber;
  bool _uploadingFront = false;
  bool _uploadingBack = false;
  bool _saving = false;
  bool _scanning = false;
  bool _extracting = false;

  // Duplicate detection (create mode only): as the title is typed, a debounced
  // trigram search quietly surfaces near-matches already in the catalog.
  List<Map<String, dynamic>> _similar = const [];
  bool _similarDismissed = false;
  Timer? _similarDebounce;
  int _similarSeq = 0;

  Map<String, dynamic>? get _edition {
    final editions = widget.initialWork?['editions'] as List?;
    return editions != null && editions.isNotEmpty ? editions.first as Map<String, dynamic> : null;
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
    _title = TextEditingController(
      text: work?['title'] as String? ?? widget.initialTitle ?? '',
    );
    // Live cover preview (S7b): the typeset cover mirrors the title/author as
    // they're typed, so a keystroke redraws it.
    _title.addListener(_onCoverChanged);
    // Duplicate check rides the same field — but only when creating (nagging
    // about "duplicates" while editing the book itself would be noise).
    if (work == null) _title.addListener(_onTitleChangedForSimilar);
    _description = TextEditingController(text: work?['description'] as String? ?? '');
    _language = work?['language'] as String?;
    _series = TextEditingController(text: (edition?['series'] as Map?)?['name'] as String? ?? '');
    _hasSeries = (edition?['series'] as Map?)?['name'] != null;
    _seriesNumber =
        TextEditingController(text: edition?['series_number']?.toString() ?? '');
    _pages = TextEditingController(text: edition?['page_count']?.toString() ?? '');
    _isbn = TextEditingController(
      text: edition?['isbn'] as String? ?? widget.initialIsbn ?? '',
    );
    _format = edition?['format'] as String? ?? _formats.first;
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
    _initialSeriesName = (edition?['series'] as Map?)?['name'] as String?;
    _initialSeriesNumber = edition?['series_number'] as int?;
    // A genre that isn't one of ours is the reader's own — it must come back
    // as a selected chip on edit, not vanish for being off-list.
    _selectedGenres = {...genreNames};
    _customGenreList.addAll(genreNames.where((g) => !_commonGenres.contains(g)));
  }

  void _onCoverChanged() {
    if (mounted) setState(() {});
  }

  /// Debounced duplicate lookup while the title is typed. Quiet by design:
  /// nothing blocks, nothing pops — matches slide in below the field and a
  /// dismiss hides them for the rest of this form.
  void _onTitleChangedForSimilar() {
    if (_similarDismissed) return;
    _similarDebounce?.cancel();
    final q = _title.text.trim();
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
      setState(() => _similar = results);
    } catch (_) {
      // Best-effort suggestion — never surface an error for it.
    }
  }

  @override
  void dispose() {
    _similarDebounce?.cancel();
    _title.removeListener(_onCoverChanged);
    for (final c in [
      _title,
      _description,
      _series,
      _seriesNumber,
      _pages,
      _isbn,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _splitNames(String raw) =>
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

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
    final picked = await context.push<Map<String, dynamic>>(Routes.workPicker, extra: {
      'forOriginal': true,
      if (widget.initialWork != null) 'excludeWorkId': widget.initialWork!['id'] as String?,
      'seed': {
        'authors': [for (final a in _authors) Map<String, dynamic>.from(a)],
        'form': _form,
        'genre_names': _selectedGenres.toList(),
      },
    });
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

  /// M1 — the fork. A similar-title match means one of four things, and only
  /// the reader knows which: their copy of that same book (→ shelf), a
  /// different printing (→ add edition), a translation (→ link as original
  /// and keep typing), or a genuinely different book (→ dismiss the match).
  Future<void> _openFork(Map<String, dynamic> work) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ForkSheet(work: work),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'shelf':
        await _forkAddToShelf(work);
      case 'edition':
        context.push(Routes.catalogAddEdition, extra: {
          'workId': work['id'] as String,
          'title': work['title'] as String?,
        });
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
        setState(() => _similarDismissed = true);
    }
  }

  /// The fork's "I own this one" — same shape as the scanner's Add: cache the
  /// catalog data, create the entry (idempotent), open the book.
  Future<void> _forkAddToShelf(Map<String, dynamic> summary) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final work = await ref.read(apiClientProvider).getWork(summary['id'] as String);
      final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final edition = editions.firstOrNull;
      if (edition == null) return;
      final editionId = edition['id'] as String;
      final repo = await ref.read(libraryRepositoryProvider.future);
      final existing = await repo.getByEditionId(editionId);
      if (existing == null) {
        await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
        await repo.add(editionId: editionId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.forkOwnThisAdded)),
      );
      context.pushReplacement(
        Routes.bookDetailPath(work['id'] as String, editionId),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    }
  }

  /// Name a type the suggestions don't cover. The server folds a variant onto
  /// its canonical spelling ("novel" → "Novel"), so typing one that's already
  /// a chip just selects that chip rather than forking the facet.
  Future<void> _pickCustomForm() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(
      text: _form != null && !kWorkForms.contains(_form) ? _form : '',
    );
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(l10n.formTypeOtherTitle, style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.formTypeOtherHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (typed == null || !mounted) return;
    final cleaned = typed.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return;
    // Mirror the server's fold so the chip highlights immediately instead of
    // waiting for a round-trip to tell us "novel" was really "Novel".
    final canonical = kWorkForms.firstWhere(
      (f) => f.toLowerCase() == cleaned.toLowerCase(),
      orElse: () => cleaned,
    );
    setState(() => _form = canonical);
  }

  /// Add a genre the suggestions don't cover — the same door, and the same
  /// look, as Type's "＋ Other" (owner request, 17 Jul 2026). The server
  /// get-or-creates genres case-insensitively, so typing one that's already a
  /// chip just selects that chip instead of forking it.
  Future<void> _pickCustomGenre() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(l10n.formGenreOtherTitle, style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.formGenreOtherHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (typed == null || !mounted) return;
    // One dialog can add several ("Sufi, Devotional") — the old free-text
    // field was comma-separated, so keep honouring that here.
    setState(() {
      for (final raw in _splitNames(typed)) {
        final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ');
        if (cleaned.isEmpty) continue;
        // Fold onto an existing chip rather than adding a near-duplicate.
        final existing = [..._commonGenres, ..._customGenreList].firstWhere(
          (g) => g.toLowerCase() == cleaned.toLowerCase(),
          orElse: () => '',
        );
        final genre = existing.isEmpty ? cleaned : existing;
        if (existing.isEmpty) _customGenreList.add(genre);
        _selectedGenres.add(genre);
      }
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
  Future<void> _fillFromPhotos() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _extracting = true);
    try {
      final fields = await ref.read(apiClientProvider).extractFromCovers(
            frontUrl: _isOwnUpload(_coverUrl) ? _coverUrl : null,
            backUrl: _isOwnUpload(_backCoverUrl) ? _backCoverUrl : null,
          );
      if (!mounted) return;
      if (!_applyExtracted(fields)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractNothing)));
      }
    } on DioException catch (err) {
      final data = err.response?.data;
      final code = data is Map ? data['code'] : null;
      messenger.showSnackBar(SnackBar(
        content: Text(
          code == 'extraction_disabled' ? l10n.formExtractUnavailable : l10n.formExtractFailed,
        ),
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractFailed)));
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
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
        _authors.addAll([for (final name in authors) {'name': name}]);
        filled = true;
      }
      final publisher = fields['publisher'] as String?;
      if (publisher != null && _publisher == null) {
        _publisher = {'name': publisher};
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

  /// A one-line, human-ish reason from an exception for a diagnostic snackbar —
  /// the Supabase Storage message ("bucket not found", "new row violates
  /// policy"), a Dio status, or the exception's own string.
  String _briefError(Object err) {
    final s = err.toString();
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  void _applyScannedWork(Map<String, dynamic> work) {
    final editions = work['editions'] as List?;
    final edition =
        editions != null && editions.isNotEmpty ? editions.first as Map<String, dynamic> : null;
    final genreNames =
        (work['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ?? <String>{};

    setState(() {
      _prefillSource = 'scan';
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
        if (format != null && _formats.contains(format)) _format = format;
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
  Future<void> _onCoverTap({required bool back}) async {
    final current = back ? _backCoverUrl : _coverUrl;
    final action = await showCoverActionSheet(context, hasImage: current != null);
    if (action == null || !mounted) return;

    if (action == CoverAction.remove) {
      setState(() => back ? _backCoverUrl = null : _coverUrl = null);
      return;
    }

    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final String? url;
      switch (action) {
        case CoverAction.camera:
          url = await pickCropUploadImage(
              source: ImageSource.camera, folder: 'covers', ratio: CropRatio.cover);
        case CoverAction.gallery:
          url = await pickCropUploadImage(
              source: ImageSource.gallery, folder: 'covers', ratio: CropRatio.cover);
        case CoverAction.adjust:
          url = await recropUploadImage(url: current!, folder: 'covers', ratio: CropRatio.cover);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          // Include a concise real reason — cover upload/crop couldn't be tested
          // on a real device before shipping, so surface what actually failed.
          content: Text('$base\n${_briefError(err)}'),
        ));
      }
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
      'publisher_name':
          publisherId == null ? (_publisher?['name'] as String?) : null,
      'series_name': _hasSeries && _series.text.trim().isNotEmpty ? _series.text.trim() : null,
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
          final seriesName =
              _hasSeries && _series.text.trim().isNotEmpty ? _series.text.trim() : null;
          final seriesNumber = _hasSeries ? int.tryParse(_seriesNumber.text.trim()) : null;
          final publisherName = _publisher?['name'] as String?;
          final edPatch = <String, dynamic>{
            if (_coverUrl != null && _coverUrl != _initialCoverUrl) 'cover_url': _coverUrl,
            if (_backCoverUrl != null && _backCoverUrl != _initialBackCoverUrl)
              'back_cover_url': _backCoverUrl,
            if (pageCount != null && pageCount != _initialPageCount) 'page_count': pageCount,
            if (isbn != null && isbn != _initialIsbn) 'isbn': isbn,
            if (_format != _initialFormat) 'format': _format,
            if (seriesName != null && seriesName != _initialSeriesName) 'series_name': seriesName,
            if (seriesNumber != null && seriesNumber != _initialSeriesNumber)
              'series_number': seriesNumber,
            // Publisher rides as an id when picked from the catalog, else by
            // name for the server to get-or-create — same shape as create.
            if (publisherId != null && publisherId != _initialPublisherId)
              'publisher_id': publisherId,
            if (publisherId == null && publisherName != null && _initialPublisherId != null)
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.editPendingApproval),
              duration: const Duration(seconds: 5),
            ));
          }
          context.pop();
        }
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (created != null && mounted) {
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
      _format = _formats.first;
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
    });
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
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$err')));
              }
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
                        disabledForegroundColor:
                            phase == 'added' ? AppColors.moss : null,
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
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.ink),
                onPressed: () => context.pop(),
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
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
              message:
                  _prefillSource == 'scan' ? l10n.formPrefillScan : l10n.formPrefillPhotos,
              onDismiss: () => setState(() => _prefillSource = null),
            ),
          ],
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverSlot(
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
              _CoverSlot(
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
                onPressed: _extracting ? null : _fillFromPhotos,
                icon: _extracting
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.oxblood,
                        ),
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
          _Field(
            label: l10n.formFieldTitle,
            controller: _title,
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
              onDismiss: () => setState(() => _similarDismissed = true),
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
            languages: (ref.watch(meProvider).valueOrNull?['preferred_languages'] as List?)
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
          // Type and genre are primary — they power the library filter — as
          // one-tap chip rows with every option visible, no typing. Type is
          // the single-valued literary form (Novel, Short stories, Poetry…);
          // tapping the selected chip again clears it.
          SizedBox(height: 12),
          Text(l10n.formFieldType, style: _fieldLabelStyle),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // The suggestions, plus the reader's own type when it isn't one
              // of them — a custom form must still show as a selected chip on
              // edit, not vanish because it's off-list.
              for (final form in [
                ...kWorkForms,
                if (_form != null && !kWorkForms.contains(_form)) _form!,
              ])
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
                  side: BorderSide(
                    color: _form == form ? AppColors.oxblood : AppColors.line,
                  ),
                ),
              // Our list will never cover every kind of book — a novella, a
              // screenplay, a devotional. Naming one is a tap away rather than
              // a dead end (owner report, 16 Jul 2026).
              ActionChip(
                onPressed: _pickCustomForm,
                label: Text(l10n.formTypeOther, style: TextStyle(fontSize: 12)),
                backgroundColor: AppColors.card,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.oxblood,
                ),
                side: BorderSide(color: AppColors.gold),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(l10n.formFieldGenrePrimary, style: _fieldLabelStyle),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // The suggestions, plus any genre the reader added themselves —
              // their own genres are chips too, not a separate text field
              // hiding underneath (owner request, 17 Jul 2026: Type's "＋
              // Other" is the pattern both rows should share).
              for (final genre in [..._commonGenres, ..._customGenreList])
                FilterChip(
                  label: Text(genre, style: TextStyle(fontSize: 12)),
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
                    color:
                        _selectedGenres.contains(genre) ? AppColors.oxblood : AppColors.line,
                  ),
                ),
              ActionChip(
                onPressed: _pickCustomGenre,
                label: Text(l10n.formTypeOther, style: TextStyle(fontSize: 12)),
                backgroundColor: AppColors.card,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.oxblood,
                ),
                side: BorderSide(color: AppColors.gold),
              ),
            ],
          ),
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
                                style:
                                    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
                                      fontSize: 11.5, color: AppColors.inkSoft, height: 1.3),
                                ),
                                SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 14,
                                      child: _Field(
                                        label: l10n.formFieldSeries,
                                        controller: _series,
                                        fillColor: AppColors.card,
                                        helper: l10n.formSeriesNameHelp,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      flex: 9,
                                      child: _Field(
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
                              child: _PickerButtonField(
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
                              child: _Field(
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
                              child: _IsbnScanField(
                                controller: _isbn,
                                onScan: _scanIsbn,
                                scanning: _scanning,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              flex: 10,
                              child: _DropdownField(
                                label: l10n.formFieldFormat,
                                value: _format,
                                options: _formats,
                                onChanged: (v) => setState(() => _format = v),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        _Field(
                          label: l10n.formFieldDescription,
                          controller: _description,
                          maxLines: 4,
                          helper: l10n.formDescriptionHelp,
                          expandable: true,
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
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: form),
            _SaveBar(
              saving: _saving,
              onSave: _save,
              label: l10n.formSave,
              hint: l10n.formSaveHint,
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
    );
  }
}

/// The sticky save bar under the scrolling form — the primary action is never
/// below the fold, and the one-line note spells out that saving publishes to
/// the shared catalog.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.saving,
    required this.onSave,
    required this.label,
    required this.hint,
  });

  final bool saving;
  final VoidCallback onSave;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                  )
                : Text(label),
          ),
          SizedBox(height: 5),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// The dismissible gold provenance banner — shown after a barcode scan or a
/// cover-photo read prefilled the form, so prefilled data is announced.
class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  // The gold-on-goldSoft ink the status pills already use for "To read".
  static const _ink = Color(0xFF8F681E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
      ),
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
  });

  final List<Map<String, dynamic>> works;
  final VoidCallback onDismiss;
  final void Function(Map<String, dynamic> work) onPick;

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
            l10n.formSimilarHelp,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.25),
          ),
          SizedBox(height: 8),
          for (final work in works) _SimilarWorkRow(work: work, onTap: () => onPick(work)),
        ],
      ),
    );
  }
}

class _SimilarWorkRow extends StatelessWidget {
  const _SimilarWorkRow({required this.work, required this.onTap});

  final Map<String, dynamic> work;
  final VoidCallback onTap;

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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

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
                                gradient: LinearGradient(colors: [
                                  AppColors.gold.withValues(alpha: 0),
                                  AppColors.gold,
                                  AppColors.gold.withValues(alpha: 0),
                                ]),
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
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 18, color: AppColors.ink),
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

// Runtime (not const): AppColors.inkSoft resolves per active theme.
TextStyle get _fieldLabelStyle => TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: AppColors.inkSoft,
      fontWeight: FontWeight.w600,
    );

/// A single labelled, tappable cover thumbnail (front or back) on the add-book
/// form. Shows the captured photo when there is one; the front otherwise falls
/// back to the live typeset preview, the back to an "add a photo" placeholder.
/// The camera badge signals it's tappable to shoot/replace.
class _CoverSlot extends StatelessWidget {
  const _CoverSlot({
    required this.label,
    required this.imageUrl,
    required this.busy,
    required this.onTap,
    this.title,
    this.author,
    this.width = 46,
    this.height = 69, // 2:3
  });

  final String label;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;
  final String? title;
  final String? author;

  /// The front slot renders larger (the mockup's 64×96 hero slot); the back
  /// stays a small companion tile.
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    // What the slot shows without (or instead of) a photo — the front falls
    // back to the live typeset preview, the back to an "add a photo" tile.
    Widget fallback() => title != null
        ? TypesetCover(title: title!, author: author, width: w, height: h)
        : Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(Icons.add_a_photo_outlined, size: 18, color: AppColors.inkSoft),
          );
    final preview = imageUrl != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: netImage(
              imageUrl!,
              width: w,
              height: h,
              fit: BoxFit.cover,
              // A dead URL degrades to the typeset/placeholder tile, never a
              // broken-image error box.
              errorBuilder: (_, _, _) => fallback(),
            ),
          )
        : fallback();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        SizedBox(height: 4),
        GestureDetector(
          onTap: busy ? null : onTap,
          child: Stack(
            children: [
              preview,
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppColors.oxblood, shape: BoxShape.circle),
                  child: busy
                      ? SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.paper),
                        )
                      : Icon(Icons.photo_camera, size: 10, color: AppColors.paper),
                ),
              ),
            ],
          ),
        ),
      ],
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
        Text(l10n.formFieldAuthor, style: _fieldLabelStyle),
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

/// A labelled, tappable field that opens a picker page and shows the chosen
/// value (or a placeholder) — used for the publisher field on the add-book
/// form. A clear button removes the current selection.
class _PickerButtonField extends StatelessWidget {
  const _PickerButtonField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? value! : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasValue ? AppColors.ink : AppColors.inkSoft,
                    ),
                  ),
                ),
                if (hasValue && onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.helper,
    this.fillColor,
    this.maxLines = 1,
    this.expandable = false,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  /// Optional one-line hint under the field, for the fields users hesitate on
  /// (series, book number, …).
  final String? helper;

  /// Override the fill — e.g. `card` when the field sits inside a `paperDeep`
  /// well (the series group) so it still reads as an input.
  final Color? fillColor;

  /// Long-text fields (description) get an expand affordance that opens the
  /// same controller in a full-screen editor.
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (expandable)
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _FullScreenTextEditor(
                      title: label,
                      controller: controller,
                      hint: helper,
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full, size: 12, color: AppColors.oxblood),
                      SizedBox(width: 4),
                      Text(
                        l10n.formFieldExpand,
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
          ],
        ),
        SizedBox(height: 4),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fillColor ?? AppColors.card,
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
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Text(
              helper!,
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
            ),
          ),
      ],
    );
  }
}

/// Full-screen editor for long text (the description blurb) — shares the
/// form field's controller, so everything typed here is already in the form
/// when it pops; Done just closes it.
class _FullScreenTextEditor extends StatelessWidget {
  const _FullScreenTextEditor({required this.title, required this.controller, this.hint});

  final String title;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.formEditorDone,
              style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            autofocus: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 14, color: AppColors.ink, height: 1.5),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// ISBN field with a built-in Scan button (S7b). Scanning is the primary path —
/// the camera fills in the ISBN (and the rest of the book) — but the field stays
/// fully editable so a user can correct or type it by hand.
class _IsbnScanField extends StatelessWidget {
  const _IsbnScanField({
    required this.controller,
    required this.onScan,
    required this.scanning,
  });

  final TextEditingController controller;
  final VoidCallback onScan;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldIsbn, style: _fieldLabelStyle),
        SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              onPressed: scanning ? null : onScan,
              tooltip: l10n.formIsbnScan,
              icon: scanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.oxblood),
                    )
                  : Icon(Icons.qr_code_scanner, size: 20, color: AppColors.oxblood),
            ),
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
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 2),
          child: Text(
            l10n.formIsbnScanHelp,
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

/// A non-null option field (e.g. Format). Tapping it opens a themed bottom-sheet
/// picker instead of the platform Material dropdown, and its box matches the
/// height of the text fields it sits beside.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SelectField(
      label: label,
      displayValue: value,
      isPlaceholder: false,
      onTap: () => _openSelectSheet(
        context,
        title: l10n.pickerChoose(label.toLowerCase()),
        options: [for (final o in options) _SelectOption(o, o)],
        current: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// The shared look for every "tap to choose" field on the form (Format,
/// Language, and the publisher picker's cousin): a labelled box, matching the
/// text fields' height, with a chevron — never the raw Material dropdown.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.displayValue,
    required this.isPlaceholder,
    required this.onTap,
    this.note,
  });

  final String label;
  final String displayValue;
  final bool isPlaceholder;
  final VoidCallback onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _fieldLabelStyle),
        SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            // vertical: 10 matches _Field's dense TextFormField height, so a
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

/// One row in the option-picker sheet. [value] is null only for a "not set"
/// entry (Language), which renders subdued.
class _SelectOption {
  const _SelectOption(this.value, this.label, {this.subdued = false});
  final String? value;
  final String label;
  final bool subdued;
}

class _SelectResult {
  const _SelectResult(this.value);
  final String? value;
}

/// Opens the Reading Room option-picker sheet. Fires [onChanged] only when the
/// user actually picks something; a dismiss (scrim tap / swipe down) leaves the
/// value untouched — which is how "not set" (a real null pick) stays distinct
/// from cancelling.
Future<void> _openSelectSheet(
  BuildContext context, {
  required String title,
  required List<_SelectOption> options,
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
    builder: (context) => SafeArea(
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
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final opt in options)
                  ListTile(
                    dense: true,
                    title: Text(
                      opt.label,
                      style: TextStyle(
                        color: opt.subdued ? AppColors.inkSoft : AppColors.ink,
                        fontWeight: opt.value == current ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: opt.value == current
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
  if (result != null) onChanged(result.value);
}

/// The language picker — a nullable dropdown (language is optional) with a
/// leading "not set" item. Lists the reader's [languages] (their profile
/// preferences; falls back to all of [kLanguages] if none are set), and always
/// keeps the current value even if it's outside that list, so editing an old
/// book never drops its language. A [note] points the reader to their profile.
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
    final base = languages.isNotEmpty ? languages : kLanguages;
    final options = [
      ...base,
      if (value != null && !base.contains(value)) value!,
    ];
    return _SelectField(
      label: label,
      displayValue: value ?? unsetLabel,
      isPlaceholder: value == null,
      note: note,
      onTap: () => _openSelectSheet(
        context,
        title: l10n.pickerChoose(label.toLowerCase()),
        current: value,
        options: [
          _SelectOption(null, unsetLabel, subdued: true),
          for (final option in options) _SelectOption(option, option),
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
          Text(l10n.formFieldTranslatedFrom, style: _fieldLabelStyle),
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
    final subtitle = [
      ?language,
      if (year != null) '$year',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldTranslatedFrom, style: _fieldLabelStyle),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: AppColors.gold, width: 3),
              top: BorderSide(color: AppColors.line),
              right: BorderSide(color: AppColors.line),
              bottom: BorderSide(color: AppColors.line),
            ),
          ),
          child: Row(
            children: [
              TypesetCover(
                title: original['title'] as String? ?? '',
                author: authors.isNotEmpty ? authors.first['name'] as String? : null,
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
                      original['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                      ),
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
  const _TranslatorField({
    required this.translators,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> translators;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldTranslator, style: _fieldLabelStyle),
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
class _ForkSheet extends StatelessWidget {
  const _ForkSheet({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final edition = (work['editions'] as List?)?.cast<Map<String, dynamic>>().firstOrNull ??
        work['edition'] as Map<String, dynamic>?;
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final year = work['first_publish_year'];
    final meta = [
      ?author,
      if (year != null) '$year',
    ].join(' · ');

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
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                  top: BorderSide(color: AppColors.line),
                  right: BorderSide(color: AppColors.line),
                  bottom: BorderSide(color: AppColors.line),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
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
                  Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ],
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
            Text(
              l10n.forkAlreadyHere,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
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
                        Text(
                          meta,
                          style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
            option(
              value: 'shelf',
              title: l10n.forkOwnThis,
              accent: AppColors.moss,
            ),
            option(
              value: 'edition',
              title: l10n.forkDifferentPrinting,
              help: l10n.forkDifferentPrintingHelp,
              accent: AppColors.gold,
            ),
            option(
              value: 'translation',
              title: l10n.forkTranslation,
              help: l10n.forkTranslationHelp,
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
    );
  }
}
