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
    required this.coverUrl,
    required this.blurb,
    required this.catalogRating,
    required this.personalRating,
    required this.personalReview,
  });

  final String title;
  final String author;
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
    final text = AppLocalizations.of(context)!.shareBookText(widget.title, widget.author);
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = XFile.fromData(
        bytes.buffer.asUint8List(),
        name: 'kitabi.png',
        mimeType: 'image/png',
      );
      await Share.shareXFiles([file], text: text);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _copyLink() async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(
      ClipboardData(text: l10n.shareBookText(widget.title, widget.author)),
    );
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
