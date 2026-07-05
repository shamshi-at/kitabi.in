import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/catalog_providers.dart';
import 'catalog_result_tile.dart';

/// S4c — every catalog work by one author. The owned/not-owned split from
/// the mockup depends on the personal library (Phase 3); until then this
/// shows the full catalog list undivided.
class AuthorBrowseScreen extends ConsumerWidget {
  const AuthorBrowseScreen({super.key, required this.authorId});

  final String authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(authorWorksProvider(authorId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: data.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(authorWorksProvider(authorId))),
          data: (body) {
            final author = body['author'] as Map<String, dynamic>;
            final works = (body['works'] as List).cast<Map<String, dynamic>>();
            final name = author['name'] as String;
            final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
            final imageUrl = author['image_url'] as String?;
            final penName = author['pen_name'] as String?;

            return ListView(
              padding: EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColors.ink),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      l10n.authorBrowseLabel,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.goldSoft,
                      foregroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                      child: imageUrl == null
                          ? Text(
                              initials,
                              style: TextStyle(
                                color: Color(0xFF8F681E),
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: Theme.of(context).textTheme.titleLarge),
                          if (penName != null && penName.isNotEmpty)
                            Text(
                              l10n.authorWritingAs(penName),
                              style: TextStyle(
                                color: AppColors.oxblood,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          Text(
                            l10n.authorBrowseWorksCount(works.length),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                if (works.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l10n.browseEmpty,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                    ),
                  )
                else
                  for (final work in works) CatalogResultTile(work: work),
              ],
            );
          },
        ),
      ),
    );
  }
}
