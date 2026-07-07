import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/haptics.dart';
import '../../../core/share_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/person_link.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/notifications/notification_service.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../lending/lending_format.dart';
import '../../lending/presentation/lend_sheet.dart';
import '../../lending/reminder.dart';
import '../../share/presentation/share_book_sheet.dart';
import '../cover_upload.dart';
import '../reading_status.dart';
import '../providers/library_providers.dart';

/// S6 — book detail. Reached with a Work id (shared data: title, authors,
/// genres, aggregate rating) and an Edition id (this specific printing:
/// cover, pages, ISBN, publisher) — feature-map.md rule 17.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.workId, required this.editionId});

  final String workId;
  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workProvider(workId));
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Stack(
          children: [
            work.when(
              loading: () => ListSkeleton(),
              error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(workProvider(workId))),
              data: (body) => _BookDetailBody(work: body, editionId: editionId),
            ),
            Positioned(top: 4, left: 8, child: _BackButton()),
          ],
        ),
      ),
    );
  }
}

/// A floating back control for the full-screen book page (it has no app bar).
/// Pops when there's a screen to return to; otherwise — e.g. the page was opened
/// straight from a share link — goes Home so the reader is never stranded.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.arrow_back, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _BookDetailBody extends ConsumerWidget {
  const _BookDetailBody({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  Map<String, dynamic>? get _edition {
    final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return editions.where((e) => e['id'] == editionId).firstOrNull ?? editions.firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final edition = _edition;
    final entry = ref.watch(libraryEntryProvider(editionId));
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final genres = (work['genres'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final publisher = edition?['publisher'] as Map<String, dynamic>?;

    return ListView(
      children: [
        Container(
          color: AppColors.paperDeep,
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppColors.ink),
                onPressed: () => context.pop(),
                padding: EdgeInsets.zero,
              ),
              SizedBox(width: 4),
              Column(
                children: [
                  _CoverUploader(
                    editionId: editionId,
                    title: work['title'] as String,
                    author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                    coverUrl: edition?['cover_url'] as String?,
                    workId: work['id'] as String,
                  ),
                  SizedBox(height: 8),
                  _CoverUploader(
                    editionId: editionId,
                    coverUrl: edition?['back_cover_url'] as String?,
                    workId: work['id'] as String,
                    back: true,
                    width: 40,
                    height: 58,
                  ),
                ],
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work['title'] as String,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (authors.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            context.push(Routes.authorBrowsePath(authors.first['id'] as String)),
                        child: Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (authors.first['image_url'] != null) ...[
                                CircleAvatar(
                                  radius: 9,
                                  backgroundColor: AppColors.goldSoft,
                                  foregroundImage:
                                      NetworkImage(authors.first['image_url'] as String),
                                ),
                                SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  authors.first['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.oxblood,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (work['first_publish_year'] != null)
                      Text(
                        '${work['first_publish_year']}',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    if (publisher != null)
                      GestureDetector(
                        onTap: () => context
                            .push(Routes.publisherBrowsePath(publisher['id'] as String)),
                        child: Text(
                          publisher['name'] as String,
                          style: TextStyle(color: AppColors.oxblood, fontSize: 12),
                        ),
                      ),
                    if (edition?['page_count'] != null)
                      Text(
                        '${edition!['page_count']} pp',
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    if (edition?['language'] != null)
                      Text(
                        edition!['language'] as String,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                      ),
                    SizedBox(height: 4),
                    _RatingRow(workId: work['id'] as String),
                  ],
                ),
              ),
              _ShareButton(work: work, edition: edition),
              _LibraryEntryMenu(editionId: editionId),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(13, 10, 13, 24),
          child: entry.when(
            loading: () => Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('$err')),
            data: (libraryEntry) => libraryEntry == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AddToLibraryButton(work: work, edition: edition ?? {'id': editionId}),
                      // A borrowed (unowned) book still shows its history —
                      // "from Anu · out now", close-out action and all.
                      SizedBox(height: 8),
                      _LendingCard(editionId: editionId),
                    ],
                  )
                : _OwnedBookSections(entry: libraryEntry, workId: work['id'] as String),
          ),
        ),
        // [WIRED] Where to buy — dormant until an edition carries buy_links
        // (external retailers). Invisible otherwise, so no rewrite when store
        // links are populated.
        if (((edition?['buy_links'] as List?) ?? const []).isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(13, 0, 13, 8),
            child: _BuySection(
              links: (edition!['buy_links'] as List).cast<Map<String, dynamic>>(),
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final genre in genres)
                      Chip(
                        label: Text(genre['name'] as String, style: TextStyle(fontSize: 10)),
                        backgroundColor: AppColors.card,
                        side: BorderSide(color: AppColors.line),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
              if (edition?['isbn'] != null)
                Text(
                  AppLocalizations.of(context)!.bookIsbnLabel(edition!['isbn'] as String),
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 10),
                ),
            ],
          ),
        ),
        SizedBox(height: 20),
        _EditionsSection(work: work, currentEditionId: editionId),
        _TranslationsSection(work: work),
        SizedBox(height: 24),
      ],
    );
  }
}

/// Section header used by the editions/translations lists.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 1,
        color: AppColors.inkSoft,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Every edition (printing/ISBN) of this Work, tappable to view, plus an
/// "Add another edition" entry — the edition-level "real bookshelf" feel.
class _EditionsSection extends ConsumerWidget {
  const _EditionsSection({required this.work, required this.currentEditionId});

  final Map<String, dynamic> work;
  final String currentEditionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final workId = work['id'] as String;
    final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(13, 0, 13, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: l10n.bookEditionsSection),
          SizedBox(height: 4),
          for (final e in editions)
            _EditionRow(
              edition: e,
              isCurrent: e['id'] == currentEditionId,
              onTap: e['id'] == currentEditionId
                  ? null
                  : () => context.push(Routes.bookDetailPath(workId, e['id'] as String)),
            ),
          SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.oxblood,
              padding: EdgeInsets.symmetric(vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              final added = await context.push<bool>(
                Routes.catalogAddEdition,
                extra: {'workId': workId, 'title': work['title'] as String?},
              );
              if (added == true && context.mounted) {
                ref.invalidate(workProvider(workId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.bookEditionAdded)),
                );
              }
            },
            icon: Icon(Icons.add, size: 18),
            label: Text(l10n.bookAddEdition),
          ),
        ],
      ),
    );
  }
}

class _EditionRow extends StatelessWidget {
  const _EditionRow({required this.edition, required this.isCurrent, required this.onTap});

  final Map<String, dynamic> edition;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final format = edition['format'] as String?;
    final isbn = edition['isbn'] as String?;
    final language = edition['language'] as String?;
    final parts = [
      ?format,
      ?language,
      if (isbn != null) 'ISBN $isbn',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.bookmark : Icons.menu_book_outlined,
              size: 16,
              color: isCurrent ? AppColors.oxblood : AppColors.inkSoft,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                parts.isEmpty ? 'Edition' : parts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (!isCurrent) Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Works linked to this one as translations (shared translation group), each
/// tappable to cross-navigate, plus a "Link a translation" entry.
class _TranslationsSection extends ConsumerWidget {
  const _TranslationsSection({required this.work});

  final Map<String, dynamic> work;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final workId = work['id'] as String;
    final picked = await context.push<Map<String, dynamic>>(Routes.workPicker, extra: workId);
    if (picked == null || !context.mounted) return;
    final otherId = picked['id'] as String?;
    if (otherId == null) return;
    try {
      await ref.read(apiClientProvider).linkTranslation(workId, otherId);
      if (!context.mounted) return;
      ref.invalidate(workProvider(workId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bookTranslationLinked)),
      );
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final translations = (work['translations'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(13, 0, 13, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(label: l10n.bookTranslationsSection),
          SizedBox(height: 4),
          for (final t in translations)
            _TranslationRow(
              translation: t,
              onTap: () {
                final ed = t['edition'] as Map<String, dynamic>?;
                if (ed != null) {
                  context.push(Routes.bookDetailPath(t['id'] as String, ed['id'] as String));
                }
              },
            ),
          SizedBox(height: 4),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.oxblood,
              padding: EdgeInsets.symmetric(vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _link(context, ref),
            icon: Icon(Icons.link, size: 18),
            label: Text(l10n.bookLinkTranslation),
          ),
        ],
      ),
    );
  }
}

class _TranslationRow extends StatelessWidget {
  const _TranslationRow({required this.translation, required this.onTap});

  final Map<String, dynamic> translation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = translation['title'] as String? ?? '';
    final edition = translation['edition'] as Map<String, dynamic>?;
    final language = edition?['language'] as String?;
    final authors = (translation['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final subtitle = language ?? (authors.isNotEmpty ? authors.first['name'] as String? : null);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            TypesetCover(
              title: title,
              author: authors.isNotEmpty ? authors.first['name'] as String? : null,
              coverUrl: edition?['cover_url'] as String?,
              width: 28,
              height: 42,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// The book-detail cover — tappable to photograph your own copy (S7b "⇧ upload a
/// photo"), with a small camera badge. Handles both the front (`back == false`,
/// with a typeset fallback) and the back (`back == true`, an "add back" tile when
/// empty). Uploads to Supabase Storage, points the edition's front/back cover_url
/// at it, and refreshes.
class _CoverUploader extends ConsumerStatefulWidget {
  const _CoverUploader({
    required this.editionId,
    required this.coverUrl,
    required this.workId,
    this.title,
    this.author,
    this.back = false,
    this.width = 58,
    this.height = 84,
  });

  final String editionId;
  final String? title;
  final String? author;
  final String? coverUrl;
  final String workId;
  final bool back;
  final double width;
  final double height;

  @override
  ConsumerState<_CoverUploader> createState() => _CoverUploaderState();
}

class _CoverUploaderState extends ConsumerState<_CoverUploader> {
  bool _busy = false;

  Future<void> _upload() async {
    if (_busy) return;
    final source = await showImageSourceSheet(context);
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await pickAndUploadCover(
        ref,
        editionId: widget.editionId,
        source: source,
        back: widget.back,
      );
      if (url != null) {
        ref.invalidate(workProvider(widget.workId));
        ref.invalidate(cachedBookProvider(widget.editionId));
        messenger.showSnackBar(SnackBar(content: Text(l10n.coverUploaded)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.coverUploadFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final Widget preview;
    if (widget.back) {
      // No typeset fallback for a back cover — show the photo, or an "add" tile.
      preview = widget.coverUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                widget.coverUrl!,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
              ),
            )
          : Container(
              width: widget.width,
              height: widget.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                l10n.bookAddBackCover,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 9),
              ),
            );
    } else {
      preview = TypesetCover(
        title: widget.title ?? '…',
        author: widget.author,
        coverUrl: widget.coverUrl,
        width: widget.width,
        height: widget.height,
      );
    }

    return GestureDetector(
      onTap: _upload,
      child: Stack(
        children: [
          preview,
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.oxblood, shape: BoxShape.circle),
              child: _busy
                  ? SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.paper),
                    )
                  : Icon(Icons.photo_camera, size: 11, color: AppColors.paper),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingRow extends ConsumerWidget {
  const _RatingRow({required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rating = ref.watch(ratingProvider(workId));
    final value = rating.valueOrNull?.value ?? 0;

    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () async {
              Haptics.selection();
              final repo = await ref.read(ratingsRepositoryProvider.future);
              await repo.setRating(workId, i);
              ref.invalidate(ratingProvider(workId));
            },
            child: Icon(
              i <= value ? Icons.star : Icons.star_border,
              size: 16,
              color: AppColors.gold,
            ),
          ),
        SizedBox(width: 6),
        Text(l10n.bookYourRating, style: TextStyle(color: AppColors.inkSoft, fontSize: 10)),
      ],
    );
  }
}

class _ShareButton extends ConsumerWidget {
  const _ShareButton({required this.work, required this.edition});

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workId = work['id'] as String;
    return IconButton(
      icon: Icon(Icons.ios_share, color: AppColors.oxblood),
      onPressed: () {
        final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final rating = ref.read(ratingProvider(workId)).valueOrNull;
        final review = ref.read(reviewProvider(workId)).valueOrNull;
        // Catalog average until the user has rated it (feature-map S6c).
        final catalog = (work['aggregate_rating'] as num?)?.toDouble() ??
            (work['translation_group_rating'] as num?)?.toDouble();
        showShareBookSheet(
          context,
          title: work['title'] as String,
          author: authors.isNotEmpty ? authors.first['name'] as String : '',
          shareUrl: bookShareUrl(workId),
          coverUrl: edition?['cover_url'] as String?,
          blurb: work['description'] as String?,
          catalogRating: catalog,
          personalRating: rating?.value,
          personalReview: review?.body,
        );
      },
    );
  }
}

/// [WIRED] "Where to buy" — lists every external retailer an edition is
/// available at (Amazon, Flipkart, …), each opening its store link in the
/// browser. Shown only when the edition carries buy_links.
class _BuySection extends StatelessWidget {
  const _BuySection({required this.links});

  final List<Map<String, dynamic>> links;

  Future<void> _open(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookBuyFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final valid = [
      for (final link in links)
        if ((link['url'] as String?)?.isNotEmpty ?? false) link,
    ];
    if (valid.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bookBuySection.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.inkSoft,
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in valid)
              OutlinedButton.icon(
                onPressed: () => _open(context, link['url'] as String),
                icon: Icon(Icons.shopping_bag_outlined, size: 16, color: AppColors.oxblood),
                label: Text(
                  (link['retailer'] as String?)?.trim().isNotEmpty ?? false
                      ? link['retailer'] as String
                      : l10n.bookBuySection,
                  style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(side: BorderSide(color: AppColors.gold)),
              ),
          ],
        ),
      ],
    );
  }
}

class _LibraryEntryMenu extends ConsumerWidget {
  const _LibraryEntryMenu({required this.editionId});

  final String editionId;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String entryId) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookRemoveFromLibrary),
        content: Text(l10n.bookRemoveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.bookRemoveFromLibrary,
              style: TextStyle(color: AppColors.oxbloodDeep),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.remove(entryId);
    ref.invalidate(libraryEntryProvider(editionId));
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(libraryEntryProvider(editionId));
    final current = entry.valueOrNull;
    if (current == null) return SizedBox.shrink();

    return Column(
      children: [
        IconButton(
          icon: Icon(
            current.isFavorite ? Icons.star : Icons.star_border,
            color: AppColors.gold,
          ),
          onPressed: () async {
            Haptics.selection();
            final repo = await ref.read(libraryRepositoryProvider.future);
            await repo.setFavorite(current.id, !current.isFavorite);
            ref.invalidate(libraryEntryProvider(editionId));
          },
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: AppColors.inkSoft),
          onPressed: () => _confirmRemove(context, ref, current.id),
        ),
      ],
    );
  }
}

class _AddToLibraryButton extends ConsumerWidget {
  const _AddToLibraryButton({required this.work, required this.edition});

  final Map<String, dynamic> work;
  final Map<String, dynamic> edition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editionId = edition['id'] as String;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () async {
          // Cache before creating the entry so the grid/home cover tiles that
          // rebuild on the insert already find the catalog data (rule 2).
          await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
          final repo = await ref.read(libraryRepositoryProvider.future);
          await repo.add(editionId: editionId);
          ref.invalidate(libraryEntryProvider(editionId));
        },
        child: Text(AppLocalizations.of(context)!.bookAddToLibrary),
      ),
    );
  }
}

class _OwnedBookSections extends ConsumerWidget {
  const _OwnedBookSections({required this.entry, required this.workId});

  final LibraryEntry entry;
  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            AppLocalizations.of(context)!.bookYourCopy.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        _StatusPicker(entry: entry),
        SizedBox(height: 8),
        _ProgressCard(entry: entry),
        SizedBox(height: 8),
        _ReviewCard(entry: entry, workId: workId),
        SizedBox(height: 8),
        _NotesCard(entry: entry),
        SizedBox(height: 8),
        _LendingCard(entry: entry, editionId: entry.editionId),
        SizedBox(height: 8),
        _TagsSection(entry: entry),
      ],
    );
  }
}

class _StatusPicker extends ConsumerWidget {
  const _StatusPicker({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final status in readingStatuses)
          GestureDetector(
            onTap: () async {
              Haptics.selection();
              final repo = await ref.read(libraryRepositoryProvider.future);
              await repo.updateStatus(entry.id, status);
              if (status == 'read' && entry.finishDate == null) {
                await repo.updateProgress(entry.id, finishDate: DateTime.now());
              }
              ref.invalidate(libraryEntryProvider(entry.editionId));
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: entry.status == status ? AppColors.oxblood : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.status == status ? AppColors.oxblood : AppColors.line,
                ),
              ),
              child: Text(
                readingStatusLabel(status),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: entry.status == status ? AppColors.paper : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.borderColor, this.leftBorder});

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final Color? leftBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          top: BorderSide(color: borderColor ?? AppColors.line),
          bottom: BorderSide(color: borderColor ?? AppColors.line),
          right: BorderSide(color: borderColor ?? AppColors.line),
          left: BorderSide(color: leftBorder ?? borderColor ?? AppColors.line, width: leftBorder != null ? 3 : 1),
        ),
      ),
      child: child,
    );
  }
}

class _ProgressCard extends ConsumerWidget {
  const _ProgressCard({required this.entry});

  final LibraryEntry entry;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.currentPage?.toString() ?? '');
    final page = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookEditProgress),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.bookCurrentPage),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (page == null) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    final needsStartDate = entry.startDate == null;
    await repo.updateProgress(
      entry.id,
      currentPage: page,
      startDate: needsStartDate ? DateTime.now() : null,
    );
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Total pages come from the edition (via the offline cache), not the current
    // page — the old code passed currentPage as both, so it read "p. 50 of 50".
    final total = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull?.pageCount;
    final page = entry.currentPage;
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookProgressLabel,
                  style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                ),
                Text(
                  page == null
                      ? '—'
                      : (total != null && total > 0
                          // "p. 302 of 724 · 42%" — pages first, never a bare
                          // percentage (docs/screen-design.md).
                          ? l10n.bookProgressValue(
                              page, total, ((page / total) * 100).round().clamp(0, 100))
                          : l10n.bookProgressPage(page)),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookStartedLabel,
                  style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                ),
                Text(
                  entry.startDate != null
                      ? '${entry.startDate!.day}/${entry.startDate!.month}/${entry.startDate!.year}'
                      : l10n.bookNotStarted,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit, size: 16, color: AppColors.oxblood),
            onPressed: () => _edit(context, ref),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.entry, required this.workId});

  final LibraryEntry entry;
  final String workId;

  Future<void> _edit(BuildContext context, WidgetRef ref, Review? current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: current?.body ?? '');
    var visible = current?.visible ?? false;
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.bookEditReview),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, maxLines: 4, autofocus: true),
              Row(
                children: [
                  Expanded(child: Text(l10n.bookReviewVisibilityPublic)),
                  Switch(
                    value: visible,
                    onChanged: (v) => setState(() => visible = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, (controller.text, visible)),
              child: Text(l10n.bookSave),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$1.trim().isEmpty) return;
    final repo = await ref.read(reviewsRepositoryProvider.future);
    await repo.upsert(workId, body: result.$1.trim(), visible: result.$2);
    ref.invalidate(reviewProvider(workId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final review = ref.watch(reviewProvider(workId));
    final current = review.valueOrNull;

    return GestureDetector(
      onTap: () => _edit(context, ref, current),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.bookReviewLabel,
                    style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                  ),
                ),
                if (current != null)
                  Text(
                    current.visible
                        ? l10n.bookReviewVisibilityPublic
                        : l10n.bookReviewVisibilityPrivate,
                    style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                  ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              current?.body ?? l10n.bookReviewEmpty,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12.5,
                color: current != null ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends ConsumerWidget {
  const _NotesCard({required this.entry});

  final LibraryEntry entry;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.notes ?? '');
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookEditNotes),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (notes == null) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateNotes(entry.id, notes);
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => _edit(context, ref),
      child: _Card(
        color: Color(0xFFF6EEDC),
        borderColor: Color(0xFFE8DCC0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock, size: 10, color: AppColors.inkSoft),
                SizedBox(width: 4),
                Text(
                  l10n.bookNotesLabel,
                  style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 0.5),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              (entry.notes?.isNotEmpty ?? false) ? entry.notes! : l10n.bookNotesEmpty,
              style: TextStyle(
                fontSize: 12.5,
                color: (entry.notes?.isNotEmpty ?? false) ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection({required this.entry});

  final LibraryEntry entry;

  Future<void> _addTag(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookNewTagTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l10n.bookNewTagHint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    final repo = await ref.read(tagsRepositoryProvider.future);
    final allTags = await ref.read(allTagsProvider.future);
    final existing = allTags.where((t) => t.name.toLowerCase() == name.trim().toLowerCase());
    final tagId = existing.isNotEmpty ? existing.first.id : await repo.createTag(name.trim());
    await repo.assign(entry.id, tagId);
    ref.invalidate(libraryTagsProvider(entry.id));
    ref.invalidate(allTagsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final assignments = ref.watch(libraryTagsProvider(entry.id));
    final allTags = ref.watch(allTagsProvider);
    final tagNames = {for (final t in allTags.valueOrNull ?? <PersonalTag>[]) t.id: t.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bookTagsLabel,
          style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
        ),
        SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final assignment in assignments.valueOrNull ?? <LibraryEntryTag>[])
              if (tagNames[assignment.tagId] != null)
                Chip(
                  label: Text(tagNames[assignment.tagId]!, style: TextStyle(fontSize: 11)),
                  onDeleted: () async {
                    final repo = await ref.read(tagsRepositoryProvider.future);
                    await repo.unassign(assignment.id);
                    ref.invalidate(libraryTagsProvider(entry.id));
                  },
                  backgroundColor: AppColors.goldSoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ActionChip(
              label: Text(l10n.bookAddTag, style: TextStyle(fontSize: 11)),
              onPressed: () => _addTag(context, ref),
              backgroundColor: AppColors.card,
              side: BorderSide(color: AppColors.line),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _LendingCard extends ConsumerWidget {
  const _LendingCard({required this.editionId, this.entry});

  /// Owned copy — enables the Lend action; null for a book you only borrowed.
  final LibraryEntry? entry;
  final String editionId;

  Future<void> _lend(BuildContext context, WidgetRef ref, LibraryEntry entry) async {
    // Warn before lending a book you're still reading — an easy way to lose your
    // spot / your copy mid-read.
    if (entry.status == 'reading') {
      final l10n = AppLocalizations.of(context)!;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.lendReadingWarnTitle),
          content: Text(l10n.lendReadingWarnBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.lendReadingWarnConfirm),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    // The lend flow (S9) is a bottom sheet; pull the cached book so it can show
    // the cover + title the same way the ledger does.
    if (!context.mounted) return;
    final book = await ref.read(cachedBookProvider(entry.editionId).future);
    if (!context.mounted) return;
    await showLendSheet(
      context,
      libraryEntryId: entry.id,
      bookTitle: book?.title ?? '',
      author: book?.authorNames,
      coverUrl: book?.coverUrl,
    );
  }

  Future<void> _markReturned(WidgetRef ref, String lendingId) async {
    Haptics.success();
    final repo = await ref.read(lendingRepositoryProvider.future);
    await repo.markReturned(lendingId, DateTime.now());
    await ref.read(notificationServiceProvider).cancel(reminderIdForRecord(lendingId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref
        .watch(bookLendingHistoryProvider((entryId: entry?.id, editionId: editionId)))
        .valueOrNull ??
        const <LendingRecord>[];
    // The active loan of the copy I own — drives the header + primary action.
    final current = history
        .where((r) => r.direction != 'borrowed' && r.returnedDate == null)
        .firstOrNull;

    // A book that's merely borrowed (not owned) only earns the card once it
    // actually has history — no "Not lent out" noise on catalog pages.
    if (entry == null && history.isEmpty) return SizedBox.shrink();

    return _Card(
      leftBorder: AppColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry != null)
            Row(
            children: [
              Icon(Icons.swap_horiz, size: 16, color: AppColors.gold),
              SizedBox(width: 8),
              Expanded(
                child: current != null
                    ? Row(
                        children: [
                          Text(
                            '${l10n.bookLendingWithFragment} ',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          Flexible(
                            child: PersonLink(
                              current.borrowerName,
                              userId: current.borrowerUserId,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        l10n.bookLendingNotLentOut,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
              ),
              if (entry != null)
                TextButton(
                  onPressed: current != null
                      ? () => _markReturned(ref, current.id)
                      : () => _lend(context, ref, entry!),
                  child: Text(
                    current != null ? l10n.bookMarkReturnedAction : l10n.bookLendAction,
                    style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          // The detailed ledger for this book — every loan either way,
          // newest first, counterparty names as doors.
          if (history.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              l10n.bookLendingHistoryLabel.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
              ),
            ),
            SizedBox(height: 2),
            for (final r in history) _LendingHistoryRow(record: r, onReturned: _markReturned),
          ],
        ],
      ),
    );
  }
}

/// One line of the book's lending history: direction, who (tappable), when,
/// and how it ended — a moss "Returned ✓" or a gold "Out now" stamp. Borrowed
/// rows that are still open close out right here ("Returned it").
class _LendingHistoryRow extends ConsumerWidget {
  const _LendingHistoryRow({required this.record, required this.onReturned});

  final LendingRecord record;
  final Future<void> Function(WidgetRef, String) onReturned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final borrowed = record.direction == 'borrowed';
    final returned = record.returnedDate != null;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                borrowed ? Icons.south_west : Icons.north_east,
                size: 11,
                color: borrowed ? AppColors.slate : AppColors.gold,
              ),
              SizedBox(width: 6),
              Text(
                '${borrowed ? l10n.lendingFromFragment : l10n.lendingToFragment} ',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
              ),
              Flexible(child: PersonLink(record.borrowerName, userId: record.borrowerUserId)),
              Flexible(
                child: Text(
                  returned
                      ? ' ${l10n.lendingRangeFragment(fmtLendingDate(record.lentDate), fmtLendingDate(record.returnedDate!))}'
                      : ' ${l10n.lendingSinceFragment(fmtLendingDate(record.lentDate))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                ),
              ),
              SizedBox(width: 6),
              Spacer(),
              if (returned)
                _HistoryStamp(label: l10n.lendingReturnedStamp, color: AppColors.moss)
              else if (borrowed)
                GestureDetector(
                  onTap: () => onReturned(ref, record.id),
                  child: _HistoryStamp(label: l10n.lendingReturnedIt, color: AppColors.oxblood),
                )
              else
                _HistoryStamp(label: l10n.bookLendingOutStamp, color: AppColors.gold),
            ],
          ),
          if (record.note != null && record.note!.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: 17, top: 1),
              child: Text(
                record.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontStyle: FontStyle.italic,
                  fontSize: 10.5,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryStamp extends StatelessWidget {
  const _HistoryStamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
