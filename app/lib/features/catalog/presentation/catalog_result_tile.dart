import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';

/// One row for a catalog work — shared by search results and author/publisher
/// browse lists. Author and publisher names are tappable (oxblood tint)
/// everywhere they appear, per feature-map.md. A quick "＋" adds it straight to
/// the library (or shows a check once owned).
class CatalogResultTile extends ConsumerWidget {
  const CatalogResultTile({super.key, required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final edition = work['edition'] as Map<String, dynamic>?;
    final publisher = edition?['publisher'] as Map<String, dynamic>?;
    final year = work['first_publish_year'] as int?;

    final workId = work['id'] as String?;
    final editionId = edition?['id'] as String?;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                            children: [
                              for (final (i, author) in authors.indexed) ...[
                                if (i > 0)
                                  Text(', ', style: TextStyle(color: AppColors.inkSoft)),
                                GestureDetector(
                                  onTap: () => context
                                      .push(Routes.authorBrowsePath(author['id'] as String)),
                                  child: Text(
                                    author['name'] as String,
                                    style: TextStyle(
                                      color: AppColors.oxblood,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        if (publisher != null || year != null)
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (publisher != null)
                                  GestureDetector(
                                    onTap: () => context.push(
                                      Routes.publisherBrowsePath(publisher['id'] as String),
                                    ),
                                    child: Text(
                                      publisher['name'] as String,
                                      style:
                                          TextStyle(color: AppColors.oxblood, fontSize: 11),
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
                          ),
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
        Haptics.success();
        final edition = work['edition'] as Map<String, dynamic>;
        await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
        final repo = await ref.read(libraryRepositoryProvider.future);
        await repo.add(editionId: editionId);
        ref.invalidate(libraryEntryProvider(editionId));
      },
    );
  }
}
