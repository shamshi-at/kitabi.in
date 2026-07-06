import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'book_share_card.dart';

/// S6c — the share sheet. Shows the card, a toggle to fold in the user's own
/// rating & note (only when they have one), and Copy-link / Share-card actions.
/// "Share card" rasterises the previewed card and hands it to the OS share sheet.
Future<void> showShareBookSheet(
  BuildContext context, {
  required String title,
  required String author,
  required String shareUrl,
  String? coverUrl,
  String? blurb,
  double? catalogRating,
  int? personalRating,
  String? personalReview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ShareSheet(
      title: title,
      author: author,
      shareUrl: shareUrl,
      coverUrl: coverUrl,
      blurb: blurb,
      catalogRating: catalogRating,
      personalRating: personalRating,
      personalReview: personalReview,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.title,
    required this.author,
    required this.shareUrl,
    required this.coverUrl,
    required this.blurb,
    required this.catalogRating,
    required this.personalRating,
    required this.personalReview,
  });

  final String title;
  final String author;
  final String shareUrl;
  final String? coverUrl;
  final String? blurb;
  final double? catalogRating;
  final int? personalRating;
  final String? personalReview;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _cardKey = GlobalKey();
  late bool _includePersonal = widget.personalRating != null;
  bool _sharing = false;

  bool get _hasPersonal => widget.personalRating != null;

  Future<void> _shareCard() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // The share text carries the real link, so even when a recipient can't see
    // the image they still get a tappable book URL.
    final text = l10n.shareBookLinkText(widget.title, widget.author, widget.shareUrl);
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('share card not ready');
      }
      // The card can still be mid-paint on the first frame after the sheet
      // opens; wait a frame so the capture isn't blank/partial.
      if (boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('could not encode card');
      }
      final file = XFile.fromData(
        bytes.buffer.asUint8List(),
        name: 'kitabi.png',
        mimeType: 'image/png',
      );
      // sharePositionOrigin is required for the iPad popover; harmless on phones.
      await Share.shareXFiles(
        [file],
        text: text,
        sharePositionOrigin: _originRect(),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// iPad requires an anchor rect for the share popover — use the sheet's own
  /// bounds, falling back to a sane default if the box isn't laid out.
  Rect _originRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shareLinkCopied)),
      );
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
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Text(l10n.shareTitle, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 14),
            Center(
              child: RepaintBoundary(
                key: _cardKey,
                child: BookShareCard(
                  title: widget.title,
                  author: widget.author,
                  coverUrl: widget.coverUrl,
                  blurb: widget.blurb,
                  catalogRating: widget.catalogRating,
                  personalRating: _includePersonal ? widget.personalRating : null,
                  personalReview: _includePersonal ? widget.personalReview : null,
                ),
              ),
            ),
            if (_hasPersonal) ...[
              SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.shareIncludeRating),
                value: _includePersonal,
                activeThumbColor: AppColors.moss,
                onChanged: (v) => setState(() => _includePersonal = v),
              ),
            ] else
              SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyLink,
                    icon: Icon(Icons.link, size: 18),
                    label: Text(l10n.shareCopyLink),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _shareCard,
                    icon: _sharing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.paper),
                          )
                        : Icon(Icons.ios_share, size: 18),
                    label: Text(l10n.shareCardButton),
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
