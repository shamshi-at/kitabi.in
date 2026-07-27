import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/share_links.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../l10n/app_localizations.dart';
import '../../share/presentation/entity_share_sheet.dart';
import '../providers/catalog_providers.dart';
import 'catalog_result_tile.dart';
import '../../../core/widgets/net_image.dart';

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

    // The back-arrow header lives outside `data.when`, so a slow or failed
    // load never strands the reader on a chrome-less page.
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.ink),
                    onPressed: () => context.pop(),
                  ),
                  Text(
                    l10n.publisherBrowseLabel,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                  Spacer(),
                  if (data.valueOrNull != null)
                    Builder(builder: (context) {
                      final body = data.value!;
                      final publisher = body['publisher'] as Map<String, dynamic>;
                      final works = (body['works'] as List).cast<Map<String, dynamic>>();
                      final name = publisher['name'] as String;
                      return IconButton(
                        // Adaptive share glyph — ios_share reads wrong on Android.
                        icon: Icon(Icons.share_outlined, color: AppColors.oxblood),
                        tooltip: l10n.shareAction,
                        onPressed: () => showEntityShareSheet(
                          context,
                          eyebrow: l10n.sharePublisherEyebrow,
                          name: name,
                          subtitle: l10n.publisherBrowseWorksCount(works.length),
                          shareUrl: publisherShareUrl(publisherId),
                          shareText:
                              l10n.sharePublisherLinkText(name, publisherShareUrl(publisherId)),
                          imageUrl: publisher['logo_url'] as String?,
                          circular: false,
                        ),
                      );
                    }),
                ],
              ),
            ),
            Expanded(
              child: data.when(
                loading: () => ListSkeleton(),
                error: (err, _) =>
                    ErrorRetry(onRetry: () => ref.invalidate(publisherWorksProvider(publisherId))),
                data: (body) {
                  final publisher = body['publisher'] as Map<String, dynamic>;
                  final works = (body['works'] as List).cast<Map<String, dynamic>>();
                  final logoUrl = publisher['logo_url'] as String?;

                  return ListView(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [
                Row(
                  children: [
                    // The bordered tile renders unconditionally — a publisher
                    // with no logo keeps the same silhouette as the author
                    // page's monogram avatar, not a naked text row.
                    Container(
                      width: 52,
                      height: 52,
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: logoUrl != null
                          ? netImage(
                              logoUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  Icon(Icons.business, color: AppColors.inkSoft),
                            )
                          : Icon(Icons.business, color: AppColors.inkSoft),
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            publisher['name'] as String,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
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
          ],
        ),
      ),
    );
  }
}
