import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/share_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/image_source_sheet.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/person_link.dart';
import '../../../core/widgets/status_pill.dart';
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
import '../../lending/presentation/sheet_fields.dart';
import '../../lending/reminder.dart';
import '../../share/presentation/share_book_sheet.dart';
import '../cover_upload.dart';
import '../reading_status.dart';
import '../providers/library_providers.dart';
import '../providers/reading_timer_providers.dart';
import 'cover_viewer.dart';
import '../../../core/widgets/net_image.dart';

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

/// Which half of the page is showing below the hero: the reader's own copy,
/// or the shared catalogue record. Tapping the hero's rating row jumps
/// straight to About's reviews.
enum _BookTab { yours, about }

class _BookDetailBody extends ConsumerStatefulWidget {
  const _BookDetailBody({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  @override
  ConsumerState<_BookDetailBody> createState() => _BookDetailBodyState();
}

class _BookDetailBodyState extends ConsumerState<_BookDetailBody> {
  var _tab = _BookTab.yours;

  Map<String, dynamic>? get _edition {
    final editions = (widget.work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return editions.where((e) => e['id'] == widget.editionId).firstOrNull ?? editions.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final editionId = widget.editionId;
    final edition = _edition;
    final entry = ref.watch(libraryEntryProvider(editionId));
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final genres = (work['genres'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final publisher = edition?['publisher'] as Map<String, dynamic>?;
    final workId = work['id'] as String;

    return ListView(
      children: [
        _Frontispiece(
          work: work,
          edition: edition,
          editionId: editionId,
          authors: authors,
          genres: genres,
          publisher: publisher,
          onTapRating: () => setState(() => _tab = _BookTab.about),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(13, 12, 13, 0),
          child: _TabBar(selected: _tab, onChanged: (t) => setState(() => _tab = t)),
        ),
        SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.fromLTRB(13, 0, 13, 24),
          child: switch (_tab) {
            _BookTab.yours => entry.when(
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
                    : _YoursTabContent(
                        entry: libraryEntry,
                        workId: workId,
                        title: work['title'] as String?,
                        author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                        coverUrl: edition?['cover_url'] as String?,
                      ),
              ),
            _BookTab.about => _AboutTabContent(
                work: work,
                edition: edition,
                editionId: editionId,
                genres: genres,
              ),
          },
        ),
      ],
    );
  }
}

/// Segmented Yours/About tabs — same visual language as the lending ledger's
/// and the reader-profile's own segmented controls.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onChanged});

  final _BookTab selected;
  final ValueChanged<_BookTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget tab(_BookTab t, String label) {
      final active = t == selected;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(t),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? AppColors.oxblood : AppColors.line,
                  width: active ? 2 : 1,
                ),
              ),
            ),
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: active ? AppColors.oxblood : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(_BookTab.yours, l10n.bookYoursTab),
        tab(_BookTab.about, l10n.bookAboutTab),
      ],
    );
  }
}

/// Direction A's "Frontispiece" hero — the cover stands on a wash of the
/// book's own derived colour (clamped so a muted cover still reads, and
/// echoed as a solid spine-colour rail down the left edge), with a filled
/// genre chip, a display-set title, the author byline (a door to their
/// page), publisher, a tidy facts line, and the community rating — stars +
/// numeric average + review count, the whole row one plain tap target to
/// the About tab's reviews (no personal rating here; that lives with the
/// reader's own review, in the Yours tab). The front cover carries a
/// smaller back cover peeking from its corner; both remain tap-to-view /
/// tap-to-edit. Share + favourite + remove sit as a top-right cluster (the
/// back button floats separately, top-left).
class _Frontispiece extends ConsumerWidget {
  const _Frontispiece({
    required this.work,
    required this.edition,
    required this.editionId,
    required this.authors,
    required this.genres,
    required this.publisher,
    required this.onTapRating,
  });

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;
  final String editionId;
  final List<Map<String, dynamic>> authors;
  final List<Map<String, dynamic>> genres;
  final Map<String, dynamic>? publisher;
  final VoidCallback onTapRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final workId = work['id'] as String;
    final title = work['title'] as String;
    final authorName = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final tint = TypesetCover.tintFor(title, authorName);
    final accent = TypesetCover.accentFor(title, authorName);
    final front = edition?['cover_url'] as String?;
    final backCover = edition?['back_cover_url'] as String?;
    final pages = <CoverPage>[
      if (front != null) (url: front, label: l10n.coverFrontLabel),
      if (backCover != null) (url: backCover, label: l10n.coverBackLabel),
    ];
    final metaBits = <String>[
      if (work['first_publish_year'] != null) '${work['first_publish_year']}',
      if (edition?['page_count'] != null) l10n.bookPagesShort(edition!['page_count'] as int),
      if (edition?['language'] != null) edition!['language'] as String,
    ];
    final reviewsData = ref.watch(publicReviewsProvider(workId));
    final ratingAverage = (reviewsData.valueOrNull?['rating_average'] as num?)?.toDouble();
    final ratingCount = reviewsData.valueOrNull?['rating_count'] as int? ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, AppColors.paper],
        ),
      ),
      child: Stack(
        children: [
          // A solid spine-colour rail down the left edge — a fixed accent
          // that doesn't depend on the gradient wash reading well.
          Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: accent)),
          Padding(
            padding: EdgeInsets.fromLTRB(21, 6, 10, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 40), // room for the floating back button
                    Spacer(),
                    _ShareButton(work: work, edition: edition),
                    _LibraryEntryMenu(editionId: editionId),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 162,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _CoverUploader(
                            editionId: editionId,
                            title: title,
                            author: authorName,
                            coverUrl: front,
                            workId: workId,
                            width: 104,
                            height: 156,
                            viewerPages: pages,
                            viewerIndex: 0,
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: _CoverUploader(
                              editionId: editionId,
                              coverUrl: backCover,
                              workId: workId,
                              back: true,
                              width: 38,
                              height: 54,
                              viewerPages: pages,
                              viewerIndex: front != null ? 1 : 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (genres.isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                (genres.first['name'] as String).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          SizedBox(height: 5),
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.12),
                          ),
                          if (authorName != null)
                            GestureDetector(
                              onTap: () => context
                                  .push(Routes.authorBrowsePath(authors.first['id'] as String)),
                              child: Padding(
                                padding: EdgeInsets.only(top: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (authors.first['image_url'] != null) ...[
                                      CircleAvatar(
                                        radius: 9,
                                        backgroundColor: AppColors.goldSoft,
                                        foregroundImage: netImageProvider(
                                            authors.first['image_url'] as String),
                                      ),
                                      SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        l10n.bookByAuthor(authorName),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.oxblood,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (publisher != null)
                            Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: GestureDetector(
                                onTap: () => context.push(
                                    Routes.publisherBrowsePath(publisher!['id'] as String)),
                                child: Text(
                                  publisher!['name'] as String,
                                  style: TextStyle(color: AppColors.oxblood, fontSize: 11.5),
                                ),
                              ),
                            ),
                          if (metaBits.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 7),
                              child: Text(
                                metaBits.join('  ·  '),
                                style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                              ),
                            ),
                          if (ratingCount > 0)
                            Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: GestureDetector(
                                onTap: onTapRating,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _Stars(value: ratingAverage ?? 0),
                                    SizedBox(width: 6),
                                    Text(
                                      ratingAverage!.toStringAsFixed(1),
                                      style:
                                          TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      l10n.bookReviewsCount(ratingCount),
                                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                                    ),
                                    Icon(Icons.chevron_right, size: 14, color: AppColors.inkSoft),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only star row for an aggregate (community) rating.
class _Stars extends StatelessWidget {
  const _Stars({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final rounded = value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rounded ? Icons.star : Icons.star_border, size: 14, color: AppColors.gold),
      ],
    );
  }
}

/// "About this book" — the encyclopedia face of the entry: subtitle,
/// description, and the shared facts, with an "Improve this entry" action
/// that opens the catalog edit form. Edits by the book's contributor apply
/// live; anyone else's go to the contributor for approval (the form's save
/// surfaces which happened).
class _AboutSection extends ConsumerWidget {
  const _AboutSection({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final workId = work['id'] as String;
    final subtitle = work['subtitle'] as String?;
    final description = work['description'] as String?;
    final hasDescription = description != null && description.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _SectionHeader(label: l10n.bookAboutSection.toUpperCase())),
            // Wiki-style: anyone can propose an improvement, right here.
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.oxblood,
                padding: EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () async {
                await context.push(Routes.catalogAdd, extra: workId);
                if (context.mounted) ref.invalidate(workProvider(workId));
              },
              icon: Icon(Icons.edit_outlined, size: 14),
              label: Text(l10n.bookImproveEntry, style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              subtitle,
              style: GoogleFonts.fraunces(
                fontStyle: FontStyle.italic,
                fontSize: 13.5,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        Text(
          hasDescription ? description.trim() : l10n.bookDescriptionEmpty,
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: hasDescription ? AppColors.ink : AppColors.inkSoft,
            fontStyle: hasDescription ? FontStyle.normal : FontStyle.italic,
          ),
        ),
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

    return Column(
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

    return Column(
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

/// The book-detail cover. Tapping a cover that has a photo opens the
/// full-screen [showCoverViewer] (front + back, swipe, pinch-zoom) — *editing*
/// lives on the small camera badge only, so looking at your book never drops
/// you into a photo picker. With no photo yet, a tap still starts the upload
/// (there is nothing to view). Handles both the front (`back == false`, with a
/// typeset fallback) and the back (`back == true`, an "add back" tile when
/// empty). Uploads to Supabase Storage, points the edition's front/back
/// cover_url at it, and refreshes.
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
    this.viewerPages = const [],
    this.viewerIndex = 0,
  });

  final String editionId;
  final String? title;
  final String? author;
  final String? coverUrl;
  final String workId;
  final bool back;
  final double width;
  final double height;

  /// Every cover photo of this edition (front first), for the viewer; this
  /// slot's own page sits at [viewerIndex].
  final List<CoverPage> viewerPages;
  final int viewerIndex;

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
              child: netImage(
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

    // A photo exists → tap views it; nothing yet → tap starts the upload.
    final hasPhoto = widget.coverUrl != null && widget.viewerPages.isNotEmpty;
    return GestureDetector(
      onTap: hasPhoto
          ? () => showCoverViewer(
                context,
                pages: widget.viewerPages,
                initialIndex: widget.viewerIndex,
              )
          : _upload,
      child: Stack(
        children: [
          preview,
          Positioned(
            right: 2,
            bottom: 2,
            // The badge is the edit affordance — its own tap target so viewing
            // the cover never opens the picker.
            child: GestureDetector(
              onTap: _upload,
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
          ),
        ],
      ),
    );
  }
}

/// The reader's own 1-5 star rating for this book — lives inside the review
/// card now (the hero only shows the community average).
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
              // Wait for the actual push (never throws, even offline) before
              // refetching the server-computed community aggregate — an
              // immediate invalidate could race ahead of the background sync
              // trigger and refetch the same stale number.
              await ref.read(syncNowProvider)();
              ref.invalidate(publicReviewsProvider(workId));
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

    return Row(
      mainAxisSize: MainAxisSize.min,
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

/// The Yours tab's content: what's yours about this specific copy — status,
/// progress, your review (with your own rating), notes, lending, tags. The
/// shared catalogue record lives in the About tab instead.
class _YoursTabContent extends ConsumerWidget {
  const _YoursTabContent({
    required this.entry,
    required this.workId,
    this.title,
    this.author,
    this.coverUrl,
  });

  final LibraryEntry entry;
  final String workId;
  final String? title;
  final String? author;
  final String? coverUrl;

  /// The `extra` the review editor route needs to show which book it's about.
  Map<String, dynamic> get _reviewExtra =>
      {'title': title, 'author': author, 'coverUrl': coverUrl};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wishlist → owned is the wish coming true — one obvious tap, not a
        // status-chip hunt: flips to "To read" (owned) and celebrates.
        if (entry.status == 'wishlist') ...[
          _GotItButton(entry: entry),
          SizedBox(height: 8),
        ],
        _StatusAndProgressCard(entry: entry, workId: workId, reviewExtra: _reviewExtra),
        SizedBox(height: 8),
        if (entry.status == 'reading') ...[
          _ReadingSessionCard(entry: entry, title: title, author: author),
          SizedBox(height: 8),
        ],
        _ReviewCard(workId: workId, reviewExtra: _reviewExtra),
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

/// The About tab's content: the shared catalogue record, the same for every
/// reader with this book — description, readers' reviews, editions,
/// translations, where to buy.
class _AboutTabContent extends StatelessWidget {
  const _AboutTabContent({
    required this.work,
    required this.edition,
    required this.editionId,
    required this.genres,
  });

  final Map<String, dynamic> work;
  final Map<String, dynamic>? edition;
  final String editionId;
  final List<Map<String, dynamic>> genres;

  @override
  Widget build(BuildContext context) {
    final workId = work['id'] as String;
    final buyLinks = (edition?['buy_links'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AboutSection(work: work),
        if (genres.isNotEmpty || edition?['isbn'] != null) ...[
          SizedBox(height: 10),
          Row(
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
        ],
        SizedBox(height: 20),
        _ReviewsSection(workId: workId),
        SizedBox(height: 20),
        _EditionsSection(work: work, currentEditionId: editionId),
        SizedBox(height: 8),
        _TranslationsSection(work: work),
        if (buyLinks.isNotEmpty) ...[
          SizedBox(height: 16),
          _BuySection(links: buyLinks.cast<Map<String, dynamic>>()),
        ],
      ],
    );
  }
}

/// "I got this book" — moves a wishlist entry onto the real shelf (status
/// 'pending' / To read) in one tap.
class _GotItButton extends ConsumerWidget {
  const _GotItButton({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          Haptics.success();
          final messenger = ScaffoldMessenger.of(context);
          final repo = await ref.read(libraryRepositoryProvider.future);
          await repo.updateStatus(entry.id, 'pending');
          ref.invalidate(libraryEntryProvider(entry.editionId));
          messenger.showSnackBar(SnackBar(content: Text(l10n.bookMovedToLibrary)));
        },
        icon: Icon(Icons.library_add_check_outlined, size: 18),
        label: Text(l10n.bookGotIt),
      ),
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
    // A rounded Border must be uniform (non-uniform colors assert in paint),
    // so the gold accent is a clipped strip laid over the left edge instead
    // of a thicker left BorderSide.
    final card = Container(
      width: double.infinity,
      padding: leftBorder != null ? EdgeInsets.fromLTRB(13, 10, 10, 10) : EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor ?? AppColors.line),
      ),
      child: child,
    );
    if (leftBorder == null) return card;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          card,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: leftBorder!),
          ),
        ],
      ),
    );
  }
}

/// Status + progress, merged into one card: a tappable status pill opens a
/// bottom sheet to change it, sitting directly above the progress bar it
/// governs — replaces the old five-button row + a separate progress card.
class _StatusAndProgressCard extends ConsumerWidget {
  const _StatusAndProgressCard({required this.entry, required this.workId, required this.reviewExtra});

  final LibraryEntry entry;
  final String workId;
  final Map<String, dynamic> reviewExtra;

  /// One gentle, self-dismissing nudge to review a book the moment it's marked
  /// read — and only when there's nothing to lose by ignoring it: no popup at
  /// all if a review or rating already exists (don't irritate the reader).
  /// A bottom sheet, not a snackbar — a snackbar times out mid-decision and
  /// its one-line text can't carry a star row, so tapping a star straight
  /// away was never possible.
  Future<void> _maybePromptReview(BuildContext context, WidgetRef ref) async {
    // Repositories directly, not the autoDispose providers' .future — a
    // read without a listener can be disposed before it resolves.
    final reviewsRepo = await ref.read(reviewsRepositoryProvider.future);
    final ratingsRepo = await ref.read(ratingsRepositoryProvider.future);
    final review = await reviewsRepo.watchForWork(workId).first;
    final rating = await ratingsRepo.watchForWork(workId).first;
    if (review != null || rating != null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FinishedReviewSheet(workId: workId, reviewExtra: reviewExtra),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StatusSheet(current: entry.status),
    );
    if (chosen == null || chosen == entry.status || !context.mounted) return;
    Haptics.selection();
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateStatus(entry.id, chosen);
    if (chosen == 'read' && entry.finishDate == null) {
      await repo.updateProgress(entry.id, finishDate: DateTime.now());
    }
    ref.invalidate(libraryEntryProvider(entry.editionId));
    if (chosen == 'read' && entry.status != 'read' && context.mounted) {
      await _maybePromptReview(context, ref);
    }
  }

  Future<void> _editProgress(BuildContext context, WidgetRef ref) async {
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
    final total = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull?.pageCount;
    final page = entry.currentPage;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _changeStatus(context, ref),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                StatusPill(status: entry.status),
                Spacer(),
                Text(
                  l10n.bookChangeStatus,
                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
                ),
                Icon(Icons.chevron_right, size: 15, color: AppColors.inkSoft),
              ],
            ),
          ),
          SizedBox(height: 11),
          Row(
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
                onPressed: () => _editProgress(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A live-timed reading session on this copy — "Start" opens the full-screen
/// pocket-watch view (`ReadingTimerScreen`); if one's already running here
/// (resumed from the mini-bar or a backgrounded watch face), the card shows
/// a live clock instead and re-opens the same screen rather than starting
/// a second one. Only shown while the book is actually being read.
class _ReadingSessionCard extends ConsumerWidget {
  const _ReadingSessionCard({required this.entry, this.title, this.author});

  final LibraryEntry entry;
  final String? title;
  final String? author;

  void _open(BuildContext context, WidgetRef ref, {required int? pageCount}) {
    Haptics.selection();
    ref.read(activeSessionProvider.notifier).start(entry.id, pageStart: entry.currentPage);
    context.push(
      Routes.readingTimerPath(entry.id),
      extra: {
        'title': title,
        'author': author,
        'currentPage': entry.currentPage,
        'pageCount': pageCount,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final book = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull;
    final active = ref.watch(activeSessionProvider);
    final running = active?.libraryEntryId == entry.id;
    final sessions = ref.watch(_recentSessionsProvider(entry.id)).valueOrNull ?? const [];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _open(context, ref, pageCount: book?.pageCount),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.timerSessionLabel,
                    style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
                  ),
                ),
                if (running)
                  _LiveClock(startedAt: active!.startedAt)
                else
                  ElevatedButton.icon(
                    onPressed: () => _open(context, ref, pageCount: book?.pageCount),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    icon: Icon(Icons.play_arrow, size: 14),
                    label: Text(l10n.timerStart),
                  ),
              ],
            ),
          ),
          if (sessions.isNotEmpty) ...[
            SizedBox(height: 10),
            for (final s in sessions.take(3)) _SessionLogRow(session: s),
          ],
        ],
      ),
    );
  }
}

/// Newest-first, capped client-side — the DAO already orders by startedAt.
final _recentSessionsProvider =
    StreamProvider.autoDispose.family<List<ReadingSession>, String>((ref, entryId) {
  return ref.watch(appDatabaseProvider).readingSessionsDao.watchForEntry(entryId);
});

class _LiveClock extends StatefulWidget {
  const _LiveClock({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: EdgeInsets.only(right: 6),
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold),
        ),
        Text(
          formatClock(DateTime.now().difference(widget.startedAt)),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.oxblood,
          ),
        ),
      ],
    );
  }
}

class _SessionLogRow extends StatelessWidget {
  const _SessionLogRow({required this.session});

  final ReadingSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final date = session.startedAt;
    final today = DateTime.now();
    final label = DateUtils.isSameDay(date, today)
        ? l10n.timerToday
        : DateUtils.isSameDay(date, today.subtract(Duration(days: 1)))
            ? l10n.timerYesterday
            : '${date.day}/${date.month}';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
          ),
          Text(
            formatDuration(Duration(seconds: session.durationSeconds)),
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// The finished-reading popup — one tap on a star saves the rating right
/// there (and syncs before refreshing the hero's aggregate, same as the
/// review card's own rating row); "Write a review" goes deeper into the full
/// editor; "Not now" dismisses without friction. Never re-shown once a
/// rating or review exists for this work (see `_maybePromptReview`).
class _FinishedReviewSheet extends ConsumerStatefulWidget {
  const _FinishedReviewSheet({required this.workId, required this.reviewExtra});

  final String workId;
  final Map<String, dynamic> reviewExtra;

  @override
  ConsumerState<_FinishedReviewSheet> createState() => _FinishedReviewSheetState();
}

class _FinishedReviewSheetState extends ConsumerState<_FinishedReviewSheet> {
  int _stars = 0;
  bool _saving = false;

  Future<void> _rate(int value) async {
    Haptics.selection();
    setState(() {
      _stars = value;
      _saving = true;
    });
    final repo = await ref.read(ratingsRepositoryProvider.future);
    await repo.setRating(widget.workId, value);
    ref.invalidate(ratingProvider(widget.workId));
    await ref.read(syncNowProvider)();
    ref.invalidate(publicReviewsProvider(widget.workId));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetGrabber(),
            SizedBox(height: 10),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.goldSoft),
              child: Icon(Icons.auto_stories, color: Color(0xFF8F681E), size: 22),
            ),
            SizedBox(height: 14),
            Text(
              l10n.reviewFinishedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 6),
            Text(
              l10n.reviewFinishedSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.4),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: _saving ? null : () => _rate(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        i <= _stars ? Icons.star : Icons.star_border,
                        size: 32,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.reviewEditorPath(widget.workId), extra: widget.reviewExtra);
                },
                child: Text(l10n.reviewFinishedAction),
              ),
            ),
            SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.reviewFinishedSkip, style: TextStyle(color: AppColors.inkSoft)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The five reading statuses as a bottom sheet — the current one checked,
/// tap any other to switch and close.
class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetGrabber(),
            Text(l10n.bookStatusSheetTitle, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 6),
            for (final status in readingStatuses)
              InkWell(
                onTap: () => Navigator.of(context).pop(status),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status == current ? AppColors.oxblood : AppColors.line,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          readingStatusLabel(status),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: status == current ? FontWeight.w700 : FontWeight.w500,
                            color: status == current ? AppColors.oxblood : AppColors.ink,
                          ),
                        ),
                      ),
                      if (status == current) Icon(Icons.check, size: 18, color: AppColors.oxblood),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.workId, required this.reviewExtra});

  final String workId;
  final Map<String, dynamic> reviewExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final review = ref.watch(reviewProvider(workId));
    final current = review.valueOrNull;

    // One tap (on the label or body — not the rating stars, which have their
    // own tap targets) opens the dedicated rate & review page; rating + review
    // invalidate themselves on save.
    void openEditor() => context.push(Routes.reviewEditorPath(workId), extra: reviewExtra);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Opaque so the whole label row (not just the text glyphs) opens
          // the editor — the rating row below keeps its own star tap targets
          // and is deliberately left outside this detector.
          GestureDetector(
            onTap: openEditor,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(
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
            ),
          ),
          _RatingRow(workId: workId),
          GestureDetector(
            onTap: openEditor,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                current?.body ?? l10n.bookReviewEmpty,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12.5,
                  color: current != null ? AppColors.ink : AppColors.inkSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three ways to order the readers' reviews list. Sorting/pagination for
/// display happen client-side over the already-fetched list (bounded by the
/// API's own limit ceiling) — small enough a dataset that a second round
/// trip per sort change would be waste, not correctness.
enum _ReviewSort { newest, ratingDesc, ratingAsc }

List<Map<String, dynamic>> _sortReviews(List<Map<String, dynamic>> reviews, _ReviewSort sort) {
  if (sort == _ReviewSort.newest) return reviews;
  // Index-based tie-break instead of relying on List.sort's stability (not
  // guaranteed in Dart) — ties keep the server's newest-first relative order.
  final indexed = reviews.asMap().entries.toList();
  indexed.sort((a, b) {
    final ra = a.value['rating'] as int?;
    final rb = b.value['rating'] as int?;
    int cmp;
    if (ra == null && rb == null) {
      cmp = 0;
    } else if (ra == null) {
      cmp = 1;
    } else if (rb == null) {
      cmp = -1;
    } else {
      cmp = sort == _ReviewSort.ratingDesc ? rb.compareTo(ra) : ra.compareTo(rb);
    }
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}

/// Every other reader's public review of this book, with sorting, a rating
/// distribution, and a client-side "show more" reveal — a reviewer's profile
/// may be private, in which case the server already anonymized their name to
/// a stable "User_XXXXXX" placeholder and dropped their avatar (never trust
/// the client to hide it). Only a public reviewer's row is tappable, opening
/// their profile where a connection request can be sent.
class _ReviewsSection extends ConsumerStatefulWidget {
  const _ReviewsSection({required this.workId});

  final String workId;

  @override
  ConsumerState<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends ConsumerState<_ReviewsSection> {
  var _sort = _ReviewSort.newest;
  var _visibleCount = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(publicReviewsProvider(widget.workId));

    return data.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      ),
      error: (_, _) =>
          ErrorRetry(onRetry: () => ref.invalidate(publicReviewsProvider(widget.workId))),
      data: (page) {
        final reviews = (page['reviews'] as List).cast<Map<String, dynamic>>();
        final ratingCount = page['rating_count'] as int? ?? 0;
        final ratingAverage = (page['rating_average'] as num?)?.toDouble();
        final distributionRaw = (page['rating_distribution'] as Map?) ?? const {};
        final distribution = {
          for (final e in distributionRaw.entries) int.parse(e.key.toString()): e.value as int,
        };
        final sorted = _sortReviews(reviews, _sort);
        final visible = sorted.take(_visibleCount).toList();
        final remaining = sorted.length - visible.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    l10n.bookReviewsCount(reviews.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (reviews.length > 1)
                  _SortChip(sort: _sort, onChanged: (s) => setState(() => _sort = s)),
              ],
            ),
            if (ratingCount > 0) ...[
              SizedBox(height: 12),
              _RatingDistribution(
                average: ratingAverage!,
                count: ratingCount,
                distribution: distribution,
              ),
            ],
            SizedBox(height: 10),
            if (reviews.isEmpty)
              _Card(
                child: Text(
                  l10n.bookReadersReviewsEmpty,
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
                ),
              )
            else ...[
              for (final r in visible) ...[
                _PublicReviewRow(review: r),
                SizedBox(height: 8),
              ],
              if (remaining > 0)
                Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _visibleCount += 10),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.oxblood,
                      side: BorderSide(color: AppColors.line),
                    ),
                    child: Text(l10n.bookShowMoreReviews(remaining)),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// The "Newest / Highest rated / Lowest rated" chip + menu.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.sort, required this.onChanged});

  final _ReviewSort sort;
  final ValueChanged<_ReviewSort> onChanged;

  String _label(AppLocalizations l10n, _ReviewSort s) => switch (s) {
        _ReviewSort.newest => l10n.bookSortNewest,
        _ReviewSort.ratingDesc => l10n.bookSortRatingHigh,
        _ReviewSort.ratingAsc => l10n.bookSortRatingLow,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<_ReviewSort>(
      initialValue: sort,
      onSelected: onChanged,
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        for (final s in _ReviewSort.values)
          PopupMenuItem(
            value: s,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_label(l10n, s)),
                if (s == sort) ...[SizedBox(width: 12), Icon(Icons.check, size: 16, color: AppColors.oxblood)],
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label(l10n, sort),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            SizedBox(width: 3),
            Icon(Icons.expand_more, size: 15, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// The numeric average + stars beside a 5→1 star distribution — free from
/// data the reviews endpoint already returns, no extra request.
class _RatingDistribution extends StatelessWidget {
  const _RatingDistribution({required this.average, required this.count, required this.distribution});

  final double average;
  final int count;
  final Map<int, int> distribution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxCount = distribution.values.isEmpty
        ? 1
        : distribution.values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          // 5 stars at 14px each is 70px wide (mainAxisSize.min doesn't
          // shrink an Icon below its `size`) — this must stay >= that or the
          // star row overflows the column.
          width: 78,
          child: Column(
            children: [
              Text(
                average.toStringAsFixed(1),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24),
              ),
              SizedBox(height: 2),
              _Stars(value: average),
              SizedBox(height: 2),
              Text(
                l10n.bookRatingsCount(count),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8.5, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            children: [
              for (var v = 5; v >= 1; v--)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 8,
                        child: Text(
                          '$v',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (distribution[v] ?? 0) / maxCount,
                            minHeight: 4,
                            backgroundColor: AppColors.paperDeep,
                            valueColor: AlwaysStoppedAnimation(AppColors.gold),
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${distribution[v] ?? 0}',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicReviewRow extends StatelessWidget {
  const _PublicReviewRow({required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reviewer = review['reviewer'] as Map<String, dynamic>;
    final isPublic = reviewer['is_public'] == true;
    final avatar = reviewer['avatar_url'] as String?;
    final name = reviewer['display_name'] as String;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final rating = review['rating'] as int?;

    return _Card(
      child: GestureDetector(
        onTap: isPublic
            ? () => context.push(
                  Routes.publicProfilePath(reviewer['id'] as String),
                  extra: name,
                )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: avatar != null ? netImageProvider(avatar) : null,
              child: Text(
                initial,
                style: TextStyle(
                  color: Color(0xFF8F681E),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: isPublic ? AppColors.oxblood : AppColors.ink,
                          ),
                        ),
                      ),
                      if (rating != null)
                        Row(
                          children: [
                            for (var i = 1; i <= 5; i++)
                              Icon(
                                i <= rating ? Icons.star : Icons.star_border,
                                size: 12,
                                color: AppColors.gold,
                              ),
                          ],
                        )
                      else
                        Text(
                          l10n.bookNoRatingLabel,
                          style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    review['body'] as String,
                    style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                  ),
                ],
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
