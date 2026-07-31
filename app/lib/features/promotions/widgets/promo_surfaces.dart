import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/promotions_providers.dart';

/// The banner and card surfaces (docs/promotions-plan.md §2).
///
/// Both are drawn entirely by Kitabi in the Reading Room palette — an
/// advertiser supplies an image, a headline, two lines and a link, never the
/// frame. That's the difference between a promotion and an ad slot, and it's
/// why the app can carry one without looking cheap.

/// "From Kitabi", or "Sponsored · {name}". Derived from the sponsor field, so
/// a disclosure can't be forgotten by whoever wrote the campaign at 11pm.
String promoLabel(AppLocalizations l10n, CachedPromotion promo) =>
    promo.sponsor == null ? l10n.promoFromKitabi : l10n.promoSponsored(promo.sponsor!);

/// A thin strip under the Home header. One line, truncated rather than
/// wrapped, so a long headline can never grow it and push the currently-reading
/// card off a small screen.
class PromoBanner extends ConsumerWidget {
  const PromoBanner({super.key, required this.promo});

  final CachedPromotion promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sponsored = promo.sponsor != null;
    final accent = sponsored ? AppColors.slate : AppColors.gold;

    return _CountImpression(
      promo: promo,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => openPromotion(context, ref, promo),
          child: Container(
            decoration: BoxDecoration(
              color: sponsored ? AppColors.card : AppColors.goldSoft,
              borderRadius: BorderRadius.circular(11),
              // Uniform border + clip + a strip child, NOT a non-uniform
              // Border() with a borderRadius — that throws at paint time and
              // renders a blank box (CLAUDE.md, 21 Jul 2026).
              border: Border.all(color: sponsored ? AppColors.line : AppColors.gold),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            promoLabel(l10n, promo).toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: sponsored ? AppColors.slate : AppColors.goldInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            promo.headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (promo.dismissible)
                    _DismissButton(promo: promo, color: AppColors.inkSoft),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full block in the Home stream, in one of three shapes — book-led,
/// image-led, or text-only. Text-only is also the fallback when an image
/// fails, so a dead URL degrades instead of leaving a grey box.
class PromoCard extends ConsumerWidget {
  const PromoCard({super.key, required this.promo});

  final CachedPromotion promo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sponsored = promo.sponsor != null;
    final dark = promo.cardStyle == 'text';
    final hasImage = promo.cardStyle == 'image' && (promo.imageUrl?.isNotEmpty ?? false);

    return _CountImpression(
      promo: promo,
      child: GestureDetector(
        onTap: () => openPromotion(context, ref, promo),
        child: Container(
          decoration: BoxDecoration(
            color: dark ? AppColors.darkPanel : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: dark ? AppColors.darkPanel : AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage) _PromoImage(promo: promo),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        promoLabel(l10n, promo).toUpperCase(),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: dark
                              ? AppColors.nightGold
                              : (sponsored ? AppColors.slate : AppColors.gold),
                        ),
                      ),
                    ),
                    if (promo.dismissible)
                      _DismissButton(
                        promo: promo,
                        color: dark ? AppColors.onDarkSoft : AppColors.stampGrey,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 4, 11, 12),
                child: promo.cardStyle == 'book'
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PromoCover(promo: promo),
                          const SizedBox(width: 10),
                          Expanded(child: _CardBody(promo: promo, dark: dark)),
                        ],
                      )
                    : _CardBody(promo: promo, dark: dark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.promo, required this.dark});

  final CachedPromotion promo;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          promo.headline,
          style: GoogleFonts.fraunces(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.3,
            color: dark ? AppColors.onDark : AppColors.ink,
          ),
        ),
        if (promo.body != null && promo.body!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            promo.body!,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: dark ? AppColors.onDarkSoft : AppColors.inkSoft,
            ),
          ),
        ],
        if (promo.ctaLabel != null && promo.ctaLabel!.isNotEmpty) ...[
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: dark ? AppColors.gold : AppColors.oxblood,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${promo.ctaLabel!} ›',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: dark ? AppColors.darkPanel : AppColors.onDark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PromoImage extends StatelessWidget {
  const _PromoImage({required this.promo});

  final CachedPromotion promo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: CachedNetworkImage(
        imageUrl: promo.imageUrl!,
        fit: BoxFit.cover,
        // No grey box on failure: an image that 404s months after the campaign
        // was written must degrade to the text shape, not to a hole.
        errorWidget: (_, _, _) => const SizedBox.shrink(),
        placeholder: (_, _) => Container(color: AppColors.paperDeep),
      ),
    );
  }
}

class _PromoCover extends StatelessWidget {
  const _PromoCover({required this.promo});

  final CachedPromotion promo;

  @override
  Widget build(BuildContext context) {
    // The *book's* cover and title, not the campaign's headline. Drawing the
    // headline through TypesetCover produced a generated cover of the ad copy
    // sitting where the book should be (owner report, 31 Jul 2026). The server
    // resolves these because the reader usually doesn't own the promoted book,
    // so it isn't in the local catalog cache to look up. A campaign image, if
    // one was uploaded, still wins — that's the deliberate override.
    return TypesetCover(
      title: promo.bookTitle ?? promo.headline,
      author: promo.bookAuthors,
      coverUrl: promo.imageUrl ?? promo.bookCoverUrl,
      width: 48,
      height: 70,
    );
  }
}

class _DismissButton extends ConsumerWidget {
  const _DismissButton({required this.promo, required this.color});

  final CachedPromotion promo;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.promoDismiss,
      child: InkWell(
        onTap: () async {
          Haptics.selection();
          // Capture the handles BEFORE the await: dismissing removes this
          // widget from the tree on the next frame, taking its ref with it
          // (same shape as the quick-stop bug, 19 Jul 2026).
          final repo = ref.read(promotionsRepositoryProvider);
          final messenger = ScaffoldMessenger.maybeOf(context);
          await repo.dismiss(promo);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(l10n.promoDismissed),
              action: SnackBarAction(
                label: l10n.undoAction,
                onPressed: () => repo.undoDismiss(promo),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(Icons.close, size: 15, color: color),
        ),
      ),
    );
  }
}

/// Opens whatever the campaign points at, and records the click.
Future<void> openPromotion(
  BuildContext context,
  WidgetRef ref,
  CachedPromotion promo,
) async {
  final value = promo.actionValue;
  if (promo.actionType == 'none' || value == null || value.isEmpty) return;
  Haptics.selection();
  // Read before any await — the surrounding widget can be rebuilt away.
  final repo = ref.read(promotionsRepositoryProvider);
  final router = GoRouter.of(context);
  unawaited(repo.recordClick(promo));

  if (promo.actionType == 'deep_link' && value.startsWith('/')) {
    router.push(value);
    return;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Records one impression the first time this widget is actually on screen.
///
/// Not on fetch, and not merely on build: Home's `ListView` builds all of its
/// children eagerly, so a card below the fold would otherwise be counted as
/// seen — and every rate in the console would be a lie. Implemented against
/// the enclosing [Scrollable] rather than adding a visibility package, since
/// this is the only place in the app that needs it.
class _CountImpression extends ConsumerStatefulWidget {
  const _CountImpression({required this.promo, required this.child});

  final CachedPromotion promo;
  final Widget child;

  @override
  ConsumerState<_CountImpression> createState() => _CountImpressionState();
}

class _CountImpressionState extends ConsumerState<_CountImpression> {
  bool _counted = false;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_counted || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final screen = MediaQuery.of(context).size.height;
    // Half of it on screen counts as seen — a 2px sliver does not.
    final visible = (bottom.clamp(0.0, screen) - top.clamp(0.0, screen));
    if (visible < box.size.height / 2) return;
    _counted = true;
    _position?.removeListener(_check);
    ref.read(promotionsRepositoryProvider).recordImpression(widget.promo);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
