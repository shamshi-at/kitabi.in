import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'period_share_card.dart';
import 'share_capture.dart';

/// The period-card share sheet — Story/Square toggle on the same rasterised
/// card, an editable pre-filled caption, and the same Copy/Share footer shape
/// as the book share sheet. No image to wait on (the card is pure typography,
/// no cover photo), so unlike [showShareBookSheet] there's nothing to
/// precache before a tap on Share.
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
  final _cardKey = GlobalKey();
  late final _caption = TextEditingController(text: widget.initialCaption);
  bool _square = false;
  bool _sharing = false;

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

  Future<void> _shareImage() async {
    setState(() => _sharing = true);
    try {
      await captureAndShareCard(context: context, cardKey: _cardKey, text: _caption.text);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            Text(l10n.insightsShareSheetTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
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
            const SizedBox(height: 14),
            Center(
              child: SizedBox(
                width: _square ? 220 : 168,
                child: RepaintBoundary(
                  key: _cardKey,
                  child: PeriodShareCard(
                    heroValue: widget.heroValue,
                    heroLabel: widget.heroLabel,
                    subLine: widget.subLine,
                    closingLine: _closingLine(l10n),
                    pill: widget.pill,
                    square: _square,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.insightsShareCaptionLabel.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 5),
            TextField(
              controller: _caption,
              maxLines: 3,
              style: TextStyle(fontSize: 11.5, color: AppColors.ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.paper,
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.line),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyCaption,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l10n.insightsShareCopyCaption),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _shareImage,
                    icon: _sharing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: Text(l10n.insightsShareImageButton),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.paper : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
