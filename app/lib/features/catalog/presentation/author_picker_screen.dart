import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/kitabi_linked_badge.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import 'picker_widgets.dart';
import '../../../core/widgets/net_image.dart';

/// S7b author picker — opened from the add-book form's author field. Search the
/// catalog for an existing author (shown with their portrait, pen name, and
/// primary language so near-duplicates are distinguishable), or add a brand-new
/// one with those same details. Returns the chosen author map
/// `{id, name, image_url?, primary_language?}` via [Navigator.pop].
///
/// [initialIsMe] jumps straight into the add-new form with "This is me"
/// pre-checked — the "is this your book?" entry point from the add-book form
/// (owner report, 15 Jul 2026: self-tagging was buried two taps under "add a
/// new author"). [initialName] seeds both the search (so an already-linked
/// Author row for this reader surfaces as a pick instead of inviting a
/// duplicate) and the add-new form's name field.
class AuthorPickerScreen extends ConsumerStatefulWidget {
  const AuthorPickerScreen({super.key, this.initialName, this.initialIsMe = false});

  final String? initialName;
  final bool initialIsMe;

  @override
  ConsumerState<AuthorPickerScreen> createState() => _AuthorPickerScreenState();
}

class _AuthorPickerScreenState extends ConsumerState<AuthorPickerScreen> {
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
    _adding = widget.initialIsMe;
    final name = widget.initialName?.trim();
    if (name != null && name.isNotEmpty) {
      _search.text = name;
      _query = name;
      _fetch(name);
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final rows = await ref.read(apiClientProvider).browseAuthors(sort: 'popular', limit: 8);
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
      final rows = await ref.read(apiClientProvider).searchAuthors(query);
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
            PickerHeader(title: l10n.authorPickerTitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: PickerSearchField(
                controller: _search,
                hint: l10n.authorPickerSearchHint,
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
                        l10n.pickerSuggestedAuthors,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final author in _suggestions)
                      _AuthorResultTile(
                        author: author,
                        onTap: () => context.pop(author),
                      ),
                    const SizedBox(height: 4),
                  ],
                  for (final author in _results)
                    _AuthorResultTile(
                      author: author,
                      onTap: () => context.pop(author),
                    ),
                  if (showEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.authorPickerEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _AddNewAuthorSection(
                    expanded: _adding,
                    initialName: _query,
                    initialIsMe: widget.initialIsMe,
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

class _AuthorResultTile extends StatelessWidget {
  const _AuthorResultTile({required this.author, required this.onTap});

  final Map<String, dynamic> author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = author['name'] as String? ?? '';
    final imageUrl = author['image_url'] as String?;
    final penName = author['pen_name'] as String?;
    final language = author['primary_language'] as String?;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final linked = author['linked_user_id'] != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: imageUrl != null ? netImageProvider(imageUrl) : null,
              child: imageUrl == null
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Color(0xFF8F681E),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                      if (linked) ...[
                        const SizedBox(width: 6),
                        const KitabiLinkedBadge(compact: true),
                      ],
                    ],
                  ),
                  if (penName != null && penName.isNotEmpty)
                    Text(
                      l10n.authorWritingAs(penName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.oxblood,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
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

class _AddNewAuthorSection extends ConsumerStatefulWidget {
  const _AddNewAuthorSection({
    required this.expanded,
    required this.initialName,
    this.initialIsMe = false,
    required this.onToggle,
  });

  final bool expanded;
  final String initialName;
  final bool initialIsMe;
  final VoidCallback onToggle;

  @override
  ConsumerState<_AddNewAuthorSection> createState() => _AddNewAuthorSectionState();
}

class _AddNewAuthorSectionState extends ConsumerState<_AddNewAuthorSection> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bio = TextEditingController();
  String? _language;
  String? _imageUrl;
  bool _isMe = false;
  bool _uploading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isMe = widget.initialIsMe;
    // Expanded from the very first frame (the "is this your book?" entry
    // point) — didUpdateWidget's false-\>true transition never fires, so seed
    // the name here too.
    if (widget.expanded) {
      _name.text = widget.initialName;
    }
  }

  @override
  void didUpdateWidget(_AddNewAuthorSection old) {
    super.didUpdateWidget(old);
    // Seed the name from the search query when the form is first expanded.
    if (widget.expanded && !old.expanded && _name.text.isEmpty) {
      _name.text = widget.initialName;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await pickAndUploadCatalogImage(folder: 'authors', source: source);
      if (mounted && url != null) setState(() => _imageUrl = url);
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
      if (_imageUrl != null) 'image_url': _imageUrl,
      if (_bio.text.trim().isNotEmpty) 'bio': _bio.text.trim(),
      if (_isMe) 'is_me': true,
    };
    try {
      final author = await ref.read(apiClientProvider).createAuthor(payload);
      if (mounted) context.pop(author);
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
        icon: const Icon(Icons.person_add_alt, size: 18),
        label: Text(l10n.authorPickerAddNew),
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
              l10n.authorPickerAddNew,
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
              label: l10n.pickerFieldPhoto,
              imageUrl: _imageUrl,
              busy: _uploading,
              pickLabel: _imageUrl == null ? l10n.pickerPhotoAdd : l10n.pickerPhotoReplace,
              onPick: _pickImage,
              onClear: _imageUrl == null ? null : () => setState(() => _imageUrl = null),
            ),
            const SizedBox(height: 8),
            PickerField(label: l10n.pickerFieldBio, controller: _bio, maxLines: 3),
            // Hidden alongside the author page's "This is me" — the same
            // unverifiable claim, and leaving this one standing would keep the
            // misuse route open (owner decision, 22 Jul 2026). `_isMe` stays
            // wired and simply reads false; restoring is one widget.
            const SizedBox(height: 8),
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
                    : Text(l10n.pickerSaveAuthor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

