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
      return const Scaffold(backgroundColor: AppColors.paper, body: SafeArea(child: _BookForm()));
    }
    final work = ref.watch(workProvider(workId!));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: work.when(
          loading: () => const Center(child: CircularProgressIndicator()),
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
  late final TextEditingController _authors;
  late final TextEditingController _language;
  late final TextEditingController _series;
  late final TextEditingController _seriesNumber;
  late final TextEditingController _publisher;
  late final TextEditingController _pages;
  late final TextEditingController _isbn;
  late final TextEditingController _customGenres;
  late String _format;
  late final Set<String> _selectedGenres;
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
    final authorNames =
        (work?['authors'] as List?)?.map((a) => (a as Map)['name'] as String).join(', ') ?? '';
    final genreNames =
        (work?['genres'] as List?)?.map((g) => (g as Map)['name'] as String).toSet() ?? <String>{};

    _title = TextEditingController(text: work?['title'] as String? ?? '');
    _authors = TextEditingController(text: authorNames);
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

  @override
  void dispose() {
    for (final c in [
      _title,
      _authors,
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

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final genres = {..._selectedGenres, ..._splitNames(_customGenres.text)}.toList();
    final payload = {
      'title': _title.text.trim(),
      'language': _language.text.trim().isEmpty ? null : _language.text.trim(),
      'author_names': _splitNames(_authors.text),
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
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
          const SizedBox(height: 16),
          Row(
            children: [
              TypesetCover(
                title: _title.text.isEmpty ? '…' : _title.text,
                author: _authors.text.isEmpty ? null : _authors.text.split(',').first,
                coverUrl: _edition?['cover_url'] as String?,
                width: 40,
                height: 60,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.formCoverTypeset,
                  style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Field(
            label: l10n.formFieldTitle,
            controller: _title,
            validator: (v) => (v == null || v.trim().isEmpty) ? l10n.formTitleRequired : null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldAuthor, controller: _authors)),
              const SizedBox(width: 8),
              Expanded(flex: 10, child: _Field(label: l10n.formFieldLanguage, controller: _language)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldSeries, controller: _series)),
              const SizedBox(width: 8),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 14,
                child: _Field(label: l10n.formFieldPublisher, controller: _publisher),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 14, child: _Field(label: l10n.formFieldIsbn, controller: _isbn)),
              const SizedBox(width: 8),
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
          const SizedBox(height: 14),
          Text(
            l10n.formFieldGenres,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final genre in _commonGenres)
                FilterChip(
                  label: Text(genre, style: const TextStyle(fontSize: 11)),
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
                  side: const BorderSide(color: AppColors.line),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _Field(label: '+ ${l10n.formFieldGenres}', controller: _customGenres),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                  )
                : Text(l10n.formSave),
          ),
        ],
      ),
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
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.line),
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
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1,
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              style: const TextStyle(
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
