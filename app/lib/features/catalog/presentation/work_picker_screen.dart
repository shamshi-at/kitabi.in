import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import 'picker_widgets.dart';

/// Search the catalogue and pick a Work — used when linking a translation
/// ("This is a translation of…"). Returns the chosen work map (a
/// `WorkSummaryOut`: `{id, title, authors, edition, …}`) via [Navigator.pop].
/// [excludeWorkId] hides the current book so it can't be linked to itself.
class WorkPickerScreen extends ConsumerStatefulWidget {
  const WorkPickerScreen({super.key, this.excludeWorkId});

  final String? excludeWorkId;

  @override
  ConsumerState<WorkPickerScreen> createState() => _WorkPickerScreenState();
}

class _WorkPickerScreenState extends ConsumerState<WorkPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

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
    setState(() => _loading = true);
    try {
      final rows = await ref.read(apiClientProvider).searchCatalog(query);
      if (!mounted || query != _query) return;
      setState(() => _results = rows.where((w) => w['id'] != widget.excludeWorkId).toList());
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showEmpty = _query.isNotEmpty && !_loading && _results.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            PickerHeader(title: l10n.workPickerTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: PickerSearchField(
                controller: _search,
                hint: l10n.workPickerSearchHint,
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
                  for (final work in _results)
                    _WorkResultTile(work: work, onTap: () => context.pop(work)),
                  if (showEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.workPickerEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
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

class _WorkResultTile extends StatelessWidget {
  const _WorkResultTile({required this.work, required this.onTap});

  final Map<String, dynamic> work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final edition = work['edition'] as Map<String, dynamic>?;
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            TypesetCover(
              title: title,
              author: author,
              coverUrl: edition?['cover_url'] as String?,
              width: 34,
              height: 50,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  if (author != null)
                    Text(
                      author,
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
