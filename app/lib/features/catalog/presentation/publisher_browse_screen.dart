import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/catalog_providers.dart';
import 'catalog_result_tile.dart';

/// S4d — every catalog work from one publisher, spanning authors. The
/// owned/genre-chip filtering from the mockup depends on the personal
/// library (Phase 3); this shows the full catalog list undivided for now.
class PublisherBrowseScreen extends ConsumerWidget {
  const PublisherBrowseScreen({super.key, required this.publisherId});

  final String publisherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(publisherWorksProvider(publisherId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (body) {
            final publisher = body['publisher'] as Map<String, dynamic>;
            final works = (body['works'] as List).cast<Map<String, dynamic>>();
            final name = publisher['name'] as String;
            final logoUrl = publisher['logo_url'] as String?;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      l10n.publisherBrowseLabel,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (logoUrl != null) ...[
                      Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.business, color: AppColors.inkSoft),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: Theme.of(context).textTheme.titleLarge),
                          Text(
                            l10n.publisherBrowseWorksCount(works.length),
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
                const SizedBox(height: 20),
                if (works.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
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
