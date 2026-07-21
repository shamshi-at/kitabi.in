import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/languages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/select_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/providers/profile_providers.dart';
import 'picker_widgets.dart';

/// Search the catalogue and pick a Work — used when linking a translation
/// ("This is a translation of…"). Returns the chosen work map (a
/// `WorkSummaryOut`: `{id, title, authors, edition, …}`) via [Navigator.pop].
/// [excludeWorkId] hides the current book so it can't be linked to itself.
///
/// [forOriginal] is the T2 flavour — picking a translation's *original*: the
/// header says so, group members are badged (gold "Original" stamp on a
/// group's root, "in group" on its translations), and a "Not here? Add the
/// original" card opens the T3 stub sheet: four fields, author carried over
/// from [seed], creating a catalogue-only Work that pops back selected.
/// Nothing the stub creates lands on anyone's shelf.
class WorkPickerScreen extends ConsumerStatefulWidget {
  const WorkPickerScreen({
    super.key,
    this.excludeWorkId,
    this.forOriginal = false,
    this.seed,
  });

  final String? excludeWorkId;
  final bool forOriginal;

  /// Carry-over from the book being added (T3's "carried over from your
  /// book"): `{authors: [{id?, name}], form?, genre_names?}` — a translation
  /// shares its original's author, type and genres.
  final Map<String, dynamic>? seed;

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

  Future<void> _addOriginalStub() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _OriginalStubSheet(
        initialTitle: _query,
        seed: widget.seed,
      ),
    );
    if (created != null && mounted) context.pop(created);
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
            PickerHeader(
              title: widget.forOriginal ? l10n.workPickerOriginalTitle : l10n.workPickerTitle,
            ),
            if (widget.forOriginal)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.workPickerOriginalSubtitle,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                  ),
                ),
              ),
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
                    _WorkResultTile(
                      work: work,
                      badges: widget.forOriginal,
                      onTap: () => context.pop(work),
                    ),
                  if (showEmpty && !widget.forOriginal)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.workPickerEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ),
                  // T2's escape hatch — the not-in-catalogue case is the
                  // *common* one for regional translations, so it's a card
                  // with equal weight, not a buried link. Shown as soon as
                  // the reader has typed anything.
                  if (widget.forOriginal && _query.isNotEmpty && !_loading) ...[
                    const SizedBox(height: 8),
                    _AddOriginalCard(onTap: _addOriginalStub),
                  ],
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
  const _WorkResultTile({required this.work, required this.onTap, this.badges = false});

  final Map<String, dynamic> work;
  final VoidCallback onTap;

  /// T2 mode: stamp group membership — gold "Original" on a group's root
  /// (in a translation group, itself translated from nothing), a quiet
  /// "in group" on its translations.
  final bool badges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final edition = work['edition'] as Map<String, dynamic>?;
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final language = edition?['language'] as String?;
    final year = work['first_publish_year'];
    final subtitle = [
      ?author,
      ?language,
      if (year != null) '$year',
    ].join(' · ');
    final inGroup = work['translation_group_id'] != null;
    final isOriginal = badges && inGroup && work['original_work_id'] == null;
    final isSibling = badges && work['original_work_id'] != null;

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
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (isOriginal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l10n.workPickerStampOriginal.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    color: Color(0xFF8F681E),
                  ),
                ),
              )
            else if (isSibling)
              Text(
                l10n.workPickerStampInGroup,
                style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
              )
            else
              Icon(Icons.chevron_right, color: AppColors.inkSoft, size: 20),
          ],
        ),
      ),
    );
  }
}

/// "Not here? Add the original" — the oxblood-ruled escape hatch (T2).
class _AddOriginalCard extends StatelessWidget {
  const _AddOriginalCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        // A borderRadius + non-uniform Border is invalid in Flutter (throws at
        // paint time), so the mockup's left accent rule is an inner clipped
        // bar instead — same look, uniform border.
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 3, color: AppColors.oxblood),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.workPickerAddOriginal,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.oxblood,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.workPickerAddOriginalHelp,
                          style:
                              TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4),
                        ),
                      ],
                    ),
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

/// T3 — the four-field stub: a catalogue entry for the original, created from
/// the translation's side without leaving the flow. Author (and type/genre,
/// invisibly) carried over from the book being added; language and year are
/// the two fields the reader actually types. Pops the created Work map.
class _OriginalStubSheet extends ConsumerStatefulWidget {
  const _OriginalStubSheet({required this.initialTitle, this.seed});

  final String initialTitle;
  final Map<String, dynamic>? seed;

  @override
  ConsumerState<_OriginalStubSheet> createState() => _OriginalStubSheetState();
}

class _OriginalStubSheetState extends ConsumerState<_OriginalStubSheet> {
  late final TextEditingController _title;
  late final TextEditingController _year;
  late final List<Map<String, dynamic>> _authors;
  String? _language;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initialTitle);
    _year = TextEditingController();
    _authors = ((widget.seed?['authors'] as List?) ?? const [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(apiClientProvider).createWork({
        'title': title,
        'language': _language,
        'first_publish_year': int.tryParse(_year.text.trim()),
        'author_ids': [
          for (final a in _authors)
            if (a['id'] != null) a['id'] as String,
        ],
        'author_names': [
          for (final a in _authors)
            if (a['id'] == null) a['name'] as String,
        ],
        // The invisible carry-over: a translation shares its original's type
        // and genres, so the stub starts with them rather than blank.
        'form': widget.seed?['form'],
        'genre_names': (widget.seed?['genre_names'] as List?)?.cast<String>() ?? const [],
      });
      if (mounted) Navigator.of(context).pop(created);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: .8,
      color: AppColors.inkSoft,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
              l10n.workPickerOriginalTitle,
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.workPickerAddOriginalHelp,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 14),
            Text(l10n.stubFieldTitle.toUpperCase(), style: labelStyle),
            const SizedBox(height: 4),
            TextField(controller: _title, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  // The themed searchable picker (never the raw Material
                  // dropdown), reader's profile languages first — an original
                  // can be in any language, Spanish to Japanese.
                  child: SelectField(
                    label: l10n.formFieldLanguage.toUpperCase(),
                    labelStyle: labelStyle,
                    displayValue: _language ?? l10n.formLanguageUnset,
                    isPlaceholder: _language == null,
                    onTap: () {
                      final preferred =
                          (ref.read(meProvider).valueOrNull?['preferred_languages'] as List?)
                                  ?.cast<String>() ??
                              const [];
                      openSelectSheet(
                        context,
                        title: l10n.pickerChoose(l10n.formFieldLanguage.toLowerCase()),
                        current: _language,
                        options: [
                          SelectOption(null, l10n.formLanguageUnset, subdued: true),
                          for (final lang in languageOptions(preferred))
                            SelectOption(lang, lang),
                        ],
                        onChanged: (v) => setState(() => _language = v),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.stubFieldYear.toUpperCase(), style: labelStyle),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _year,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.formFieldAuthor.toUpperCase(), style: labelStyle),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final author in _authors)
                  Chip(
                    label: Text(
                      author['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: AppColors.goldSoft,
                    side: BorderSide.none,
                    onDeleted: () => setState(() => _authors.remove(author)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5D3A6)),
              ),
              child: Text(
                l10n.stubCarriedOver,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Color(0xFF8A6F34),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oxblood,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(l10n.stubSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
