import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/quiet_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../circle/circle_models.dart';
import '../../circle/widgets/circle_widgets.dart';
import '../../library/providers/library_providers.dart';

/// One row for a catalog work — shared by search results and author/publisher
/// browse lists. Author and publisher names are tappable (oxblood tint)
/// everywhere they appear, per feature-map.md. A quick "＋" adds it straight to
/// the library (or shows a check once owned).
class CatalogResultTile extends ConsumerWidget {
  const CatalogResultTile({super.key, required this.work, this.circleSignal});

  final Map<String, dynamic> work;

  /// "Anu & 2 more read this" — what the reader's circle did with this book,
  /// when the list it sits in has asked (search does; browse lists don't).
  final CircleSignal? circleSignal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final edition = work['edition'] as Map<String, dynamic>?;
    final publisher = edition?['publisher'] as Map<String, dynamic>?;
    final year = work['first_publish_year'] as int?;
    // On the cover would match the shelf/browse grids, but this row's cover
    // is 30×44 — smaller than the chip itself — so the rating leads the meta
    // line instead.
    final rating = (work['aggregate_rating'] as num?)?.toDouble();

    final workId = work['id'] as String?;
    final editionId = edition?['id'] as String?;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Outside the row's tap target, so wishlisting never opens the book.
          if (editionId != null)
            _QuickWishlist(work: work, editionId: editionId)
          else
            SizedBox(width: _QuickWishlist.width),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: workId != null && editionId != null
                  ? () => context.push(Routes.bookDetailPath(workId, editionId))
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TypesetCover(
                    title: title,
                    author: authors.isNotEmpty ? authors.first['name'] as String? : null,
                    coverUrl: edition?['cover_url'] as String?,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        if (authors.isNotEmpty)
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final (i, author) in authors.indexed) ...[
                                if (i > 0)
                                  Text(', ', style: TextStyle(color: AppColors.inkSoft)),
                                // Padded so the oxblood name-link is a real
                                // target, not an 12px-tall strip.
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => context
                                      .push(Routes.authorBrowsePath(author['id'] as String)),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                      author['name'] as String,
                                      style: TextStyle(
                                        color: AppColors.oxblood,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        if (publisher != null || year != null || rating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (rating != null)
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    '★ ${rating.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      color: AppColors.goldInk,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (rating != null && (publisher != null || year != null))
                                Text(
                                  ' · ',
                                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                                ),
                              // Flexible + ellipsis: a long imprint name must
                              // truncate, not RenderFlex-overflow the row.
                              if (publisher != null)
                                Flexible(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => context.push(
                                      Routes.publisherBrowsePath(publisher['id'] as String),
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 6),
                                      child: Text(
                                        publisher['name'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            TextStyle(color: AppColors.oxblood, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ),
                              if (publisher != null && year != null)
                                Text(
                                  ' · ',
                                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                                ),
                              if (year != null)
                                Text(
                                  '$year',
                                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                                ),
                            ],
                          ),
                        if (circleSignal != null && !circleSignal!.isEmpty)
                          CircleSearchLine(signal: circleSignal!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (editionId != null) _QuickAdd(work: work, editionId: editionId),
        ],
      ),
    );
  }
}

/// Trailing quick-add on a catalog result — "＋" to add to the library, a moss
/// check once owned (offline-first: writes to Drift + the sync queue).
class _QuickAdd extends ConsumerWidget {
  const _QuickAdd({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(libraryEntryProvider(editionId)).valueOrNull != null;
    if (owned) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.check_circle, color: AppColors.moss, size: 22),
      );
    }
    return IconButton(
      icon: Icon(Icons.add_circle_outline, color: AppColors.oxblood),
      tooltip: AppLocalizations.of(context)!.bookAddToLibrary,
      onPressed: () async {
        final l10n = AppLocalizations.of(context)!;
        try {
          final edition = work['edition'] as Map<String, dynamic>;
          await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
          final repo = await ref.read(libraryRepositoryProvider.future);
          await repo.add(editionId: editionId);
          // Success feedback only after the write actually landed.
          Haptics.success();
          ref.invalidate(libraryEntryProvider(editionId));
        } catch (err) {
          if (context.mounted) showQuietError(context, l10n.quickAddFailed, err);
        }
      },
    );
  }
}

/// Leading "save for later" on a catalog result (owner request, 14 Oct 2026):
/// a bookmark left of the cover for a book that isn't anywhere on the reader's
/// shelves yet, the mirror of the trailing "＋". Slate, the Wishlist status
/// colour. Once wishlisted it stays as a filled bookmark so the row says so; a
/// book the reader already has in any other state gets the empty slot, which
/// keeps every cover in the list on the same line.
class _QuickWishlist extends ConsumerWidget {
  const _QuickWishlist({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  static const double width = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entry = ref.watch(libraryEntryProvider(editionId)).valueOrNull;
    final Widget child;
    if (entry == null) {
      child = IconButton(
        icon: Icon(Icons.bookmark_add_outlined, color: AppColors.slate, size: 22),
        tooltip: l10n.bookWishlistShort,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: width, height: 44),
        onPressed: () async {
          try {
            final edition = work['edition'] as Map<String, dynamic>;
            await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
            final repo = await ref.read(libraryRepositoryProvider.future);
            await repo.add(editionId: editionId, status: 'wishlist');
            Haptics.success();
            ref.invalidate(libraryEntryProvider(editionId));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.bookWishlistAdded)));
            }
          } catch (err) {
            if (context.mounted) showQuietError(context, l10n.quickAddFailed, err);
          }
        },
      );
    } else if (entry.status == 'wishlist') {
      child = Semantics(
        label: l10n.bookWishlistShort,
        child: SizedBox(
          height: 44,
          child: Icon(Icons.bookmark, color: AppColors.slate, size: 22),
        ),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return SizedBox(width: width, child: Center(child: child));
  }
}

