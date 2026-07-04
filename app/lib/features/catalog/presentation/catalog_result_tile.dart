import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';

/// One row for a catalog work — shared by search results and author/publisher
/// browse lists. Author and publisher names are tappable (oxblood tint)
/// everywhere they appear, per feature-map.md.
class CatalogResultTile extends StatelessWidget {
  const CatalogResultTile({super.key, required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final edition = work['edition'] as Map<String, dynamic>?;
    final publisher = edition?['publisher'] as Map<String, dynamic>?;
    final year = work['first_publish_year'] as int?;

    final workId = work['id'] as String?;
    final editionId = edition?['id'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
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
                  const SizedBox(width: 12),
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
                                  const Text(', ', style: TextStyle(color: AppColors.inkSoft)),
                                GestureDetector(
                                  onTap: () => context
                                      .push(Routes.authorBrowsePath(author['id'] as String)),
                                  child: Text(
                                    author['name'] as String,
                                    style: const TextStyle(
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
                            padding: const EdgeInsets.only(top: 2),
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
                                          const TextStyle(color: AppColors.oxblood, fontSize: 11),
                                    ),
                                  ),
                                if (publisher != null && year != null)
                                  const Text(
                                    ' · ',
                                    style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                                  ),
                                if (year != null)
                                  Text(
                                    '$year',
                                    style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
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
          TextButton(
            onPressed: () => context.push(Routes.catalogAdd, extra: work['id'] as String),
            child: Text(
              l10n.catalogEditAction,
              style: const TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
