import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/image_crop.dart';
import '../../../core/quiet_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../data/api/api_client.dart';
import '../cover_extract.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import '../work_editions.dart';
import 'form_widgets.dart';

/// Add another edition (printing/ISBN) to an existing Work — same book, a
/// different physical copy. Only edition-level fields; the Work (title,
/// authors, genres) is untouched. Scanning an ISBN prefills from the looked-up
/// edition. Every field widget is shared with the add/edit book form
/// (form_widgets.dart) so the two screens can't drift apart again.
class AddEditionScreen extends ConsumerStatefulWidget {
  const AddEditionScreen({super.key, required this.workId, this.workTitle, this.seed});

  final String workId;
  final String? workTitle;

  /// Details already captured on the add form before the reader discovered the
  /// book was catalogued and chose "mine's a different printing" — the covers
  /// especially. Without this the fork threw two fresh photographs away and
  /// asked for them again (owner report, 13 Aug 2026).
  final Map<String, dynamic>? seed;

  @override
  ConsumerState<AddEditionScreen> createState() => _AddEditionScreenState();
}

class _AddEditionScreenState extends ConsumerState<AddEditionScreen> {
  final _isbn = TextEditingController();
  final _pages = TextEditingController();
  final _series = TextEditingController();
  final _seriesNumber = TextEditingController();
  final _description = TextEditingController();
  // Optional; null when unset — no silent 'Paperback' on an edition the
  // reader never described.
  String? _format;
  Map<String, dynamic>? _publisher;
  String? _coverUrl;
  String? _backCoverUrl;
  // Read off the covers, sent with the printing, and used by the server only
  // where the Work has no answer of its own. Not shown as fields: they are not
  // edition data, and a Type row on a printing form would say they were.
  String? _workForm;
  String? _language;
  bool _scanning = false;
  bool _extracting = false;
  bool _uploadingFront = false;
  bool _uploadingBack = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed == null) return;
    // A printing *is* its covers, its ISBN and its page count — everything the
    // seed carries is edition-level, so all of it applies here.
    _coverUrl = seed['cover_url'] as String?;
    _backCoverUrl = seed['back_cover_url'] as String?;
    _isbn.text = seed['isbn'] as String? ?? '';
    final pages = seed['page_count'];
    if (pages != null) _pages.text = '$pages';
    final format = seed['format'] as String?;
    if (format != null && kEditionFormats.contains(format)) _format = format;
    final publisher = seed['publisher'] as Map?;
    if (publisher != null) _publisher = Map<String, dynamic>.from(publisher);
    final series = seed['series'] as Map?;
    _series.text = series?['name'] as String? ?? seed['series_name'] as String? ?? '';
    final number = seed['series_number'];
    if (number != null) _seriesNumber.text = '$number';
    _description.text = seed['description'] as String? ?? '';
    _workForm = seed['form'] as String?;
    _language = seed['language'] as String?;
  }

  @override
  void dispose() {
    for (final c in [_isbn, _pages, _series, _seriesNumber, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only photos uploaded through this app (our covers bucket) can be read —
  /// same rule as the add-book form, which the server enforces anyway.
  bool _isOwnUpload(String? url) =>
      url != null && url.contains('/storage/v1/object/public/covers/');

  /// "Read the covers" on a *printing*: the ISBN, page count, publisher and
  /// series belong to this edition, while the blurb, type and language are
  /// what a bare parent Work is usually missing (owner request, 13 Aug 2026 —
  /// a work with no covers, no blurb and no info should get them from the
  /// edition being added). Fills only empty fields; the reader's typing wins.
  Future<void> _fillFromPhotos() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Read before the awaits: the blurb lands frames later, and a `ref` read
    // after an await is a read on a widget that may be gone.
    final api = ref.read(apiClientProvider);
    setState(() => _extracting = true);

    // Both halves leave together, so the blurb is already being transcribed
    // while the reader reads the title.
    final parts = startCoverExtract(
      api,
      frontUrl: _isOwnUpload(_coverUrl) ? _coverUrl : null,
      backUrl: _isOwnUpload(_backCoverUrl) ? _backCoverUrl : null,
    );

    var filled = false;
    try {
      filled = _applyExtracted(await parts.identity);
    } on DioException catch (err) {
      final data = err.response?.data;
      final code = data is Map ? data['code'] : null;
      messenger.showSnackBar(SnackBar(
        content: Text(
          code == 'extraction_disabled' ? l10n.formExtractUnavailable : l10n.formExtractFailed,
        ),
      ));
      return;
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractFailed)));
      return;
    } finally {
      // Dropped as soon as the identity fields are in — the reader is not kept
      // waiting behind a blurb they can watch arrive.
      if (mounted) setState(() => _extracting = false);
    }

    // …and the blurb behind them. Never throws (see startCoverExtract).
    if (!mounted) return;
    if (_applyExtracted(await parts.description)) filled = true;
    // Said only once both halves have settled: a read that found no title but
    // did find a blurb has not "found nothing".
    if (mounted && !filled) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.formExtractNothing)));
    }
  }

  bool _applyExtracted(Map<String, dynamic> fields) {
    var filled = false;
    setState(() {
      void text(TextEditingController c, Object? value) {
        if (value == null || c.text.trim().isNotEmpty) return;
        c.text = '$value';
        filled = true;
      }

      text(_isbn, fields['isbn']);
      text(_description, fields['description']);
      text(_series, fields['series_name']);
      if (_series.text.trim().isNotEmpty) text(_seriesNumber, fields['series_number']);
      final publisher = fields['publisher'] as String?;
      if (publisher != null && _publisher == null) {
        // The server hands back the catalogue's canonical house and its id
        // where it knows one — carry the id so this printing joins that row.
        _publisher = {'name': publisher, 'id': ?fields['publisher_id'] as String?};
        filled = true;
      }
      final form = fields['form'] as String?;
      if (form != null && _workForm == null) {
        _workForm = form;
        filled = true;
      }
      final language = fields['language'] as String?;
      if (language != null && _language == null) {
        _language = language;
        filled = true;
      }
    });
    return filled;
  }

  Future<void> _scanIsbn() async {
    setState(() => _scanning = true);
    try {
      final result = await context.push<Map<String, dynamic>>(Routes.catalogScanResult);
      if (result == null || !mounted) return;
      final edition = scannedEdition(result);
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

  /// A camera capture on an edition with no covers yet chains to the other
  /// side (same flow as the add-book form — the two must not drift).
  Future<void> _captureCover({required bool back}) async {
    final bothEmpty = _coverUrl == null && _backCoverUrl == null;
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    final captured = await _captureCoverFrom(source, back: back);
    if (captured &&
        source == ImageSource.camera &&
        bothEmpty &&
        mounted &&
        (back ? _coverUrl == null : _backCoverUrl == null)) {
      final next = await showChainedCoverSheet(context, nextIsBack: !back);
      if (next && mounted) await _captureCoverFrom(ImageSource.camera, back: !back);
    }
  }

  /// One capture/pick → crop → upload into the [back] slot; true if a photo
  /// landed.
  Future<bool> _captureCoverFrom(ImageSource source, {required bool back}) async {
    setState(() => back ? _uploadingBack = true : _uploadingFront = true);
    try {
      final url =
          await pickCropUploadImage(source: source, folder: 'covers', ratio: CropRatio.cover);
      if (mounted && url != null) setState(() => back ? _backCoverUrl = url : _coverUrl = url);
      return url != null;
    } catch (err) {
      if (mounted) {
        showQuietError(context, AppLocalizations.of(context)!.coverUploadFailed, err);
      }
      return false;
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
      // Work-level, and gap-fill only on the server: a book whose entry has no
      // blurb, type or language gets them from the copy in the reader's hands
      // rather than staying blank forever.
      'description': ?(_description.text.trim().isEmpty ? null : _description.text.trim()),
      'form': ?_workForm,
      'language': ?_language,
    };
    try {
      final created = await ref.read(apiClientProvider).createEdition(widget.workId, payload);
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
      // Pop with the edition itself, not a bare `true`: the caller has to be
      // able to send the reader to *this* printing. Landing them back on the
      // work's representative edition is how "add to library" kept shelving
      // the parent, page count and all (owner report, 13 Aug 2026).
      context.pop(created);
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
                  // Same rescue path as the add-book form: once a photo is up,
                  // read the printing off it. Shared behaviour, so the two
                  // screens can't drift (the reason every field widget here is
                  // imported rather than re-written).
                  if (_isOwnUpload(_coverUrl) || _isOwnUpload(_backCoverUrl)) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: (_extracting || _uploadingBack) ? null : _fillFromPhotos,
                        icon: _extracting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.auto_awesome, size: 16, color: AppColors.oxblood),
                        label: Text(l10n.formFillFromPhotos),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
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
                  const SizedBox(height: 10),
                  // The blurb is the Work's, not this printing's — the helper
                  // says so. It's here because the reader adding a printing is
                  // holding the book, and the parent entry is usually the bare
                  // stub an ISBN lookup left behind.
                  FormTextField(
                    label: l10n.formFieldDescription,
                    controller: _description,
                    maxLines: 4,
                    expandable: true,
                    helper: l10n.addEditionDescriptionHelp,
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
