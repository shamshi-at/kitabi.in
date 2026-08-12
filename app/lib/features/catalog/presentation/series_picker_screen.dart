import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/quiet_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import 'picker_widgets.dart';

/// Series picker — the counterpart to the author and publisher pickers.
///
/// The add-book form used to take a series as free text, which is how one
/// ordering became several: "Malgudi", "malgudi " and "ഐതിഹ്യമാല" beside
/// "Aithihyamala" are all the same shelf, and nothing typed can tell. Search
/// here is cross-script and typo-tolerant, and every row shows how many books
/// the series already holds — the signal that makes an existing series the
/// obvious pick over a new near-duplicate.
///
/// Returns `{id, name, book_count?, primary_language?}` via [Navigator.pop].
class SeriesPickerScreen extends ConsumerStatefulWidget {
  const SeriesPickerScreen({super.key, this.initialName});

  /// Prefills the search (and the add-new name) — a series read off a scanned
  /// cover arrives as a string, and the reader should be shown the matches
  /// before it becomes a new row.
  final String? initialName;

  @override
  ConsumerState<SeriesPickerScreen> createState() => _SeriesPickerScreenState();
}

class _SeriesPickerScreenState extends ConsumerState<SeriesPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  bool _errored = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialName?.trim() ?? '';
    if (initial.isNotEmpty) {
      _search.text = initial;
      _query = initial;
      // Straight to the matches: the whole point of arriving with a name is to
      // be shown what already exists under it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch(initial));
    }
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final rows = await ref.read(apiClientProvider).browseSeries(sort: 'popular', limit: 8);
      if (mounted) setState(() => _suggestions = rows);
    } catch (_) {
      // Suggestions are a nicety; a blank list is a fine fallback.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim();
    setState(() => _query = query);
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(query));
  }

  Future<void> _fetch(String query) async {
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final rows = await ref.read(apiClientProvider).searchSeries(query);
      if (!mounted || query != _query) return;
      setState(() => _results = rows);
    } catch (_) {
      if (mounted && query == _query) {
        setState(() {
          _results = [];
          _errored = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showEmpty = _query.isNotEmpty && !_loading && !_errored && _results.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            PickerHeader(title: l10n.seriesPickerTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: PickerSearchField(
                controller: _search,
                hint: l10n.seriesPickerSearchHint,
                onChanged: _onChanged,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (_query.isEmpty && _suggestions.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                      child: Text(
                        l10n.pickerSuggestedSeries,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final series in _suggestions)
                      _SeriesResultTile(series: series, onTap: () => context.pop(series)),
                    const SizedBox(height: 4),
                  ],
                  for (final series in _results)
                    _SeriesResultTile(series: series, onTap: () => context.pop(series)),
                  if (_errored && !_loading) PickerErrorRow(onRetry: () => _fetch(_query)),
                  if (showEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.seriesPickerEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _AddNewSeriesSection(
                    expanded: _adding,
                    initialName: _query,
                    onToggle: () => setState(() => _adding = !_adding),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesResultTile extends StatelessWidget {
  const _SeriesResultTile({required this.series, required this.onTap});

  final Map<String, dynamic> series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = series['name'] as String? ?? '';
    final translit = series['name_translit'] as String?;
    final count = series['book_count'] as int? ?? 0;
    final language = series['primary_language'] as String?;
    // The romanization only earns its line when it says something the name
    // doesn't — on a Latin name it is the same string twice.
    final showTranslit =
        translit != null && translit.isNotEmpty && translit.toLowerCase() != name.toLowerCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Icon(Icons.auto_stories_outlined, color: AppColors.inkSoft, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    [
                      l10n.seriesBookCount(count),
                      if (showTranslit) translit,
                      if (language != null && language.isNotEmpty) language,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.inkSoft, size: 20),
          ],
        ),
      ),
    );
  }
}

class _AddNewSeriesSection extends ConsumerStatefulWidget {
  const _AddNewSeriesSection({
    required this.expanded,
    required this.initialName,
    required this.onToggle,
  });

  final bool expanded;
  final String initialName;
  final VoidCallback onToggle;

  @override
  ConsumerState<_AddNewSeriesSection> createState() => _AddNewSeriesSectionState();
}

class _AddNewSeriesSectionState extends ConsumerState<_AddNewSeriesSection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _language;
  bool _saving = false;

  @override
  void didUpdateWidget(_AddNewSeriesSection old) {
    super.didUpdateWidget(old);
    if (widget.expanded && !old.expanded && _name.text.isEmpty) {
      _name.text = widget.initialName;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      if (_language != null) 'primary_language': _language,
    };
    try {
      final series = await ref.read(apiClientProvider).createSeries(payload);
      if (mounted) context.pop(series);
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.pickerSaveSeriesFailed, err);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!widget.expanded) {
      return OutlinedButton.icon(
        onPressed: widget.onToggle,
        icon: const Icon(Icons.playlist_add, size: 18),
        label: Text(l10n.seriesPickerAddNew),
      );
    }
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.seriesPickerAddNew,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            PickerField(
              label: l10n.pickerFieldName,
              controller: _name,
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pickerNameRequired : null,
            ),
            const SizedBox(height: 8),
            PickerLanguageField(
              label: l10n.pickerFieldLanguage,
              value: _language,
              hint: l10n.pickerLanguageHint,
              onChanged: (v) => setState(() => _language = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.pickerSaveSeries),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
