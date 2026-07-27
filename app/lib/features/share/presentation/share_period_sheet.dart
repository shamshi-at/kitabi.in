import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'period_share_card.dart';
import 'share_sheet_scaffold.dart';

/// The period-card share sheet — Story/Square toggle on the same rasterised
/// card, an editable pre-filled caption, and the same Copy/Share footer shape
/// as the book share sheet (all via [ShareSheetScaffold]). No image to wait
/// on (the card is pure typography, no cover photo).
Future<void> showSharePeriodSheet(
  BuildContext context, {
  required String heroValue,
  required String heroLabel,
  required String subLine,
  required String initialCaption,
  String? pill,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SharePeriodSheet(
      heroValue: heroValue,
      heroLabel: heroLabel,
      subLine: subLine,
      initialCaption: initialCaption,
      pill: pill,
    ),
  );
}

class _SharePeriodSheet extends StatefulWidget {
  const _SharePeriodSheet({
    required this.heroValue,
    required this.heroLabel,
    required this.subLine,
    required this.initialCaption,
    this.pill,
  });

  final String heroValue;
  final String heroLabel;
  final String subLine;
  final String initialCaption;
  final String? pill;

  @override
  State<_SharePeriodSheet> createState() => _SharePeriodSheetState();
}

class _SharePeriodSheetState extends State<_SharePeriodSheet> {
  late final _caption = TextEditingController(text: widget.initialCaption);
  bool _square = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Same rotation mechanism as the daily reading-fact card — one per day,
  /// no repeats until the small pool cycles. A flourish, not a stat, so it
  /// doesn't need to match anything the flagship card itself claims.
  String _closingLine(AppLocalizations l10n) {
    final lines = [
      l10n.insightsShareLine1,
      l10n.insightsShareLine2,
      l10n.insightsShareLine3,
      l10n.insightsShareLine4,
      l10n.insightsShareLine5,
    ];
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    return lines[dayOfYear % lines.length];
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
      title: l10n.insightsShareSheetTitle,
      aboveCard: Row(
        children: [
          Expanded(
            child: _FormatChip(
              label: l10n.insightsShareFormatStory,
              selected: !_square,
              onTap: () => setState(() => _square = false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _FormatChip(
              label: l10n.insightsShareFormatSquare,
              selected: _square,
              onTap: () => setState(() => _square = true),
            ),
          ),
        ],
      ),
      previewWidth: _square ? 220 : 168,
      card: PeriodShareCard(
        heroValue: widget.heroValue,
        heroLabel: widget.heroLabel,
        subLine: widget.subLine,
        closingLine: _closingLine(l10n),
        pill: widget.pill,
        square: _square,
      ),
      captionLabel: l10n.insightsShareCaptionLabel,
      captionController: _caption,
      shareText: () => _caption.text,
      copyLabel: l10n.insightsShareCopyCaption,
      copyIcon: Icons.copy,
      onCopy: _copyCaption,
      shareLabel: l10n.insightsShareImageButton,
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.paper : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
