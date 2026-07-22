import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reading_timer_notifications.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../lending/lending_format.dart';
import '../../lending/presentation/lend_sheet.dart';
import '../../lending/presentation/sheet_fields.dart';
import '../../lending/reminder.dart';
import '../../share/presentation/share_book_sheet.dart';
import '../cover_upload.dart';
import '../reading_progress.dart';
import '../reading_status.dart';
import '../stop_session_flow.dart';
import 'note_page.dart';
import '../providers/library_providers.dart';
import '../providers/reading_timer_providers.dart';
import 'notes_journal_screen.dart';
import 'cover_viewer.dart';
import 'shelf_sheets.dart';
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
    final translators =
        (work['translators'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
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
                          if (authors.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 3),
                              // Every author, not just the first — a co-author
                              // (including the reader who tagged themself) must
                              // show up here. Each name is its own door to that
                              // author's page; the row wraps for long lists.
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  for (final (i, author) in authors.indexed)
                                    GestureDetector(
                                      onTap: author['id'] != null
                                          ? () => context.push(
                                              Routes.authorBrowsePath(author['id'] as String))
                                          : null,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (i == 0 && author['image_url'] != null) ...[
                                            CircleAvatar(
                                              radius: 9,
                                              backgroundColor: AppColors.goldSoft,
                                              foregroundImage: netImageProvider(
                                                  author['image_url'] as String),
                                            ),
                                            SizedBox(width: 6),
                                          ],
                                          Text(
                                            i == 0
                                                ? l10n.bookByAuthor(author['name'] as String)
                                                : ', ${author['name']}',
                                            style: TextStyle(
                                              color: AppColors.oxblood,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          // T5: the translator in the byline, where a reader
                          // looks for it — each name a door to their author
                          // page, same as the authors above.
                          if (translators.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Wrap(
                                children: [
                                  for (final (i, translator) in translators.indexed)
                                    GestureDetector(
                                      onTap: translator['id'] != null
                                          ? () => context.push(
                                              Routes.authorBrowsePath(translator['id'] as String))
                                          : null,
                                      child: Text(
                                        i == 0
                                            ? l10n.bookTranslatedBy(translator['name'] as String)
                                            : ', ${translator['name']}',
                                        style: TextStyle(
                                          color: AppColors.oxblood,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
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
      // "Link a translation" from an *original's* page records the direction
      // (the picked work was translated from this one). From a page that is
      // itself a translation, stay undirected — the picked sibling's original
      // is this work's original, not this work.
      final relation = work['original'] == null ? 'translation' : 'sibling';
      await ref.read(apiClientProvider).linkTranslation(workId, otherId, relation: relation);
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

  /// T6: open the add form pre-linked to this work as the original — the new
  /// translation joins the group on save. On return, refresh so it appears.
  Future<void> _addTranslation(BuildContext context, WidgetRef ref) async {
    final workId = work['id'] as String;
    await context.push(Routes.catalogAdd, extra: {
      'originalWork': {
        'id': workId,
        'title': work['title'],
        'language': work['language'],
        'first_publish_year': work['first_publish_year'],
        'authors': work['authors'],
        'edition':
            ((work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? const []).firstOrNull,
      },
    });
    ref.invalidate(workProvider(workId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final translations = (work['translations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final original = work['original'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: l10n.bookTranslationsSection),
        SizedBox(height: 4),
        // T5: on a translation's page, the original leads — the gold-ruled
        // "Translation of …" card, tappable like any sibling.
        if (original != null)
          _OriginalCard(
            original: original,
            onTap: () {
              final ed = original['edition'] as Map<String, dynamic>?;
              if (ed != null) {
                context.push(Routes.bookDetailPath(original['id'] as String, ed['id'] as String));
              }
            },
          ),
        for (final t in translations)
          if (t['id'] != original?['id'])
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
        // T6's two doors, deliberately distinct: create a new translation of
        // this work (pre-seeded add form), or link one already in the
        // catalogue (the picker).
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.oxblood,
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _addTranslation(context, ref),
              icon: Icon(Icons.add, size: 18),
              label: Text(l10n.bookAddTranslation),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.oxblood,
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _link(context, ref),
              icon: Icon(Icons.link, size: 18),
              label: Text(l10n.bookLinkTranslation),
            ),
          ],
        ),
      ],
    );
  }
}

/// T5 — "Translation of `<original>`", the gold-ruled provenance card leading
/// the translations section on a translation's own page.
class _OriginalCard extends StatelessWidget {
  const _OriginalCard({required this.original, required this.onTap});

  final Map<String, dynamic> original;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final edition = original['edition'] as Map<String, dynamic>?;
    final authors = (original['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final language = edition?['language'] as String?;
    final year = original['first_publish_year'];
    final subtitle = [
      ?language,
      if (year != null) '$year',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          // Left accent rule as an inner clipped bar — borderRadius plus a
          // non-uniform Border throws at paint time.
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.only(right: 9),
            child: Row(
              children: [
                Container(width: 3, height: 53, color: AppColors.gold),
                SizedBox(width: 9),
                Icon(Icons.swap_horiz, size: 16, color: AppColors.oxblood),
                SizedBox(width: 8),
                TypesetCover(
                  title: original['title'] as String? ?? '',
                  author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                  coverUrl: edition?['cover_url'] as String?,
                  width: 24,
                  height: 35,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.bookTranslationOf(original['title'] as String? ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
              ],
            ),
          ),
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final title = translation['title'] as String? ?? '';
    final edition = translation['edition'] as Map<String, dynamic>?;
    final language = edition?['language'] as String?;
    final authors = (translation['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final translators =
        (translation['translators'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // "Malayalam · trans. S. Ramesan" — the two facts that tell versions apart.
    final subtitle = [
      ?language ?? (authors.isNotEmpty ? authors.first['name'] as String? : null),
      if (translators.isNotEmpty) l10n.bookTranslatedBy(translators.first['name'] as String),
    ].join(' · ');

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
                  if (subtitle.isNotEmpty)
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
    // The full sheet, so a cover already on the book can be straightened or
    // re-cropped here — not only from the add/edit form.
    final action = await showCoverActionSheet(context, hasImage: widget.coverUrl != null);
    if (action == null || !mounted) return;
    ImageSource? source;
    switch (action) {
      case CoverAction.camera:
        source = ImageSource.camera;
      case CoverAction.gallery:
        source = ImageSource.gallery;
      case CoverAction.adjust:
      case CoverAction.rotate:
      case CoverAction.remove:
        source = null;
    }
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = switch (action) {
        CoverAction.rotate || CoverAction.adjust => await rotateAndUploadCover(
            ref,
            context,
            editionId: widget.editionId,
            currentUrl: widget.coverUrl!,
            back: widget.back,
          ),
        _ => await pickAndUploadCover(
            ref,
            editionId: widget.editionId,
            source: source!,
            back: widget.back,
          ),
      };
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

  /// Taking a book off the wishlist keeps the entry — it just stops being a
  /// wish and becomes "To read" (owner decision, 22 Jul 2026: nothing personal
  /// gets removed behind a one-tap toggle). Deleting outright is still there,
  /// but only behind the trash can and its confirm dialog, where the cost is
  /// spelled out. The catalogue book is Layer 1 and is never touched either
  /// way.
  Future<void> _unwishlist(BuildContext context, WidgetRef ref, LibraryEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    Haptics.selection();
    final messenger = ScaffoldMessenger.of(context);
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateStatus(entry.id, 'pending');
    ref.invalidate(libraryEntryProvider(editionId));
    messenger.showSnackBar(SnackBar(content: Text(l10n.bookWishlistRemoved)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entry = ref.watch(libraryEntryProvider(editionId));
    final current = entry.valueOrNull;
    if (current == null) return SizedBox.shrink();

    final wishlisted = current.status == 'wishlist';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wishlist sits beside Favourite so the two are finally visible
        // together — gold star (owned, loved) vs slate bookmark (not owned
        // yet). Apart, they were confusable; side by side the colour and the
        // mark do the work (U3). A book you already own can't be wished for,
        // so on an owned entry the bookmark simply isn't there.
        if (wishlisted)
          IconButton(
            tooltip: l10n.bookWishlistRemove,
            icon: Icon(Icons.bookmark, color: AppColors.slate),
            onPressed: () => _unwishlist(context, ref, current),
          ),
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
    final l10n = AppLocalizations.of(context)!;
    final editionId = edition['id'] as String;

    // Cache before creating the entry so the grid/home cover tiles that
    // rebuild on the insert already find the catalog data (rule 2).
    Future<void> addEntry({String status = 'pending'}) async {
      await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.add(editionId: editionId, status: status);
      ref.invalidate(libraryEntryProvider(editionId));
    }

    return Row(children: [
      Expanded(
        child: ElevatedButton(
          onPressed: addEntry,
          child: Text(l10n.bookAddToLibrary),
        ),
      ),
      SizedBox(width: 8),
      // The other half of the question this page asks: owning it and wanting
      // it are different answers, and wishlisting used to be reachable only
      // through the status sheet — which U5 removed.
      Tooltip(
        message: l10n.bookWishlistAdd,
        child: OutlinedButton(
          onPressed: () async {
            Haptics.selection();
            final messenger = ScaffoldMessenger.of(context);
            await addEntry(status: 'wishlist');
            messenger.showSnackBar(SnackBar(content: Text(l10n.bookWishlistAdded)));
          },
          style: OutlinedButton.styleFrom(
            minimumSize: Size(50, 46),
            padding: EdgeInsets.zero,
            side: BorderSide(color: AppColors.slate),
            foregroundColor: AppColors.slate,
          ),
          child: Icon(Icons.bookmark_outline, size: 20),
        ),
      ),
    ]);
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
        // Wishlist → owned is the wish coming true, and it now lives inside
        // the reading card — which for a wishlisted book is nothing *but*
        // that one move, so a second button above it was saying it twice.
        _ReadingCard(
          entry: entry,
          workId: workId,
          reviewExtra: _reviewExtra,
          title: title,
          author: author,
        ),
        SizedBox(height: 8),
        _ReviewCard(workId: workId, reviewExtra: _reviewExtra),
        SizedBox(height: 8),
        _NotesCard(entry: entry),
        SizedBox(height: 8),
        // You can't lend out a book you don't own yet. Shelves stay — filing a
        // want under "Buy in Kochi" is a real thing to want to do.
        if (entry.status != 'wishlist') ...[
          _LendingCard(entry: entry, editionId: entry.editionId),
          SizedBox(height: 8),
        ],
        _ShelfSection(entry: entry),
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

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmtDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]} ${d.year}';
String _fmtDayMonth(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

/// "today" / "yesterday" / "18 Jul 2026" — the reading card's last-read line.
String _relativeDay(DateTime d, AppLocalizations l10n) {
  final today = DateTime.now();
  if (DateUtils.isSameDay(d, today)) return l10n.timerToday.toLowerCase();
  if (DateUtils.isSameDay(d, today.subtract(const Duration(days: 1)))) {
    return l10n.timerYesterday.toLowerCase();
  }
  return _fmtDate(d);
}

/// The reading card (owner pick "B", 19 Jul 2026): status, progress, and the
/// live/manual reading session merged onto one surface. A tappable status pill,
/// a real progress bar, the started date with an inline edit, and — while
/// reading — Start-a-session with a manual-log fallback. Its footer summarises
/// the sessions and opens the full [showReadingLogSheet]. Replaces the old
/// separate status/progress and reading-session cards.
class _ReadingCard extends ConsumerWidget {
  const _ReadingCard({
    required this.entry,
    required this.workId,
    required this.reviewExtra,
    this.title,
    this.author,
  });

  final LibraryEntry entry;
  final String workId;
  final Map<String, dynamic> reviewExtra;
  final String? title;
  final String? author;

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

  /// Applies a status picked straight off the tile row (U5). The start/finish
  /// stamps and the review prompt ride along with it, exactly as they did when
  /// this was reached through a sheet.
  Future<void> _setStatus(BuildContext context, WidgetRef ref, String chosen) async {
    if (chosen == entry.status || !context.mounted) return;
    Haptics.selection();

    // A running timer only makes sense while the book is Reading, so leaving
    // that status ends the sitting rather than leaving a clock running on a
    // book you just marked finished (owner report, 22 Jul 2026). Going to
    // Stopped runs the full stop flow — page and notes, both skippable —
    // because that's a reader deliberately putting the book down. Read and To
    // read stop it quietly: the page is about to be settled anyway.
    final active = ref.read(activeSessionProvider);
    String? closingNoteSessionId;
    if (active?.libraryEntryId == entry.id && chosen != 'reading') {
      if (chosen == 'stopped') {
        await quickStopSession(context, ref);
      } else {
        // stop() still logs the sitting — only the page question is skipped,
        // since Read fills the page in below and To read may clear it anyway.
        final logged = await ref.read(activeSessionProvider.notifier).stop();
        // Finishing a book on a live timer is the most note-worthy moment
        // there is, and it was passing in silence (owner report, 22 Jul 2026).
        if (chosen == 'read') closingNoteSessionId = logged?.sessionId;
      }
      if (!context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateStatus(entry.id, chosen);
    if (chosen == 'reading' && entry.startDate == null) {
      await repo.updateProgress(entry.id, startDate: DateTime.now());
    }
    if (chosen == 'read') {
      if (entry.finishDate == null) {
        await repo.updateProgress(entry.id, finishDate: DateTime.now());
      }
      // Finishing a book means you read all of it — leaving progress at p. 27
      // of 200 on a book marked Read is a contradiction the reader would have
      // to go fix by hand.
      final total = ref.read(cachedBookProvider(entry.editionId)).valueOrNull?.pageCount;
      if (total != null && total > 0 && (entry.currentPage ?? 0) < total) {
        await repo.updateProgress(entry.id, currentPage: total);
        messenger.showSnackBar(SnackBar(content: Text(l10n.statusReadAllPages(total))));
      }
    }
    ref.invalidate(libraryEntryProvider(entry.editionId));

    // Back to To read is the one transition that can mean "I'm starting this
    // over" — so it asks, rather than assuming either way. Keeping is the
    // default; clearing is never silent.
    if (chosen == 'pending' && context.mounted) {
      await _maybeClearHistory(context, ref);
    }
    // Putting a book down with no timer running still wants the page settled —
    // Cancel skips it, and the notes card below is where a parting thought
    // goes. (With a timer running the full stop flow above already asked.)
    if (chosen == 'stopped' && active?.libraryEntryId != entry.id && context.mounted) {
      await _editProgress(context, ref);
    }
    // The closing thought comes before the review prompt: it's about the
    // sitting you just ended, while the review is about the whole book. Both
    // are skippable — back out and nothing is lost.
    if (closingNoteSessionId != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => NotePage(
            libraryEntryId: entry.id,
            bookTitle: title,
            sessionId: closingNoteSessionId,
            currentPage: entry.currentPage,
          ),
        ),
      );
      if (!context.mounted) return;
    }
    if (chosen == 'read' && entry.status != 'read' && context.mounted) {
      await _maybePromptReview(context, ref);
    }
  }

  /// Offers to wipe this book's sittings and notes when it goes back to To
  /// read. Dismissing the dialog keeps everything — the destructive answer has
  /// to be chosen explicitly.
  Future<void> _maybeClearHistory(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final sessionsRepo = await ref.read(readingSessionsRepositoryProvider.future);
    final notesRepo = await ref.read(readingNotesRepositoryProvider.future);
    final sessions = await sessionsRepo.watchForEntry(entry.id).first;
    final notes = await notesRepo.watchForEntry(entry.id).first;
    if ((sessions.isEmpty && notes.isEmpty) || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final wipe = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.statusClearTitle),
        content: Text(l10n.statusClearBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.statusClearKeep)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.statusClearWipe, style: TextStyle(color: AppColors.oxbloodDeep)),
          ),
        ],
      ),
    );
    if (wipe != true) return;
    for (final s in sessions) {
      await sessionsRepo.deleteSession(s.id);
    }
    for (final n in notes) {
      await notesRepo.remove(n.id);
    }
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateProgress(entry.id, currentPage: 0);
    ref.invalidate(libraryEntryProvider(entry.editionId));
    messenger.showSnackBar(SnackBar(content: Text(l10n.statusCleared)));
  }

  Future<void> _editProgress(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    // When the catalog has no total, offer to set it here too — otherwise
    // progress can only ever be "p. 42", never a percentage.
    final knownTotal = ref.read(cachedBookProvider(entry.editionId)).valueOrNull?.pageCount;
    final controller = TextEditingController(text: entry.currentPage?.toString() ?? '');
    // Pre-selected, so the autofocused field is overwritten by the first digit.
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final totalController = TextEditingController();
    // The start date is stamped automatically the first time a book goes to
    // Reading — which is right, until it isn't: a book you began last month
    // but added today is dated today, forever, with nowhere to correct it
    // (owner question, 21 Jul 2026). It's editable here now.
    var started = entry.startDate;
    final result = await showDialog<(int?, int?, DateTime?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.bookEditProgress),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.bookCurrentPage),
                autofocus: true,
                // Typing a new page should replace the old one, not append to
                // it — nobody wants to backspace "127" to write "9" (owner
                // report, 22 Jul 2026). Same replace-on-tap the stop sheet's
                // page entry already uses.
                onTap: () => controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                ),
              ),
              if (knownTotal == null)
                TextField(
                  controller: totalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.timerTotalFieldLabel),
                ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: started ?? now,
                    firstDate: DateTime(now.year - 20),
                    // You can't have started a book after today.
                    lastDate: now,
                  );
                  if (picked != null) setDialogState(() => started = picked);
                },
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 16, color: AppColors.inkSoft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        started == null
                            ? l10n.bookStartDateUnset
                            : l10n.bookStartedOn(_fmtDate(started!)),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      l10n.bookChangeDate,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.oxblood,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                (
                  int.tryParse(controller.text.trim()),
                  int.tryParse(totalController.text.trim()),
                  started,
                ),
              ),
              child: Text(l10n.bookSave),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final (page, total, startDate) = result;
    // The total belongs to the shared Edition — mirror it locally + sync it.
    if (knownTotal == null && total != null) {
      await saveBookTotalPages(
        ref.read(appDatabaseProvider),
        ref.read(apiClientProvider),
        entry.editionId,
        total,
      );
    }
    if (page == null) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    // Whatever the reader chose wins; falling back to now only when there was
    // no date and they didn't set one.
    final resolvedStart = startDate ?? (entry.startDate == null ? DateTime.now() : null);
    await repo.updateProgress(
      entry.id,
      currentPage: page,
      startDate: resolvedStart,
    );
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  Future<void> _logManually(BuildContext context, WidgetRef ref, {required int? pageCount}) async {
    final result = await showModalBottomSheet<(int, int?, int?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ManualLogSheet(currentPage: entry.currentPage, pageCount: pageCount),
    );
    if (result == null || !context.mounted) return;
    final (minutes, pageEnd, total) = result;
    Haptics.success();

    // A total typed here (book had none) belongs to the Edition — save + sync.
    if (pageCount == null && total != null) {
      await saveBookTotalPages(
        ref.read(appDatabaseProvider),
        ref.read(apiClientProvider),
        entry.editionId,
        total,
      );
    }

    final endedAt = DateTime.now();
    final startedAt = endedAt.subtract(Duration(minutes: minutes));
    final repo = await ref.read(readingSessionsRepositoryProvider.future);
    await repo.logSession(
      libraryEntryId: entry.id,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: minutes * 60,
      pageStart: entry.currentPage,
      pageEnd: pageEnd,
    );
    if (pageEnd != null) {
      final libraryRepo = await ref.read(libraryRepositoryProvider.future);
      await libraryRepo.updateProgress(entry.id, currentPage: pageEnd);
      ref.invalidate(libraryEntryProvider(entry.editionId));
    }
    ref.invalidate(weeklyReadingSecondsProvider);
  }

  /// The primary button's idle half: a book you haven't started is the one you
  /// most want to start, so this moves it to Reading (stamping the start date)
  /// before opening the timer — one tap where there used to be three.
  Future<void> _startReading(
    BuildContext context,
    WidgetRef ref, {
    required int? pageCount,
    String? coverUrl,
  }) async {
    if (entry.status != 'reading') {
      await _setStatus(context, ref, 'reading');
      if (!context.mounted) return;
    }
    _open(context, ref, pageCount: pageCount, coverUrl: coverUrl);
  }

  void _open(BuildContext context, WidgetRef ref, {required int? pageCount, String? coverUrl}) {
    Haptics.selection();
    final freshStart = ref.read(activeSessionProvider)?.libraryEntryId != entry.id;
    final startedAt = DateTime.now();
    ref.read(activeSessionProvider.notifier).start(entry.id, pageStart: entry.currentPage);
    if (freshStart) {
      final l10n = AppLocalizations.of(context)!;
      armReadingTimerSafetyNet(
        libraryEntryId: entry.id,
        from: startedAt,
        title: l10n.timerCheckInTitle,
        body: l10n.timerCheckInBody,
        yesLabel: l10n.timerCheckInYes,
        noLabel: l10n.timerCheckInNo,
      );
    }
    context.push(
      Routes.readingTimerPath(entry.id),
      extra: {
        'title': title,
        'author': author,
        'currentPage': entry.currentPage,
        'pageCount': pageCount,
        'coverUrl': coverUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final book = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull;
    final total = book?.pageCount;
    final page = entry.currentPage;
    final active = ref.watch(activeSessionProvider);
    final running = active?.libraryEntryId == entry.id;
    final sessions = ref.watch(_recentSessionsProvider(entry.id)).valueOrNull ?? const <ReadingSession>[];
    final isReading = entry.status == 'reading';
    final pct = (page != null && total != null && total > 0)
        ? ((page / total) * 100).round().clamp(0, 100)
        : null;

    // A book you don't own has no reading stage, no progress and no session to
    // start — the whole card would be four dead controls. It says what it is
    // and offers the one move that matters: getting hold of it.
    if (entry.status == 'wishlist') {
      return _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bookmark, size: 16, color: AppColors.slate),
              SizedBox(width: 6),
              Expanded(
                child: Text(l10n.bookWishlistNotOwned,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              ),
            ]),
            SizedBox(height: 11),
            _GotItButton(entry: entry),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status — four tiles, one tap each. The old pill + "Change ›" hid
          // the options behind a sheet, so nobody found Stopped and starting
          // to read took two taps and a guess (owner report, 21 Jul 2026; U5).
          // Wishlist is deliberately absent: it isn't a stage of reading a
          // book you own, it lives in the title bar (U3).
          Text(l10n.bookWhereItStands,
              style: TextStyle(
                  fontSize: 9, letterSpacing: 1.2, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Row(
            children: [
              for (final status in _ownedStatuses) ...[
                if (status != _ownedStatuses.first) SizedBox(width: 5),
                Expanded(
                  child: _StatusTile(
                    status: status,
                    selected: entry.status == status,
                    onTap: () => _setStatus(context, ref, status),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 6),
          Center(
            child: Text(l10n.bookStatusHint,
                style: TextStyle(fontSize: 9.5, color: AppColors.inkSoft)),
          ),
          SizedBox(height: 13),
          Container(height: 1, color: AppColors.line),
          SizedBox(height: 13),
          // Progress — a real bar when the total is known, page text either way.
          if (pct != null) ...[
            _ProgressBar(value: page! / total!),
            SizedBox(height: 8),
            Text(l10n.bookProgressValue(page, total, pct),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ] else
            Text(page == null ? l10n.bookNotStarted : l10n.bookProgressPage(page),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
          SizedBox(height: 9),
          // Started + inline edit.
          Row(children: [
            // Only the real start date earns a line. It used to fall back to
            // "Not started", which now sits directly under "p. 27 of 200" and
            // reads as a contradiction — it only ever meant "no start date on
            // file", and Edit is right there to put one on.
            Expanded(
              child: entry.startDate != null
                  ? Text(l10n.bookStartedOn(_fmtDate(entry.startDate!)),
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft))
                  : const SizedBox.shrink(),
            ),
            GestureDetector(
              onTap: () => _editProgress(context, ref),
              behavior: HitTestBehavior.opaque,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit, size: 13, color: AppColors.oxblood),
                SizedBox(width: 3),
                Text(l10n.bookProgressEdit,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.oxblood)),
              ]),
            ),
          ]),
          // One control that changes state in place: Start reading becomes
          // Stop & log with the running clock on it, so starting and stopping
          // are never two buttons in two places (U5). It shows whatever the
          // status is — a book you haven't started is exactly the book you
          // most want to start.
          SizedBox(height: 13),
          Row(children: [
            Expanded(
              flex: 22,
              child: running
                  ? ElevatedButton.icon(
                      onPressed: () => quickStopSession(context, ref),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 11),
                        backgroundColor: AppColors.ink,
                      ),
                      icon: Icon(Icons.stop_rounded, size: 16),
                      label: _StopLabel(startedAt: active!.startedAt, label: l10n.timerStopAndLog),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _startReading(context, ref, pageCount: total, coverUrl: book?.coverUrl),
                      style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 11)),
                      icon: Icon(Icons.play_arrow, size: 16),
                      label: Text(isReading ? l10n.bookStartSession : l10n.bookStartReading),
                    ),
            ),
            SizedBox(width: 7),
            Expanded(
              flex: 10,
              child: OutlinedButton.icon(
                onPressed: running
                    ? () => _open(context, ref, pageCount: total, coverUrl: book?.coverUrl)
                    : () => _editProgress(context, ref),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, 44),
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: AppColors.line),
                  foregroundColor: AppColors.oxblood,
                ),
                icon: Icon(running ? Icons.edit_note : Icons.edit, size: 15),
                label: Text(running ? l10n.bookSecondaryNote : l10n.bookSecondaryPage,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
          // Logging a sitting you never timed used to be the icon beside
          // "Start a session"; U5 spends that slot on Page/Note, so it keeps
          // its own line rather than vanishing with the button it rode on.
          if (!running) ...[
            SizedBox(height: 7),
            Center(
              child: TextButton(
                onPressed: () => _logManually(context, ref, pageCount: total),
                style: TextButton.styleFrom(
                  minimumSize: Size(0, 30),
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: AppColors.inkSoft,
                ),
                child: Text(l10n.timerLogManually, style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
          // Footer: a summary that opens the full reading log.
          if (sessions.isNotEmpty) ...[
            SizedBox(height: 12),
            GestureDetector(
              onTap: () => showReadingLogSheet(context, entry.id),
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                Text(l10n.bookLogLastRead(_relativeDay(sessions.first.startedAt, l10n)),
                    style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                Spacer(),
                Text(
                  '${l10n.bookLogSessions(sessions.length)} · '
                  '${formatDuration(Duration(seconds: sessions.fold<int>(0, (a, s) => a + s.durationSeconds)))}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.oxblood),
                ),
                Icon(Icons.chevron_right, size: 15, color: AppColors.oxblood),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The gold→oxblood progress fill on a paper track — the reading card's bar.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 7,
        child: ColoredBox(
          color: AppColors.paperDeep,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.gold, AppColors.oxblood]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reading log — every sitting on this book, grouped by day, with a week
/// sparkline and swipe-free delete (owner request, 19 Jul 2026). Opened from
/// the reading card's footer.
Future<void> showReadingLogSheet(BuildContext context, String entryId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReadingLogSheet(entryId: entryId),
  );
}

class _ReadingLogSheet extends ConsumerWidget {
  const _ReadingLogSheet({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(_recentSessionsProvider(entryId)).valueOrNull ?? const <ReadingSession>[];
    final totalSecs = sessions.fold<int>(0, (a, s) => a + s.durationSeconds);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bookReadingLogTitle, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.bookLogSessions(sessions.length)} · ${formatDuration(Duration(seconds: totalSecs))}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                  if (sessions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _WeekSparkline(sessions: sessions),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Text(l10n.bookLogEmpty,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
              )
            else
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 14),
                  children: _rows(context, ref, sessions, l10n),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(
    BuildContext context,
    WidgetRef ref,
    List<ReadingSession> sessions,
    AppLocalizations l10n,
  ) {
    final out = <Widget>[];
    DateTime? lastDay;
    for (final s in sessions) {
      if (lastDay == null || !DateUtils.isSameDay(s.startedAt, lastDay)) {
        lastDay = s.startedAt;
        final header = DateUtils.isSameDay(s.startedAt, DateTime.now())
            ? l10n.timerToday
            : DateUtils.isSameDay(s.startedAt, DateTime.now().subtract(const Duration(days: 1)))
                ? l10n.timerYesterday
                : _fmtDayMonth(s.startedAt);
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 14, bottom: 3),
          child: Text(header.toUpperCase(),
              style: TextStyle(
                  fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppColors.inkSoft)),
        ));
      }
      out.add(_LogRow(
        session: s,
        onDelete: () async {
          Haptics.selection();
          final messenger = ScaffoldMessenger.of(context);
          final repo = await ref.read(readingSessionsRepositoryProvider.future);
          await repo.deleteSession(s.id);
          messenger.showSnackBar(SnackBar(content: Text(l10n.bookLogDeleted)));
        },
      ));
    }
    return out;
  }
}

/// One sitting in the log: time of day, the pages it moved through, its length,
/// and a delete for the stray micro-sessions.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.session, required this.onDelete});

  final ReadingSession session;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(session.startedAt));
    final ps = session.pageStart;
    final pe = session.pageEnd;
    final pages = (ps != null && pe != null && pe > ps) ? l10n.bookLogPages(ps, pe) : l10n.bookLogNoPages;

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.goldSoft, shape: BoxShape.circle),
            child: Icon(Icons.timelapse, size: 15, color: AppColors.gold),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                Text(pages, style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          Text(
            formatDuration(Duration(seconds: session.durationSeconds)),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.oxblood,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 18, color: AppColors.inkSoft),
            tooltip: l10n.bookLogDelete,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Minutes read per day across the last week — today in oxblood, the rest gold.
class _WeekSparkline extends StatelessWidget {
  const _WeekSparkline({required this.sessions});

  final List<ReadingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final secs = [
      for (final d in days)
        sessions
            .where((s) => DateUtils.isSameDay(s.startedAt, d))
            .fold<int>(0, (a, s) => a + s.durationSeconds)
    ];
    final maxSec = secs.fold<int>(1, (a, b) => b > a ? b : a);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, s) in secs.indexed)
                Expanded(
                  child: Container(
                    height: (s / maxSec * 32).clamp(3.0, 32.0),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: i == 6 ? AppColors.oxblood : AppColors.goldSoft,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text(_fmtDayMonth(days.first),
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: AppColors.inkSoft)),
            Spacer(),
            Text(l10n.timerToday.toUpperCase(),
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: AppColors.inkSoft)),
          ],
        ),
      ],
    );
  }
}

/// Duration-only fallback for a session the reader forgot to time live —
/// synthesizes `startedAt`/`endedAt` as `(now - duration)..now` and reuses
/// the same optional end-page field as the wax-seal stop screen. Returns
/// `(minutes, pageEnd)` for the caller to log; pure UI, no repository calls
/// here, same split as `_StatusSheet`/`_changeStatus`.
class _ManualLogSheet extends StatefulWidget {
  const _ManualLogSheet({required this.currentPage, required this.pageCount});

  final int? currentPage;
  final int? pageCount;

  @override
  State<_ManualLogSheet> createState() => _ManualLogSheetState();
}

class _ManualLogSheetState extends State<_ManualLogSheet> {
  late final _minutesController = TextEditingController();
  late final _pageController = TextEditingController(
    text: widget.currentPage?.toString() ?? '',
  );
  final _totalController = TextEditingController();

  @override
  void dispose() {
    _minutesController.dispose();
    _pageController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_minutesController.text.trim());
    if (minutes == null || minutes <= 0) return;
    final page = int.tryParse(_pageController.text.trim());
    final total = int.tryParse(_totalController.text.trim());
    Navigator.pop(context, (minutes, page, total));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.timerManualSheetTitle, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 18),
          Text(
            l10n.timerManualDurationLabel,
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          TextField(
            controller: _minutesController,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              suffixText: l10n.timerManualDurationUnit,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          SizedBox(height: 16),
          Text(
            l10n.timerPageFieldLabel,
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (widget.pageCount != null) ...[
                SizedBox(width: 8),
                Text(
                  l10n.timerPageFieldOf(widget.pageCount!),
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ] else ...[
                // No total in the catalog — capture it here so progress can be
                // a percentage (and the number reaches the book + the cloud).
                SizedBox(width: 8),
                Text(l10n.timerTotalFieldLabel,
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: _totalController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.timerTotalFieldHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _save, child: Text(l10n.timerManualSave)),
          ),
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

class _LiveClock extends ConsumerStatefulWidget {
  const _LiveClock({required this.startedAt});

  final DateTime startedAt;

  @override
  ConsumerState<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends ConsumerState<_LiveClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // The book page hides the mini-bar (it's a top-level route, covers the
  // shell), so someone parked here — not on the watch face or a shell tab —
  // still needs the same deterministic forgot-to-stop safety net.
  Future<void> _tick() async {
    if (!mounted) return;
    final logged = await checkReadingTimerSafetyNet(ref);
    if (!mounted) return;
    if (logged == null) {
      setState(() {});
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    ref.invalidate(weeklyReadingSecondsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.timerResumeSafetyNetMessage(formatDuration(Duration(seconds: logged.durationSeconds))),
        ),
      ),
    );
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

/// The statuses a book you *own* can be in, in the order a book travels
/// through them. Wishlist is not among them — it says you don't own the book
/// yet, which is a different claim entirely, so it lives in the title bar (U3).
const _ownedStatuses = ['pending', 'reading', 'read', 'stopped'];

/// One status, as a labelled tile: mark on top, word under it, filled in its
/// own ink when it's the current one. Four of these replace the sheet that
/// used to hide the choice behind "Change ›" (U5).
class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.selected, required this.onTap});

  final String status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = readingStatusInk(status);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? ink : AppColors.card,
          border: Border.all(color: selected ? ink : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(readingStatusIcon(status),
                size: 17, color: selected ? AppColors.paper : ink),
            const SizedBox(height: 3),
            Text(
              readingStatusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.paper : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Stop & log · 12:04" — the label half of the primary button while a session
/// runs, so the clock is on the control you press rather than beside it.
class _StopLabel extends StatelessWidget {
  const _StopLabel({required this.startedAt, required this.label});

  final DateTime startedAt;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      const Text(' · '),
      _LiveClock(startedAt: startedAt),
    ]);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final notes = ref.watch(bookNotesProvider(entry.id)).valueOrNull ?? const <ReadingNote>[];
    // The pre-journal blob still exists on the entry and still belongs to the
    // reader — show it as one undated note rather than silently retiring it.
    final legacy = entry.notes;
    final hasLegacy = legacy != null && legacy.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotesJournalScreen(entry: entry),
        ),
      ),
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
                Spacer(),
                if (notes.isNotEmpty)
                  Text(
                    '${notes.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                Icon(Icons.chevron_right, size: 14, color: AppColors.inkSoft),
              ],
            ),
            SizedBox(height: 4),
            Text(
              notes.isNotEmpty
                  ? notes.first.body
                  : (hasLegacy ? legacy : l10n.bookNotesEmpty),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: (notes.isNotEmpty || hasLegacy) ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where this copy lives — one shelf (owner rule: one book, one shelf), shown
/// as a little bookcase (owner pick, 19 Jul 2026, mockup "B"): a gold bookmark
/// ribbon down the edge, the shelf name, and a fan of the shelf's other books
/// on a ledge — the same miniature bookcase the Shelves view uses, so the book
/// page and that wall read as one world. Tapping opens the single-select
/// picker (move); Remove takes it off.
class _ShelfSection extends ConsumerWidget {
  const _ShelfSection({required this.entry});

  final LibraryEntry entry;

  static const _angles = [-0.14, -0.02, 0.11];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final assignments = ref.watch(libraryTagsProvider(entry.id)).valueOrNull ?? const <LibraryEntryTag>[];
    final tagNames = {
      for (final t in ref.watch(allTagsProvider).valueOrNull ?? const <PersonalTag>[]) t.id: t.name,
    };
    // At most one shelf now; take the first assignment whose tag still exists.
    LibraryEntryTag? current;
    for (final a in assignments) {
      if (tagNames.containsKey(a.tagId)) {
        current = a;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          current != null ? l10n.bookShelfLabel : l10n.bookShelfLabelEmpty,
          style: TextStyle(fontSize: 9, color: AppColors.inkSoft, letterSpacing: 1),
        ),
        const SizedBox(height: 7),
        if (current == null)
          _EmptyShelfCard(onTap: () => showShelfPickerSheet(context, entryId: entry.id))
        else
          _ShelfCard(entry: entry, assignment: current, name: tagNames[current.tagId]!),
      ],
    );
  }
}

class _ShelfCard extends ConsumerWidget {
  const _ShelfCard({required this.entry, required this.assignment, required this.name});

  final LibraryEntry entry;
  final LibraryEntryTag assignment;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hits = ref.watch(libraryHitsProvider).valueOrNull ?? const <LibraryHit>[];
    final shelvesOf =
        ref.watch(entryShelvesProvider).valueOrNull ?? const <String, Set<String>>{};
    final onShelf =
        hits.where((h) => shelvesOf[h.entry.id]?.contains(assignment.tagId) ?? false).toList();
    final others = onShelf.where((h) => h.entry.id != entry.id).toList();
    // Fan the shelf's *other* books; if this is the only one on it so far, fan
    // its own cover so the little bookcase is never empty.
    final previews = (others.isNotEmpty ? others : onShelf).take(3).toList();

    void move() => showShelfPickerSheet(context, entryId: entry.id);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The bookmark ribbon.
            Container(
              width: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.gold, Color(0xFF9C6F1E)],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: move,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _fan(previews),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.fraunces(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.bookShelfOthers(others.length),
                                  style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.line)),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: move,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz, size: 15, color: AppColors.oxblood),
                                const SizedBox(width: 5),
                                Text(
                                  l10n.bookShelfMove,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.oxblood,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () async {
                              final repo = await ref.read(tagsRepositoryProvider.future);
                              await repo.unassign(assignment.id);
                            },
                            child: Text(
                              l10n.bookShelfRemove,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A miniature bookcase: up to three covers fanned on a gold ledge.
  Widget _fan(List<LibraryHit> previews) {
    return SizedBox(
      width: 64,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -2,
            right: -4,
            bottom: 3,
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.gold.withValues(alpha: 0),
                  AppColors.gold.withValues(alpha: 0.6),
                  AppColors.gold.withValues(alpha: 0),
                ]),
              ),
            ),
          ),
          for (final (i, hit) in previews.indexed)
            Positioned(
              left: 2.0 + i * 16,
              bottom: 5,
              child: Transform.rotate(
                angle: _ShelfSection._angles[i],
                alignment: Alignment.bottomCenter,
                child: TypesetCover(
                  title: hit.book.title,
                  author: hit.book.authorNames,
                  coverUrl: hit.book.coverUrl,
                  width: 28,
                  height: 42,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The book is on no shelf — the same ribboned card, quieted, inviting a pick.
class _EmptyShelfCard extends StatelessWidget {
  const _EmptyShelfCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: AppColors.gold.withValues(alpha: 0.4)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.paperDeep,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.bookmark_add_outlined, size: 18, color: AppColors.inkSoft),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.bookShelfEmptyTitle,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              l10n.bookShelfEmptyBody,
                              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.bookShelfChoose,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.oxblood,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 16, color: AppColors.oxblood),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

  /// The "I bought this" transition (owner request, 15 Jul 2026): confirms,
  /// then flips this entry from borrowed to owned in place — same id, so
  /// reading status/progress/notes carry over untouched. The lending history
  /// below is never touched by this; it stays as the permanent loan log.
  Future<void> _makeMine(BuildContext context, WidgetRef ref, LibraryEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookMakeMineConfirmTitle),
        content: Text(l10n.bookMakeMineConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.bookMakeMineAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    Haptics.success();
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.markAsOwned(entry.id);
    ref.invalidate(libraryEntryProvider(entry.editionId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final history = ref
        .watch(bookLendingHistoryProvider((entryId: entry?.id, editionId: editionId)))
        .valueOrNull ??
        const <LendingRecord>[];
    // The active loan of the copy I own — drives the header + primary action
    // for an owned entry.
    final current = history
        .where((r) => r.direction != 'borrowed' && r.returnedDate == null)
        .firstOrNull;
    // A borrowed entry (ownership: 'borrowed', added 15 Jul 2026) drives an
    // entirely different header: who it's from while active, "Make this
    // mine" once returned — never the lend/owned-copy actions above, which
    // don't make sense for a book that isn't mine yet.
    final isBorrowedEntry = entry != null && entry!.ownership == 'borrowed';
    // This entry's own borrows — there can be more than one if the reader
    // borrowed the same book twice (logBorrowed reuses the entry rather
    // than forking a new row for a re-borrow) — newest first.
    final myBorrows = isBorrowedEntry
        ? (history
                .where((r) => r.direction == 'borrowed' && r.libraryEntryId == entry!.id)
                .toList()
              ..sort((a, b) => b.lentDate.compareTo(a.lentDate)))
        : const <LendingRecord>[];
    final activeBorrow = myBorrows.where((r) => r.returnedDate == null).firstOrNull;

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
              Icon(
                isBorrowedEntry ? Icons.south_west : Icons.swap_horiz,
                size: 16,
                color: isBorrowedEntry ? AppColors.slate : AppColors.gold,
              ),
              SizedBox(width: 8),
              Expanded(
                child: isBorrowedEntry
                    ? (activeBorrow != null
                        ? Row(
                            children: [
                              Text(
                                '${l10n.bookBorrowedFromFragment} ',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                              Flexible(
                                child: PersonLink(
                                  activeBorrow.borrowerName,
                                  userId: activeBorrow.borrowerUserId,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            l10n.bookBorrowedReturnedFragment,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ))
                    : (current != null
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
                          )),
              ),
              TextButton(
                onPressed: isBorrowedEntry
                    ? (activeBorrow != null
                        ? () => _markReturned(ref, activeBorrow.id)
                        : () => _makeMine(context, ref, entry!))
                    : (current != null
                        ? () => _markReturned(ref, current.id)
                        : () => _lend(context, ref, entry!)),
                child: Text(
                  isBorrowedEntry
                      ? (activeBorrow != null
                          ? l10n.bookMarkReturnedAction
                          : l10n.bookMakeMineAction)
                      : (current != null ? l10n.bookMarkReturnedAction : l10n.bookLendAction),
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
