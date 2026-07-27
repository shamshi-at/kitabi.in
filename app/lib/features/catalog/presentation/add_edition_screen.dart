import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/image_crop.dart';
import '../../../core/quiet_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import 'form_widgets.dart';

/// Add another edition (printing/ISBN) to an existing Work — same book, a
/// different physical copy. Only edition-level fields; the Work (title,
/// authors, genres) is untouched. Scanning an ISBN prefills from the looked-up
/// edition. Every field widget is shared with the add/edit book form
/// (form_widgets.dart) so the two screens can't drift apart again.
class AddEditionScreen extends ConsumerStatefulWidget {
  const AddEditionScreen({super.key, required this.workId, this.workTitle});

  final String workId;
  final String? workTitle;

  @override
  ConsumerState<AddEditionScreen> createState() => _AddEditionScreenState();
}

class _AddEditionScreenState extends ConsumerState<AddEditionScreen> {
  final _isbn = TextEditingController();
  final _pages = TextEditingController();
  final _series = TextEditingController();
  final _seriesNumber = TextEditingController();
  // Optional; null when unset — no silent 'Paperback' on an edition the
  // reader never described.
  String? _format;
  Map<String, dynamic>? _publisher;
  String? _coverUrl;
  String? _backCoverUrl;
  bool _scanning = false;
  bool _uploadingFront = false;
  bool _uploadingBack = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_isbn, _pages, _series, _seriesNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scanIsbn() async {
    setState(() => _scanning = true);
    try {
      final result = await context.push<Map<String, dynamic>>(Routes.catalogScanResult);
      if (result == null || !mounted) return;
      final editions = result['editions'] as List?;
      final edition =
          editions != null && editions.isNotEmpty ? editions.first as Map<String, dynamic> : null;
      setState(() {
        if (result['isbn'] is String) _isbn.text = result['isbn'] as String;
        if (edition != null) {
          if (edition['isbn'] is String) _isbn.text = edition['isbn'] as String;
          final pages = edition['page_count'];
          if (pages != null) _pages.text = pages.toString();
          final format = edition['format'] as String?;
          if (format != null && kEditionFormats.contains(format)) _format = format;
          _coverUrl = edition['cover_url'] as String? ?? _coverUrl;
          final publisher = edition['publisher'] as Map?;
          if (publisher != null) _publisher = Map<String, dynamic>.from(publisher);
        }
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickPublisher() async {
    final result = await context.push<Map<String, dynamic>>(Routes.publisherPicker);
    if (result == null) return;
    setState(() => _publisher = result);
  }

  Future<void> _captureCover({required bool back}) async {
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final url =
          await pickCropUploadImage(source: source, folder: 'covers', ratio: CropRatio.cover);
      if (mounted && url != null) setState(() => back ? _backCoverUrl = url : _coverUrl = url);
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.coverUploadFailed, err);
      }
    } finally {
      if (mounted) setState(() => back ? _uploadingBack = false : _uploadingFront = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    final publisherId = _publisher?['id'] as String?;
    final payload = {
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
      'page_count': int.tryParse(_pages.text.trim()),
      // Absent when unset — the server's format column is nullable, and an
      // unchosen format must not default to anything.
      if (_format != null) 'format': _format,
      'publisher_id': publisherId,
      'publisher_name': publisherId == null ? (_publisher?['name'] as String?) : null,
      'series_name': _series.text.trim().isEmpty ? null : _series.text.trim(),
      'series_number': int.tryParse(_seriesNumber.text.trim()),
      if (_coverUrl != null) 'cover_url': _coverUrl,
      if (_backCoverUrl != null) 'back_cover_url': _backCoverUrl,
    };
    try {
      await ref.read(apiClientProvider).createEdition(widget.workId, payload);
      if (!mounted) return;
      // M9 — every add path ends at a confirmation, not a silent pop. The
      // root messenger outlives this screen, so the toast survives the pop.
      final title = widget.workTitle;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          title == null || title.isEmpty
              ? l10n.addEditionAddedNoTitle
              : l10n.addEditionAdded(title),
        ),
      ));
      context.pop(true);
    } catch (err) {
      if (mounted) {
        showQuietError(context, l10n.formSaveFailed, err);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                            Text(l10n.addEditionTitle,
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(
                              widget.workTitle ?? l10n.addEditionSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverSlot(
                        label: l10n.formCoverFront,
                        imageUrl: _coverUrl,
                        busy: _uploadingFront,
                        title: widget.workTitle,
                        onTap: () => _captureCover(back: false),
                      ),
                      const SizedBox(width: 12),
                      CoverSlot(
                        label: l10n.formCoverBack,
                        imageUrl: _backCoverUrl,
                        busy: _uploadingBack,
                        onTap: () => _captureCover(back: true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.formCoverHelp,
                          style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  IsbnScanField(controller: _isbn, onScan: _scanIsbn, scanning: _scanning),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FormTextField(
                          label: l10n.formFieldPages,
                          controller: _pages,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FormatField(
                          value: _format,
                          onChanged: (v) => setState(() => _format = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  PickerButtonField(
                    label: l10n.formFieldPublisher,
                    value: _publisher?['name'] as String?,
                    placeholder: l10n.formPublisherChoose,
                    onTap: _pickPublisher,
                    onClear: _publisher == null ? null : () => setState(() => _publisher = null),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 14,
                        child: FormTextField(label: l10n.formFieldSeries, controller: _series),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 10,
                        child: FormTextField(
                          label: l10n.formFieldBookNumber,
                          controller: _seriesNumber,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // The same sticky save bar as the add-book form, with an
            // edition-appropriate shared-catalogue hint.
            FormSaveBar(
              saving: _saving,
              onSave: _save,
              label: l10n.addEditionSave,
              hint: l10n.addEditionSaveHint,
            ),
          ],
        ),
      ),
    );
  }
}
