import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/share_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../recap_identity.dart';
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
  required String recapKey,
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
      recapKey: recapKey,
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

class _SharePeriodSheet extends ConsumerStatefulWidget {
  const _SharePeriodSheet({
    required this.dataBuilder,
    required this.initialCaption,
    required this.recapKey,
    required this.canNameBooks,
    required this.initialFormat,
    this.title,
  });

  final PeriodCardData Function(bool nameBooks) dataBuilder;
  final String initialCaption;
  final String recapKey;
  final bool canNameBooks;
  final ShareCardFormat initialFormat;
  final String? title;

  @override
  ConsumerState<_SharePeriodSheet> createState() => _SharePeriodSheetState();
}

class _SharePeriodSheetState extends ConsumerState<_SharePeriodSheet> {
  late final _caption = TextEditingController(text: widget.initialCaption);
  late ShareCardFormat _format = widget.initialFormat;
  bool _nameBooks = true;
  /// A publish attempt failed (offline). The link is then dropped from the
  /// card and the caption rather than shared as a URL that would 404.
  bool _publishFailed = false;

  /// The caption the reader has already edited must never be overwritten by
  /// the link arriving — appended once, and only to text they haven't touched
  /// since.
  String? _captionWithLink;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// The link this window will carry — shown as soon as the reader *has a
  /// handle*, not only once their recaps are published.
  ///
  /// Sharing the card is what publishes them (owner decision, 8 Sep 2026: the
  /// link was opt-in behind a button, so the first card shared had no link and
  /// the recipient had nowhere to go). Consent is the act of sharing, which is
  /// the act the reader is already performing — so the honest thing is to show
  /// the exact URL, and what it will mean, *before* the Share button is tapped
  /// rather than after.
  String? _linkFor(RecapIdentity? identity) {
    if (identity == null || identity.needsUsername || _publishFailed) return null;
    return recapShareUrl(identity.username!, widget.recapKey);
  }

  /// Publish the reader's recaps if this is their first shared card. Runs
  /// before the capture, so the link is on the image and in the caption.
  ///
  /// A failure here is not a failed share: the card and its caption still go,
  /// minus the link, and the reader is told why. A link that 404s because the
  /// flag never reached the server would be worse than no link at all.
  Future<void> _publishBeforeShare() async {
    final identity = ref.read(recapIdentityProvider).valueOrNull;
    if (identity == null || identity.needsUsername || identity.recapsVisible) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await publishRecaps(ref);
      ref.invalidate(recapIdentityProvider);
      await ref.read(recapIdentityProvider.future);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publishFailed = true;
        final link = recapShareUrl(identity.username!, widget.recapKey);
        _caption.text = _caption.text.replaceAll(link, '').trimRight();
        _captionWithLink = null;
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareRecapPublishFailed)));
    }
  }

  /// Put the link into the caption, so the message that arrives carries it —
  /// the caption now ships *with* the image (8 Sep 2026), which is the whole
  /// reason a link on a card is worth anything.
  void _syncCaption(String? link) {
    if (link == null) return;
    if (_caption.text.contains(link)) return;
    // Only if the reader hasn't edited it away from what we last wrote.
    if (_captionWithLink != null && _caption.text != _captionWithLink) return;
    final base = _caption.text.trim();
    final next = base.isEmpty ? link : '$base\n$link';
    _caption.text = next;
    _captionWithLink = next;
  }

  Future<void> _copyLink(String link) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.shareRecapCopied)),
    );
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
    final identity = ref.watch(recapIdentityProvider).valueOrNull;
    final link = _linkFor(identity);
    // The caption is what actually reaches the recipient now that text ships
    // with the image, so the link belongs in it — appended after the frame, not
    // during build, because it writes to a controller.
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncCaption(link);
        // Only for readers whose recaps are *already* published: a reader who
        // has moved timezone would otherwise keep having their windows cut on
        // the clock they published under. The unpublished case needs nothing
        // here — `publishRecaps` sends the offset itself on the first share,
        // and firing this on open would PATCH the server merely because
        // somebody looked at the share sheet.
        if (identity?.recapsVisible ?? false) syncUtcOffsetIfChanged(ref);
      });
    }
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
      card: PeriodShareCard(
        data: widget.dataBuilder(_nameBooks),
        format: _format,
        // Printed on the image itself, so a forwarded screenshot still leads
        // somewhere. Without the scheme: nobody types "https://".
        linkLine: link?.replaceFirst(RegExp(r'^https?://'), ''),
      ),
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
          _RecapLinkBlock(
            identity: identity,
            link: link,
            onCopy: () => _copyLink(link!),
            onClaimUsername: () {
              Navigator.of(context).pop();
              context.push(Routes.profile);
            },
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
      captionLabel: l10n.insightsShareCaptionLabel,
      captionController: _caption,
      onBeforeShare: _publishBeforeShare,
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

/// The recap link, and the one decision behind it.
///
/// Three states, and the reason there are three: a shared recap is a *page* on
/// kitabi.in, not a picture, so it needs the reader's own yes — and a reader
/// with no handle has nothing to build a URL from. Nothing here happens by
/// tapping Share; the link only exists once the reader has said so, and the
/// switch that undoes it lives on the profile screen, not only in this sheet.
class _RecapLinkBlock extends StatelessWidget {
  const _RecapLinkBlock({
    required this.identity,
    required this.link,
    required this.onCopy,
    required this.onClaimUsername,
  });

  final RecapIdentity? identity;
  final String? link;
  final VoidCallback onCopy;
  final VoidCallback onClaimUsername;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Still resolving, and offline it resolves from key_values rather than
    // never — but until it has, showing nothing beats showing the wrong thing.
    if (identity == null) return const SizedBox.shrink();

    if (link != null) {
      // The URL, plainly, plus what it will mean. A reader who has not
      // published yet sees the same row — sharing is what publishes it, so
      // the sentence under it is the notice, shown before the Share button is
      // tapped rather than as a snackbar after (8 Sep 2026).
      final live = identity!.recapsVisible;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 14, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.shareRecapLinkLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      Text(
                        link!.replaceFirst(RegExp(r'^https?://'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy, size: 15, color: AppColors.inkSoft),
                  tooltip: l10n.insightsShareCopyCaption,
                  visualDensity: VisualDensity.compact,
                  onPressed: onCopy,
                ),
              ],
            ),
            Text(
              live ? l10n.shareRecapLinkHint : l10n.shareRecapLinkOnShare,
              style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft, height: 1.3),
            ),
          ],
        ),
      );
    }

    // No handle — there is nothing to build a URL from, so the honest offer is
    // to go and pick one rather than a link that cannot exist.
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onClaimUsername,
        icon: Icon(Icons.alternate_email, size: 15, color: AppColors.oxblood),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.oxblood,
          visualDensity: VisualDensity.compact,
        ),
        label: Text(
          l10n.shareRecapNeedsUsername,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
