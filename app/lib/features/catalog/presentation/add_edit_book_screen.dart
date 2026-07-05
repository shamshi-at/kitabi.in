import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
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
  late final TextEditingController _publisher;
  late final TextEditingController _pages;
  late final TextEditingController _isbn;
  late final TextEditingController _customGenres;
  late String _format;
  late final Set<String> _selectedGenres;
  // Authors are now a chip list (dropdown-cum-add-new) rather than a raw
  // comma-separated string, so each author is a discrete, de-duplicatable token.
  final List<String> _authorNames = [];
  bool _saving = false;

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

    _authorNames.addAll(
      (work?['authors'] as List?)?.map((a) => (a as Map)['name'] as String) ?? const <String>[],
    );
    _title = TextEditingController(text: work?['title'] as String? ?? '');
    // Live cover preview (S7b): the typeset cover mirrors the title/author as
    // they're typed, so a keystroke redraws it.
    _title.addListener(_onCoverChanged);
    _language = TextEditingController(text: work?['language'] as String? ?? '');
    _series = TextEditingController(text: (edition?['series'] as Map?)?['name'] as String? ?? '');
    _seriesNumber =
        TextEditingController(text: edition?['series_number']?.toString() ?? '');
    _publisher =
        TextEditingController(text: (edition?['publisher'] as Map?)?['name'] as String? ?? '');
    _pages = TextEditingController(text: edition?['page_count']?.toString() ?? '');
    _isbn = TextEditingController(text: edition?['isbn'] as String? ?? '');
    _format = edition?['format'] as String? ?? _formats.first;
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
      _publisher,
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

  void _addAuthor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_authorNames.any((a) => a.toLowerCase() == trimmed.toLowerCase())) return;
    setState(() => _authorNames.add(trimmed));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final genres = {..._selectedGenres, ..._splitNames(_customGenres.text)}.toList();
    final payload = {
      'title': _title.text.trim(),
      'language': _language.text.trim().isEmpty ? null : _language.text.trim(),
      'author_names': _authorNames,
      'genre_names': genres,
      'publisher_name': _publisher.text.trim().isEmpty ? null : _publisher.text.trim(),
      'series_name': _series.text.trim().isEmpty ? null : _series.text.trim(),
      'series_number': int.tryParse(_seriesNumber.text.trim()),
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
      'page_count': int.tryParse(_pages.text.trim()),
      'format': _format,
    };

    try {
      final api = ref.read(apiClientProvider);
      final workId = widget.initialWork?['id'] as String?;
      if (workId == null) {
        await api.createWork(payload);
      } else {
        await api.updateWork(workId, payload);
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
            children: [
              TypesetCover(
                title: _title.text.isEmpty ? '…' : _title.text,
                author: _authorNames.isEmpty ? null : _authorNames.first,
                coverUrl: _edition?['cover_url'] as String?,
                width: 40,
                height: 60,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.formCoverTypeset,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
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
            authors: _authorNames,
            onAdd: _addAuthor,
            onRemove: (name) => setState(() => _authorNames.remove(name)),
            fetch: (q) => ref.read(apiClientProvider).searchAuthors(q),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldSeries, controller: _series)),
              SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: _Field(
                  label: l10n.formFieldBookNumber,
                  controller: _seriesNumber,
                  keyboardType: TextInputType.number,
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
          _TypeaheadField(
            label: l10n.formFieldPublisher,
            controller: _publisher,
            hintText: l10n.formPublisherHint,
            fetch: (q) => ref.read(apiClientProvider).searchPublishers(q),
            onSelected: (_) {},
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldIsbn, controller: _isbn)),
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

/// Author input (S7b) — a "dropdown cum add new" chip field: existing catalog
/// authors are suggested as you type (so you pick the canonical one rather
/// than coining a near-duplicate), and anything you type is addable as-is.
/// Multiple authors are kept as discrete chips instead of a comma string.
class _AuthorField extends StatefulWidget {
  const _AuthorField({
    required this.authors,
    required this.onAdd,
    required this.onRemove,
    required this.fetch,
  });

  final List<String> authors;
  final void Function(String) onAdd;
  final void Function(String) onRemove;
  final Future<List<Map<String, dynamic>>> Function(String) fetch;

  @override
  State<_AuthorField> createState() => _AuthorFieldState();
}

class _AuthorFieldState extends State<_AuthorField> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldAuthor, style: _fieldLabelStyle),
        SizedBox(height: 4),
        if (widget.authors.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in widget.authors)
                  Chip(
                    label: Text(name, style: TextStyle(fontSize: 12)),
                    onDeleted: () => widget.onRemove(name),
                    backgroundColor: AppColors.goldSoft,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        _TypeaheadField(
          controller: _input,
          hintText: l10n.formAuthorAddHint,
          fetch: widget.fetch,
          clearOnSelect: true,
          onSelected: widget.onAdd,
        ),
      ],
    );
  }
}

/// A text field backed by server-side typeahead suggestions, with an
/// "Add …" affordance so the typed value is always usable even when nothing
/// matches — the reusable half of the dropdown-cum-add-new pattern.
class _TypeaheadField extends StatefulWidget {
  const _TypeaheadField({
    required this.controller,
    required this.fetch,
    required this.onSelected,
    this.label,
    this.hintText,
    this.clearOnSelect = false,
  });

  final TextEditingController controller;
  final Future<List<Map<String, dynamic>>> Function(String) fetch;
  final void Function(String) onSelected;
  final String? label;
  final String? hintText;

  /// Author mode: commit clears the input (ready for the next chip). Publisher
  /// mode (false): commit fills the field with the chosen value.
  final bool clearOnSelect;

  @override
  State<_TypeaheadField> createState() => _TypeaheadFieldState();
}

class _TypeaheadFieldState extends State<_TypeaheadField> {
  Timer? _debounce;
  List<String> _suggestions = [];
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim();
    setState(() => _query = query);
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(Duration(milliseconds: 250), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    try {
      final rows = await widget.fetch(query);
      if (!mounted || query != _query) return;
      setState(() => _suggestions = rows.map((r) => r['name'] as String).toList());
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    }
  }

  void _select(String name) {
    final value = name.trim();
    if (value.isEmpty) return;
    widget.onSelected(value);
    if (widget.clearOnSelect) {
      widget.controller.clear();
    } else {
      widget.controller.text = value;
    }
    setState(() {
      _suggestions = [];
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showAddNew =
        _query.isNotEmpty && !_suggestions.any((s) => s.toLowerCase() == _query.toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: _fieldLabelStyle),
          SizedBox(height: 4),
        ],
        TextField(
          controller: widget.controller,
          textInputAction: TextInputAction.done,
          onChanged: _onChanged,
          onSubmitted: _select,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            hintText: widget.hintText,
            hintStyle: TextStyle(fontSize: 13, color: AppColors.inkSoft),
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
        if (_suggestions.isNotEmpty || showAddNew)
          Container(
            margin: EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                for (final name in _suggestions)
                  InkWell(
                    onTap: () => _select(name),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Text(
                        name,
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                  ),
                if (showAddNew)
                  InkWell(
                    onTap: () => _select(_query),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 15, color: AppColors.oxblood),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.formAddNew(_query),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.oxblood,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.validator, this.keyboardType});

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
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
