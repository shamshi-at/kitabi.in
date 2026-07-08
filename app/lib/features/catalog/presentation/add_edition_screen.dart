import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../core/image_crop.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import '../catalog_image_upload.dart';
import '../../../core/widgets/net_image.dart';

/// The edition formats offered in the add-edition form's dropdown.
const _formats = ['Paperback', 'Hardcover', 'eBook', 'Audiobook'];

/// Add another edition (printing/ISBN) to an existing Work — same book, a
/// different physical copy. Only edition-level fields; the Work (title, authors,
/// genres) is untouched. Scanning an ISBN prefills from the looked-up edition.
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
  String _format = _formats.first;
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
          if (format != null && _formats.contains(format)) _format = format;
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
      final url = await pickCropUploadImage(source: source, folder: 'covers', ratio: CropRatio.cover);
      if (mounted && url != null) setState(() => back ? _backCoverUrl = url : _coverUrl = url);
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
    setState(() => _saving = true);
    final publisherId = _publisher?['id'] as String?;
    final payload = {
      'isbn': _isbn.text.trim().isEmpty ? null : _isbn.text.trim(),
      'page_count': int.tryParse(_pages.text.trim()),
      'format': _format,
      'publisher_id': publisherId,
      'publisher_name': publisherId == null ? (_publisher?['name'] as String?) : null,
      'series_name': _series.text.trim().isEmpty ? null : _series.text.trim(),
      'series_number': int.tryParse(_seriesNumber.text.trim()),
      if (_coverUrl != null) 'cover_url': _coverUrl,
      if (_backCoverUrl != null) 'back_cover_url': _backCoverUrl,
    };
    try {
      await ref.read(apiClientProvider).createEdition(widget.workId, payload);
      if (mounted) context.pop(true);
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
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                      Text(l10n.addEditionTitle, style: Theme.of(context).textTheme.titleLarge),
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
                _CoverSlot(
                  label: l10n.formCoverFront,
                  imageUrl: _coverUrl,
                  busy: _uploadingFront,
                  title: widget.workTitle,
                  onTap: () => _captureCover(back: false),
                ),
                const SizedBox(width: 12),
                _CoverSlot(
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
            _IsbnScanField(controller: _isbn, onScan: _scanIsbn, scanning: _scanning),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: l10n.formFieldPages,
                    controller: _pages,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DropdownField(
                    label: l10n.formFieldFormat,
                    value: _format,
                    options: _formats,
                    onChanged: (v) => setState(() => _format = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PickerButtonField(
              label: l10n.formFieldPublisher,
              value: _publisher?['name'] as String?,
              placeholder: l10n.formPublisherChoose,
              onTap: _pickPublisher,
              onClear: _publisher == null ? null : () => setState(() => _publisher = null),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 14,
                  child: _Field(label: l10n.formFieldSeries, controller: _series),
                ),
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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(l10n.addEditionSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle get _labelStyle => TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: AppColors.inkSoft,
      fontWeight: FontWeight.w600,
    );

class _CoverSlot extends StatelessWidget {
  const _CoverSlot({
    required this.label,
    required this.imageUrl,
    required this.busy,
    required this.onTap,
    this.title,
  });

  final String label;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;
  final String? title;

  @override
  Widget build(BuildContext context) {
    const w = 46.0;
    const h = 69.0;
    Widget preview;
    if (imageUrl != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: netImage(imageUrl!, width: w, height: h, fit: BoxFit.cover),
      );
    } else if (title != null) {
      preview = TypesetCover(title: title!, width: w, height: h);
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
        Text(label, style: _labelStyle),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: busy ? null : onTap,
          child: Stack(
            children: [
              preview,
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.all(3),
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

class _IsbnScanField extends StatelessWidget {
  const _IsbnScanField({required this.controller, required this.onScan, required this.scanning});

  final TextEditingController controller;
  final VoidCallback onScan;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldIsbn, style: _labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.keyboardType});

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        Text(label, style: _labelStyle),
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
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
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
        Text(label, style: _labelStyle),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
