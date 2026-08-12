import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/catalog_providers.dart';
import 'catalog_result_tile.dart';

/// Every book in one series, in reading order — reached from a book's
/// "Book 3 of Malgudi" line.
///
/// A translated series shows each language's book at its own number rather
/// than as a separate ordering: the position belongs to the story, so book 3
/// is book 3 whichever language you are holding. The number column is what
/// carries that, which is why an unnumbered book shows a dot instead of being
/// silently renumbered by its position in the list.
class SeriesBrowseScreen extends ConsumerWidget {
  const SeriesBrowseScreen({super.key, required this.seriesId, this.seriesName});

  final String seriesId;
  final String? seriesName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final data = ref.watch(seriesWorksProvider(seriesId));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            // Outside `data.when`, so a slow or failed load never strands the
            // reader on a page with no way back.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.ink),
                    onPressed: () => context.pop(),
                  ),
                  Text(
                    l10n.seriesBrowseLabel,
                    style:
                        Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            Expanded(
              child: data.when(
                loading: () => const ListSkeleton(),
                error: (err, _) =>
                    ErrorRetry(onRetry: () => ref.invalidate(seriesWorksProvider(seriesId))),
                data: (works) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Icon(Icons.auto_stories_outlined, color: AppColors.inkSoft),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                seriesName ?? l10n.seriesBrowseLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                l10n.seriesBookCount(works.length),
                                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (works.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          l10n.seriesBrowseEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
                        ),
                      ),
                    for (final work in works)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                work['series_number']?.toString() ?? '·',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          Expanded(child: CatalogResultTile(work: work)),
                        ],
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
}
