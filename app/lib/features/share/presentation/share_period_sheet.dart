import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'period_card_data.dart';
import 'period_share_card.dart';
import 'share_sheet_scaffold.dart';

/// The period-card share sheet, rebuilt for the graphical family (26 Aug
/// 2026): Story · Square · Slip as shape-true chips, an optional "Name the
/// book" toggle (the only content decision), the privacy promise printed
/// where the reader can see it every time, and the same editable caption +
/// Copy/Share footer as the whole share family ([ShareSheetScaffold],
/// `captureAndShareCard` untouched underneath).
///
/// [dataBuilder] composes the card for the current toggle state — the caller
/// is the one place that knows what "anonymous" means for its window (drop
/// the title from the subline, keep the spines nameless), so the sheet never
/// edits card strings itself.
Future<void> showSharePeriodSheet(
  BuildContext context, {
  required PeriodCardData Function(bool nameBooks) dataBuilder,
  required String initialCaption,
  bool canNameBooks = false,
  ShareCardFormat initialFormat = ShareCardFormat.story,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SharePeriodSheet(
      dataBuilder: dataBuilder,
      initialCaption: initialCaption,
      canNameBooks: canNameBooks,
      initialFormat: initialFormat,
      title: title,
    ),
  );
}

/// The long-press row slip (B, chosen): one ledger line as an image, locked
/// to slip format — a single row has no story, so there are no format chips.
Future<void> showRowSlipSheet(
  BuildContext context, {
  required RowSlipCard card,
  required String initialCaption,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RowSlipSheet(card: card, initialCaption: initialCaption),
  );
}

class _SharePeriodSheet extends StatefulWidget {
  const _SharePeriodSheet({
    required this.dataBuilder,
    required this.initialCaption,
    required this.canNameBooks,
    required this.initialFormat,
    this.title,
  });

  final PeriodCardData Function(bool nameBooks) dataBuilder;
  final String initialCaption;
  final bool canNameBooks;
  final ShareCardFormat initialFormat;
  final String? title;

  @override
  State<_SharePeriodSheet> createState() => _SharePeriodSheetState();
}

class _SharePeriodSheetState extends State<_SharePeriodSheet> {
  late final _caption = TextEditingController(text: widget.initialCaption);
  late ShareCardFormat _format = widget.initialFormat;
  bool _nameBooks = true;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _copyCaption() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _caption.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.insightsShareCaptionCopied)),
      );
    }
  }

  double get _previewWidth => switch (_format) {
        ShareCardFormat.story => 168,
        ShareCardFormat.square => 220,
        ShareCardFormat.slip => 260,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ShareSheetScaffold(
      title: widget.title ?? l10n.insightsShareSheetTitle,
      aboveCard: Row(
        children: [
          for (final format in ShareCardFormat.values) ...[
            if (format != ShareCardFormat.values.first) const SizedBox(width: 6),
            Expanded(
              child: _FormatChip(
                format: format,
                label: switch (format) {
                  ShareCardFormat.story => l10n.insightsShareFormatStory,
                  ShareCardFormat.square => l10n.insightsShareFormatSquare,
                  ShareCardFormat.slip => l10n.insightsShareFormatSlip,
                },
                selected: _format == format,
                onTap: () => setState(() => _format = format),
              ),
            ),
          ],
        ],
      ),
      previewWidth: _previewWidth,
      card: PeriodShareCard(data: widget.dataBuilder(_nameBooks), format: _format),
      belowCard: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.canNameBooks)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.insightsShareNameBooks,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          l10n.insightsShareNameBooksHint,
                          style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _nameBooks,
                    onChanged: (v) => setState(() => _nameBooks = v),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // The privacy line is not a setting — it's a promise, printed on
          // every open. Numbers, covers and titles only; never notes or
          // private reviews.
          Row(
            children: [
              Icon(Icons.lock_outline, size: 12, color: AppColors.moss),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.insightsSharePrivacyLine,
                  style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      ),
      captionLabel: l10n.insightsShareCaptionAsText,
      captionController: _caption,
      shareText: () => _caption.text,
      copyLabel: l10n.insightsShareCopyCaption,
      copyIcon: Icons.copy,
      onCopy: _copyCaption,
      shareLabel: l10n.insightsShareImageButton,
    );
  }
}

class _RowSlipSheet extends StatefulWidget {
  const _RowSlipSheet({required this.card, required this.initialCaption});

  final RowSlipCard card;
  final String initialCaption;

  @override
  State<_RowSlipSheet> createState() => _RowSlipSheetState();
}

class _RowSlipSheetState extends State<_RowSlipSheet> {
  late final _caption = TextEditingController(text: widget.initialCaption);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _copyCaption() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: _caption.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.insightsShareCaptionCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ShareSheetScaffold(
      title: l10n.insightsShareRowSheetTitle,
      previewWidth: 260,
      card: widget.card,
      belowCard: Row(
        children: [
          Icon(Icons.lock_outline, size: 12, color: AppColors.moss),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.insightsSharePrivacyLine,
              style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, height: 1.3),
            ),
          ),
        ],
      ),
      captionLabel: l10n.insightsShareCaptionAsText,
      captionController: _caption,
      shareText: () => _caption.text,
      copyLabel: l10n.insightsShareCopyCaption,
      copyIcon: Icons.copy,
      onCopy: _copyCaption,
      shareLabel: l10n.insightsShareImageButton,
    );
  }
}

/// A format chip drawn as its true shape — a tall, a square, a wide — so the
/// choice needs no words (the label rides underneath anyway).
class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.format,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ShareCardFormat format;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (w, h) = switch (format) {
      ShareCardFormat.story => (10.0, 17.0),
      ShareCardFormat.square => (14.0, 14.0),
      ShareCardFormat.slip => (19.0, 11.0),
    };
    final tint = selected ? AppColors.ink : AppColors.inkSoft;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.paperDeep : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 17,
                  child: Center(
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        border: Border.all(color: tint, width: 1.5),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
