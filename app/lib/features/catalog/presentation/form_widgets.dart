import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/select_sheet.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';

/// Shared field widgets for the catalog contribution forms — the add/edit book
/// screen and the add-edition screen. These used to be two private forks that
/// drifted apart (the CLAUDE.md lesson, live again): one screen gained helpers,
/// validators and the themed select sheet while the other kept a raw Material
/// dropdown. One copy here keeps both screens in lockstep.

/// The edition formats the forms offer. Values are the server vocabulary —
/// display labels go through [localizedFormat].
const kEditionFormats = ['Paperback', 'Hardcover', 'eBook', 'Audiobook'];

/// Display label for an edition-format *value* — the stored value stays the
/// server's English vocabulary; only what the reader sees localizes.
String localizedFormat(AppLocalizations l10n, String value) => switch (value) {
      'Paperback' => l10n.formatPaperback,
      'Hardcover' => l10n.formatHardcover,
      'eBook' => l10n.formatEbook,
      'Audiobook' => l10n.formatAudiobook,
      _ => value,
    };

/// Display label for one of the hardcoded suggested-genre *values*. Reader- and
/// catalogue-supplied genres pass through untouched — they are shared free
/// text, not a vocabulary the app can translate.
String localizedGenre(AppLocalizations l10n, String value) => switch (value) {
      'Fiction' => l10n.genreFiction,
      'Non-fiction' => l10n.genreNonFiction,
      'Poetry' => l10n.genrePoetry,
      'Historical' => l10n.genreHistorical,
      'Mystery' => l10n.genreMystery,
      'Romance' => l10n.genreRomance,
      'Fantasy' => l10n.genreFantasy,
      'Biography' => l10n.genreBiography,
      'Science' => l10n.genreScience,
      'Self-help' => l10n.genreSelfHelp,
      _ => value,
    };

// Runtime (not const): AppColors.inkSoft resolves per active theme.
TextStyle get formFieldLabelStyle => TextStyle(
      fontSize: 10,
      letterSpacing: 1,
      color: AppColors.inkSoft,
      fontWeight: FontWeight.w600,
    );

/// The sticky save bar under a scrolling contribution form — the primary
/// action is never below the fold, and the one-line note spells out that
/// saving publishes to the shared catalogue.
class FormSaveBar extends StatelessWidget {
  const FormSaveBar({
    super.key,
    required this.saving,
    required this.onSave,
    required this.label,
    required this.hint,
  });

  final bool saving;
  final VoidCallback onSave;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                  )
                : Text(label),
          ),
          SizedBox(height: 5),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// A single labelled, tappable cover thumbnail (front or back). Shows the
/// captured photo when there is one; the front otherwise falls back to the
/// live typeset preview, the back to an "add a photo" placeholder. The camera
/// badge signals it's tappable to shoot/replace.
class CoverSlot extends StatelessWidget {
  const CoverSlot({
    super.key,
    required this.label,
    required this.imageUrl,
    required this.busy,
    required this.onTap,
    this.title,
    this.author,
    this.width = 46,
    this.height = 69, // 2:3
  });

  final String label;
  final String? imageUrl;
  final bool busy;
  final VoidCallback onTap;
  final String? title;
  final String? author;

  /// The add-form's front slot renders larger (the mockup's 64×96 hero slot);
  /// the back stays a small companion tile.
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = height;
    // What the slot shows without (or instead of) a photo — the front falls
    // back to the live typeset preview, the back to an "add a photo" tile.
    Widget fallback() => title != null
        ? TypesetCover(title: title!, author: author, width: w, height: h)
        : Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(Icons.add_a_photo_outlined, size: 18, color: AppColors.inkSoft),
          );
    final preview = imageUrl != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: netImage(
              imageUrl!,
              width: w,
              height: h,
              fit: BoxFit.cover,
              // A dead URL degrades to the typeset/placeholder tile, never a
              // broken-image error box.
              errorBuilder: (_, _, _) => fallback(),
            ),
          )
        : fallback();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: formFieldLabelStyle),
        SizedBox(height: 4),
        GestureDetector(
          onTap: busy ? null : onTap,
          child: Stack(
            children: [
              preview,
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppColors.oxblood, shape: BoxShape.circle),
                  child: busy
                      ? SizedBox(
                          width: 10,
                          height: 10,
                          child:
                              CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.paper),
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

/// A labelled, tappable field that opens a picker page and shows the chosen
/// value (or a placeholder) — the publisher field on both forms. A clear
/// button removes the current selection.
class PickerButtonField extends StatelessWidget {
  const PickerButtonField({
    super.key,
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
        Text(label, style: formFieldLabelStyle),
        SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                    ),
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

/// The forms' labelled text field — validator, helper line, optional inline
/// label action, and (for long text) an expand affordance into a full-screen
/// editor.
class FormTextField extends StatelessWidget {
  const FormTextField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.helper,
    this.fillColor,
    this.maxLines = 1,
    this.expandable = false,
    this.labelAction,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  /// An optional inline action rendered on the label row (right side, before
  /// the expand affordance) — e.g. the Description field's "Scan back cover"
  /// link. A link, not a button, so it sits quietly beside the field it fills.
  final Widget? labelAction;

  /// Optional one-line hint under the field, for the fields users hesitate on
  /// (series, book number, …).
  final String? helper;

  /// Override the fill — e.g. `card` when the field sits inside a `paperDeep`
  /// well (the series group) so it still reads as an input.
  final Color? fillColor;

  /// Long-text fields (description) get an expand affordance that opens the
  /// same controller in a full-screen editor.
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // The label; an inline action (e.g. Description's "Scan back cover")
            // sits right beside it, while the expand affordance stays far right.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: formFieldLabelStyle,
              ),
            ),
            ?labelAction,
            const Spacer(),
            if (expandable)
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _FullScreenTextEditor(
                      title: label,
                      controller: controller,
                      hint: helper,
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full, size: 12, color: AppColors.oxblood),
                      SizedBox(width: 4),
                      Text(
                        l10n.formFieldExpand,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.oxblood,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 4),
        TextFormField(
          textCapitalization: TextCapitalization.sentences,
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fillColor ?? AppColors.card,
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
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Text(
              helper!,
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
            ),
          ),
      ],
    );
  }
}

/// Full-screen editor for long text (the description blurb) — shares the
/// form field's controller, so everything typed here is already in the form
/// when it pops; Done just closes it.
class _FullScreenTextEditor extends StatelessWidget {
  const _FullScreenTextEditor({required this.title, required this.controller, this.hint});

  final String title;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              l10n.formEditorDone,
              style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            autofocus: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 14, color: AppColors.ink, height: 1.5),
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// ISBN field with a built-in Scan button (S7b). Scanning is the primary path —
/// the camera fills in the ISBN (and the rest of the book) — but the field
/// stays fully editable so a user can correct or type it by hand.
class IsbnScanField extends StatelessWidget {
  const IsbnScanField({
    super.key,
    required this.controller,
    required this.onScan,
    required this.scanning,
  });

  final TextEditingController controller;
  final VoidCallback onScan;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.formFieldIsbn, style: formFieldLabelStyle),
        SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 2),
          child: Text(
            l10n.formIsbnScanHelp,
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.25),
          ),
        ),
      ],
    );
  }
}

/// The nullable Format field — a themed select with a leading, subdued
/// "Not set" row. No silent default: a reader who never chose a format saves
/// none, instead of every book quietly becoming a Paperback.
class FormatField extends StatelessWidget {
  const FormatField({super.key, required this.value, required this.onChanged});

  /// The chosen server-vocabulary value, or null when unset.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      ...kEditionFormats,
      // An off-list value from an old edition must stay pickable, not vanish.
      if (value != null && !kEditionFormats.contains(value)) value!,
    ];
    return SelectField(
      label: l10n.formFieldFormat,
      displayValue: value == null ? l10n.formFormatUnset : localizedFormat(l10n, value!),
      isPlaceholder: value == null,
      onTap: () => openSelectSheet(
        context,
        title: l10n.pickerChoose(l10n.formFieldFormat.toLowerCase()),
        current: value,
        options: [
          SelectOption(null, l10n.formFormatUnset, subdued: true),
          for (final o in options) SelectOption(o, localizedFormat(l10n, o)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
