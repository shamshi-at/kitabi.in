import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/sheet_grabber.dart';
import 'share_capture.dart';

/// The chrome all three share sheets (period / book / entity) share: grabber,
/// title, the RepaintBoundary'd card preview, image precache, an optional
/// editable caption, and the Copy + Share button row with the busy spinner
/// and the capture-and-share flow. Extracted 28 Jul 2026 — the three sheets
/// had hand-rolled near-identical copies of all of it (the "duplicated
/// private forks" pattern).
class ShareSheetScaffold extends StatefulWidget {
  const ShareSheetScaffold({
    super.key,
    required this.title,
    required this.card,
    required this.shareText,
    required this.copyLabel,
    required this.copyIcon,
    required this.onCopy,
    required this.shareLabel,
    this.aboveCard,
    this.belowCard,
    this.captionLabel,
    this.captionController,
    this.imageUrl,
    this.previewWidth,
  });

  final String title;

  /// The card widget to preview and rasterise — rebuilt by the parent when
  /// its options (format, include-rating…) change.
  final Widget card;

  /// Read at share time (not construction time) so an edited caption is what
  /// accompanies the image.
  final String Function() shareText;

  final String copyLabel;
  final IconData copyIcon;
  final VoidCallback onCopy;
  final String shareLabel;

  /// Optional extra chrome — format chips above, a toggle below.
  final Widget? aboveCard;
  final Widget? belowCard;

  /// When [captionController] is set, an editable caption field renders under
  /// the preview with [captionLabel] as its eyebrow.
  final String? captionLabel;
  final TextEditingController? captionController;

  /// Cover/portrait to precache on open and to await (bounded) before a
  /// capture, so the card never rasterises with a half-loaded image.
  final String? imageUrl;

  /// Constrains the preview (the period card is width-driven); null lets the
  /// card size itself.
  final double? previewWidth;

  @override
  State<ShareSheetScaffold> createState() => _ShareSheetScaffoldState();
}

class _ShareSheetScaffoldState extends State<ShareSheetScaffold> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the image up front so it's painted before the user taps Share —
    // rasterising before a NetworkImage resolves leaves a blank spot.
    final url = widget.imageUrl;
    if (url != null) precacheImage(netImageProvider(url), context);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // Never rasterise a card whose image hasn't decoded yet — wait for it,
      // bounded; on timeout the card ships with the typeset fallback.
      await ensureImageLoaded(context, widget.imageUrl);
      if (!mounted) return;
      await captureAndShareCard(context: context, cardKey: _cardKey, text: widget.shareText());
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.captionController;
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
            const SheetGrabber(),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            if (widget.aboveCard != null) ...[
              const SizedBox(height: 12),
              widget.aboveCard!,
            ],
            const SizedBox(height: 14),
            Center(
              child: SizedBox(
                width: widget.previewWidth,
                child: RepaintBoundary(key: _cardKey, child: widget.card),
              ),
            ),
            if (widget.belowCard != null) ...[
              const SizedBox(height: 12),
              widget.belowCard!,
            ],
            const SizedBox(height: 16),
            if (caption != null) ...[
              if (widget.captionLabel != null)
                Text(
                  widget.captionLabel!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.inkSoft,
                  ),
                ),
              const SizedBox(height: 5),
              TextField(
                controller: caption,
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
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onCopy,
                    icon: Icon(widget.copyIcon, size: 16),
                    label: Text(widget.copyLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.paper),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: Text(widget.shareLabel),
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
