import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'entity_share_card.dart';
import 'share_sheet_scaffold.dart';

/// The share sheet for an author or publisher — the counterpart to the book
/// share sheet. Previews an [EntityShareCard] (portrait/logo + name +
/// subtitle) and offers Copy-link / Share-card, so a shared author/publisher
/// carries their image and name, not just a bare URL (chrome via
/// [ShareSheetScaffold]).
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

class _EntityShareSheet extends StatelessWidget {
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

  Future<void> _copyLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: shareUrl));
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareLinkCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ShareSheetScaffold(
      title: l10n.shareTitle,
      imageUrl: imageUrl,
      card: EntityShareCard(
        eyebrow: eyebrow,
        name: name,
        subtitle: subtitle,
        imageUrl: imageUrl,
        circular: circular,
      ),
      shareText: () => shareText,
      copyLabel: l10n.shareCopyLink,
      copyIcon: Icons.link,
      onCopy: () => _copyLink(context),
      shareLabel: l10n.shareCardButton,
    );
  }
}
