import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import 'picker_widgets.dart';

/// S7b publisher picker — the publisher counterpart to the author picker.
/// Search an existing catalog publisher (shown with logo and primary language)
/// or add a new one. Returns `{id, name, logo_url?, primary_language?}` via
/// [Navigator.pop].
class PublisherPickerScreen extends ConsumerStatefulWidget {
  const PublisherPickerScreen({super.key});

  @override
  ConsumerState<PublisherPickerScreen> createState() => _PublisherPickerScreenState();
}

class _PublisherPickerScreenState extends ConsumerState<PublisherPickerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final rows = await ref.read(apiClientProvider).browsePublishers(sort: 'popular', limit: 8);
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
    setState(() => _loading = true);
    try {
      final rows = await ref.read(apiClientProvider).searchPublishers(query);
      if (!mounted || query != _query) return;
      setState(() => _results = rows);
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
            PickerHeader(title: l10n.publisherPickerTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: PickerSearchField(
                controller: _search,
                hint: l10n.publisherPickerSearchHint,
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
                        l10n.pickerSuggestedPublishers,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final publisher in _suggestions)
                      _PublisherResultTile(
                        publisher: publisher,
                        onTap: () => context.pop(publisher),
                      ),
                    const SizedBox(height: 4),
                  ],
                  for (final publisher in _results)
                    _PublisherResultTile(
                      publisher: publisher,
                      onTap: () => context.pop(publisher),
                    ),
                  if (showEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.publisherPickerEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _AddNewPublisherSection(
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

class _PublisherResultTile extends StatelessWidget {
  const _PublisherResultTile({required this.publisher, required this.onTap});

  final Map<String, dynamic> publisher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = publisher['name'] as String? ?? '';
    final logoUrl = publisher['logo_url'] as String?;
    final language = publisher['primary_language'] as String?;

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
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: logoUrl != null
                  ? Image.network(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(Icons.business, color: AppColors.inkSoft),
                    )
                  : Icon(Icons.business, color: AppColors.inkSoft, size: 18),
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
                  if (language != null && language.isNotEmpty)
                    Text(
                      l10n.authorPickerLanguage(language),
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

class _AddNewPublisherSection extends ConsumerStatefulWidget {
  const _AddNewPublisherSection({
    required this.expanded,
    required this.initialName,
    required this.onToggle,
  });

  final bool expanded;
  final String initialName;
  final VoidCallback onToggle;

  @override
  ConsumerState<_AddNewPublisherSection> createState() => _AddNewPublisherSectionState();
}

class _AddNewPublisherSectionState extends ConsumerState<_AddNewPublisherSection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _language;
  String? _logoUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void didUpdateWidget(_AddNewPublisherSection old) {
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

  Future<void> _pickLogo() async {
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadCatalogImage(folder: 'publishers', source: source);
      if (mounted && url != null) setState(() => _logoUrl = url);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.pickerImageUploadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      if (_language != null) 'primary_language': _language,
      if (_logoUrl != null) 'logo_url': _logoUrl,
    };
    try {
      final publisher = await ref.read(apiClientProvider).createPublisher(payload);
      if (mounted) context.pop(publisher);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
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
        icon: const Icon(Icons.add_business_outlined, size: 18),
        label: Text(l10n.publisherPickerAddNew),
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
              l10n.publisherPickerAddNew,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            PickerField(
              label: l10n.pickerFieldName,
              controller: _name,
              validator: (v) => (v == null || v.trim().isEmpty) ? l10n.pickerNameRequired : null,
            ),
            const SizedBox(height: 8),
            PickerLanguageDropdown(
              label: l10n.pickerFieldLanguage,
              value: _language,
              hint: l10n.pickerLanguageHint,
              onChanged: (v) => setState(() => _language = v),
            ),
            const SizedBox(height: 8),
            PickerImageField(
              label: l10n.pickerFieldLogo,
              imageUrl: _logoUrl,
              busy: _uploading,
              pickLabel: _logoUrl == null ? l10n.pickerLogoAdd : l10n.pickerLogoReplace,
              onPick: _pickLogo,
              onClear: _logoUrl == null ? null : () => setState(() => _logoUrl = null),
              circular: false,
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
                    : Text(l10n.pickerSavePublisher),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
