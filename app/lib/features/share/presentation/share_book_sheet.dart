import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'book_share_card.dart';
import 'share_sheet_scaffold.dart';

/// S6c — the share sheet. Shows the card, a toggle to fold in the user's own
/// rating & note (only when they have one), the outgoing share text in the
/// same editable caption field the period sheet uses, and Copy-link /
/// Share-card actions (chrome via [ShareSheetScaffold]).
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
  late bool _includePersonal = widget.personalRating != null;

  /// The text that rides along with the shared image — shown (and editable)
  /// in the caption field instead of being invisible until the OS sheet.
  /// Initialised lazily: the l10n template needs a BuildContext.
  TextEditingController? _caption;

  bool get _hasPersonal => widget.personalRating != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _caption ??= TextEditingController(
      text: AppLocalizations.of(context)!
          .shareBookLinkText(widget.title, widget.author, widget.shareUrl),
    );
  }

  @override
  void dispose() {
    _caption?.dispose();
    super.dispose();
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
    return ShareSheetScaffold(
      title: l10n.shareTitle,
      imageUrl: widget.coverUrl,
      card: BookShareCard(
        title: widget.title,
        author: widget.author,
        coverUrl: widget.coverUrl,
        blurb: widget.blurb,
        catalogRating: widget.catalogRating,
        personalRating: _includePersonal ? widget.personalRating : null,
        personalReview: _includePersonal ? widget.personalReview : null,
      ),
      belowCard: _hasPersonal
          ? SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.shareIncludeRating),
              value: _includePersonal,
              activeThumbColor: AppColors.moss,
              onChanged: (v) => setState(() => _includePersonal = v),
            )
          : null,
      captionLabel: l10n.insightsShareCaptionLabel,
      captionController: _caption,
      shareText: () => _caption?.text ?? '',
      copyLabel: l10n.shareCopyLink,
      copyIcon: Icons.link,
      onCopy: _copyLink,
      shareLabel: l10n.shareCardButton,
    );
  }
}
