import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/image_crop.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import '../providers/catalog_providers.dart';

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
  const AddEditBookScreen({super.key, this.workId});

  final String? workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (workId == null) {
      return Scaffold(backgroundColor: AppColors.paper, body: SafeArea(child: _BookForm()));
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
  const _BookForm({this.initialWork});

  final Map<String, dynamic>? initialWork;

  @override
  ConsumerState<_BookForm> createState() => _BookFormState();
}

class _BookFormState extends ConsumerState<_BookForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _language;
  late final TextEditingController _series;
  late final TextEditingController _seriesNumber;
  late final TextEditingController _pages;
  late final TextEditingController _isbn;
  late final TextEditingController _customGenres;
  late String _format;
  late final Set<String> _selectedGenres;
  // Authors and publisher are chosen via the dedicated picker pages, so each
  // carries its canonical catalog id (falling back to name for legacy data).
  final List<Map<String, dynamic>> _authors = [];
  Map<String, dynamic>? _publisher;
  // The edition's front and back cover URLs — set from an ISBN scan, an existing
  // edition (edit mode), or a photo the user captures right here.
  String? _coverUrl;
  String? _backCoverUrl;
  // Snapshot at load, so on edit we only PATCH the edition for a side the user
  // actually changed — and never null an existing cover out.
  String? _initialCoverUrl;
  String? _initialBackCoverUrl;
  bool _uploadingFront = false;
  bool _uploadingBack = false;
  bool _saving = false;
  bool _scanning = false;

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
    final publisher = edition?['publisher'] as Map?;
    if (publisher != null) _publisher = Map<String, dynamic>.from(publisher);
    _title = TextEditingController(text: work?['title'] as String? ?? '');
    // Live cover preview (S7b): the typeset cover mirrors the title/author as
    // they're typed, so a keystroke redraws it.
    _title.addListener(_onCoverChanged);
    _language = TextEditingController(text: work?['language'] as String? ?? '');
    _series = TextEditingController(text: (edition?['series'] as Map?)?['name'] as String? ?? '');
    _seriesNumber =
        TextEditingController(text: edition?['series_number']?.toString() ?? '');
    _pages = TextEditingController(text: edition?['page_count']?.toString() ?? '');
    _isbn = TextEditingController(text: edition?['isbn'] as String? ?? '');
    _format = edition?['format'] as String? ?? _formats.first;
    _coverUrl = edition?['cover_url'] as String?;
    _backCoverUrl = edition?['back_cover_url'] as String?;
    _initialCoverUrl = _coverUrl;
    _initialBackCoverUrl = _backCoverUrl;
    _selectedGenres = genreNames.where(_commonGenres.contains).toSet();
    _customGenres =
        TextEditingController(text: genreNames.where((g) => !_commonGenres.contains(g)).join(', '));
  }

  void _onCoverChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.removeListener(_onCoverChanged);
    for (final c in [
      _title,
      _language,
      _series,
      _seriesNumber,
      _pages,
      _isbn,
      _customGenres,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _splitNames(String raw) =>
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _pickAuthor() async {
    final result = await context.push<Map<String, dynamic>>(Routes.authorPicker);
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

  void _applyScannedWork(Map<String, dynamic> work) {
    final editions = work['editions'] as List?;
    final edition =
        editions != null && editions.isNotEmpty ? editions.first as Map<String, dynamic> : null;
    final genreNames =
        (work['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ?? <String>{};

    setState(() {
      _title.text = work['title'] as String? ?? _title.text;
      final language = work['language'] as String?;
      if (language != null && language.isNotEmpty) _language.text = language;

      _authors
        ..clear()
        ..addAll(
          (work['authors'] as List?)?.map((a) => Map<String, dynamic>.from(a as Map)) ??
              const <Map<String, dynamic>>[],
        );

      if (edition != null) {
        final series = (edition['series'] as Map?)?['name'] as String?;
        if (series != null && series.isNotEmpty) _series.text = series;
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
        ..addAll(genreNames.where(_commonGenres.contains));
      final custom = genreNames.where((g) => !_commonGenres.contains(g)).join(', ');
      if (custom.isNotEmpty) _customGenres.text = custom;
    });
  }

  /// Photograph (or pick) a cover for [back]=false front / true back, crop it to
  /// 2:3, upload it, and hold the URL until save. New books have no edition id
  /// yet, so the image lands under a fresh `covers/<uuid>.jpg` path.
  Future<void> _captureCover({required bool back}) async {
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final url = await pickCropUploadImage(
        source: source,
        folder: 'covers',
        ratio: CropRatio.cover,
      );
      if (mounted && url != null) {
        setState(() => back ? _backCoverUrl = url : _coverUrl = url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.coverUploadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => back ? _uploadingBack = false : _uploadingFront = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final genres = {..._selectedGenres, ..._splitNames(_customGenres.text)}.toList();
    final publisherId = _publisher?['id'] as String?;
    final payload = {
      'title': _title.text.trim(),
      'language': _language.text.trim().isEmpty ? null : _language.text.trim(),
      // Ids for picker-chosen authors; names only for anything without one.
      'author_ids': [
        for (final a in _authors)
          if (a['id'] != null) a['id'] as String,
      ],
      'author_names': [
        for (final a in _authors)
          if (a['id'] == null) a['name'] as String,
      ],
      'genre_names': genres,
      'publisher_id': publisherId,
      'publisher_name':
          publisherId == null ? (_publisher?['name'] as String?) : null,
      'series_name': _series.text.trim().isEmpty ? null : _series.text.trim(),
      'series_number': int.tryParse(_seriesNumber.text.trim()),
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
      'page_count': int.tryParse(_pages.text.trim()),
      'format': _format,
      // On create these land on the new edition. Never null a cover out on edit.
      if (_coverUrl != null) 'cover_url': _coverUrl,
      if (_backCoverUrl != null) 'back_cover_url': _backCoverUrl,
    };

    try {
      final api = ref.read(apiClientProvider);
      final workId = widget.initialWork?['id'] as String?;
      if (workId == null) {
        await api.createWork(payload);
      } else {
        await api.updateWork(workId, payload);
        // Covers live on the Edition, not the Work — patch them separately, and
        // only the side the user actually changed.
        final editionId = _edition?['id'] as String?;
        if (editionId != null) {
          final edPatch = <String, dynamic>{
            if (_coverUrl != null && _coverUrl != _initialCoverUrl) 'cover_url': _coverUrl,
            if (_backCoverUrl != null && _backCoverUrl != _initialBackCoverUrl)
              'back_cover_url': _backCoverUrl,
          };
          if (edPatch.isNotEmpty) await api.updateEdition(editionId, edPatch);
        }
        ref.invalidate(workProvider(workId));
      }
      if (mounted) context.pop();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEdit = widget.initialWork != null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
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
          SizedBox(height: 16),
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
                onTap: () => _captureCover(back: false),
              ),
              SizedBox(width: 12),
              _CoverSlot(
                label: l10n.formCoverBack,
                imageUrl: _backCoverUrl,
                busy: _uploadingBack,
                onTap: () => _captureCover(back: true),
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
          SizedBox(height: 16),
          _Field(
            label: l10n.formFieldTitle,
            controller: _title,
            validator: (v) => (v == null || v.trim().isEmpty) ? l10n.formTitleRequired : null,
          ),
          SizedBox(height: 10),
          _AuthorField(
            authors: _authors,
            onAdd: _pickAuthor,
            onRemove: (author) => setState(() => _authors.remove(author)),
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
                  helper: l10n.formSeriesHelp,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: _Field(
                  label: l10n.formFieldBookNumber,
                  controller: _seriesNumber,
                  keyboardType: TextInputType.number,
                  helper: l10n.formBookNumberHelp,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldLanguage, controller: _language)),
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
          _PickerButtonField(
            label: l10n.formFieldPublisher,
            value: _publisher?['name'] as String?,
            placeholder: l10n.formPublisherChoose,
            onTap: _pickPublisher,
            onClear: _publisher == null ? null : () => setState(() => _publisher = null),
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
          SizedBox(height: 14),
          Text(
            l10n.formFieldGenres,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final genre in _commonGenres)
                FilterChip(
                  label: Text(genre, style: TextStyle(fontSize: 11)),
                  selected: _selectedGenres.contains(genre),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _selectedGenres.add(genre);
                    } else {
                      _selectedGenres.remove(genre);
                    }
                  }),
                  selectedColor: AppColors.oxblood,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                    color: _selectedGenres.contains(genre) ? AppColors.paper : AppColors.ink,
                  ),
                  side: BorderSide(color: AppColors.line),
                ),
            ],
          ),
          SizedBox(height: 8),
          _Field(label: '+ ${l10n.formFieldGenres}', controller: _customGenres),
          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                    )
                  : Text(l10n.formSave),
            ),
          ),
        ],
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
  });

  final String label;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;
  final String? title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    const w = 46.0;
    const h = 69.0; // 2:3
    Widget preview;
    if (imageUrl != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(imageUrl!, width: w, height: h, fit: BoxFit.cover),
      );
    } else if (title != null) {
      preview = TypesetCover(title: title!, author: author, width: w, height: h);
    } else {
      preview = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(Icons.add_a_photo_outlined, size: 18, color: AppColors.inkSoft),
      );
    }
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
    required this.onRemove,
  });

  final List<Map<String, dynamic>> authors;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldAuthor, style: _fieldLabelStyle),
        SizedBox(height: 4),
        if (authors.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final author in authors)
                  Chip(
                    label: Text(author['name'] as String, style: TextStyle(fontSize: 12)),
                    onDeleted: () => onRemove(author),
                    backgroundColor: AppColors.goldSoft,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.person_add_alt, size: 18),
            label: Text(authors.isEmpty ? l10n.formAuthorAddButton : l10n.formAuthorAddAnother),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 2),
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
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  /// Optional one-line hint under the field, for the fields users hesitate on
  /// (series, book number, …).
  final String? helper;

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
        SizedBox(height: 4),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
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
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              items: [
                for (final option in options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ),
        ),
      ],
    );
  }
}
