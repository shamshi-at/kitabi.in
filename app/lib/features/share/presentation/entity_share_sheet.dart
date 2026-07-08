import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'entity_share_card.dart';
import 'share_capture.dart';

/// The share sheet for an author or publisher — the counterpart to the book
/// share sheet. Previews an [EntityShareCard] (portrait/logo + name + subtitle)
/// and offers Copy-link / Share-card, so a shared author/publisher carries their
/// image and name, not just a bare URL.
Future<void> showEntityShareSheet(
  BuildContext context, {
  required String eyebrow,
  required String name,
  required String subtitle,
  required String shareUrl,
  required String shareText,
  String? imageUrl,
  required bool circular,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EntityShareSheet(
      eyebrow: eyebrow,
      name: name,
      subtitle: subtitle,
      shareUrl: shareUrl,
      shareText: shareText,
      imageUrl: imageUrl,
      circular: circular,
    ),
  );
}

class _EntityShareSheet extends StatefulWidget {
  const _EntityShareSheet({
    required this.eyebrow,
    required this.name,
    required this.subtitle,
    required this.shareUrl,
    required this.shareText,
    required this.imageUrl,
    required this.circular,
  });

  final String eyebrow;
  final String name;
  final String subtitle;
  final String shareUrl;
  final String shareText;
  final String? imageUrl;
  final bool circular;

  @override
  State<_EntityShareSheet> createState() => _EntityShareSheetState();
}

class _EntityShareSheetState extends State<_EntityShareSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the portrait/logo up front so it's painted by the time the user
    // taps Share — capturing before a NetworkImage resolves yields a blank spot.
    final url = widget.imageUrl;
    if (url != null) precacheImage(NetworkImage(url), context);
  }

  Future<void> _shareCard() async {
    setState(() => _sharing = true);
    try {
      // Same guard as the book sheet: don't capture a still-loading portrait.
      await ensureImageLoaded(context, widget.imageUrl);
      if (!mounted) return;
      await captureAndShareCard(context: context, cardKey: _cardKey, text: widget.shareText);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
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
                child: EntityShareCard(
                  eyebrow: widget.eyebrow,
                  name: widget.name,
                  subtitle: widget.subtitle,
                  imageUrl: widget.imageUrl,
                  circular: widget.circular,
                ),
              ),
            ),
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
