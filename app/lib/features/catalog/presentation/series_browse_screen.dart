import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/report_review.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
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
                    _SeriesRatingCard(seriesId: seriesId),
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


/// The reader's own rating and review **of the series** — a different claim
/// from anything they said about its volumes, kept in its own row and its own
/// pool (API migration 000044). Followed by what other readers said.
class _SeriesRatingCard extends ConsumerWidget {
  const _SeriesRatingCard({required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mine = ref.watch(seriesRatingProvider(seriesId));
    final myReview = ref.watch(seriesReviewProvider(seriesId));
    final community = ref.watch(seriesReviewsProvider(seriesId));
    final value = mine.valueOrNull?.value ?? 0;
    final average = (community.valueOrNull?['rating_average'] as num?)?.toDouble();
    final count = community.valueOrNull?['rating_count'] as int? ?? 0;
    // Parsed eagerly: `.cast()` is lazy, so a shape change would throw inside
    // this build() rather than at the fetch (CLAUDE.md, 21 Jul 2026).
    final reviews = ApiClient.parseRows(community.valueOrNull?['reviews'] ?? const []);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.seriesYourRating,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (average != null)
                Text(
                  '★ ${average.toStringAsFixed(1)} · ${l10n.seriesRatingCount(count)}',
                  style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5),
                ),
            ],
          ),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    Haptics.selection();
                    final repo = await ref.read(ratingsRepositoryProvider.future);
                    // A second tap on the selected star means "no rating",
                    // exactly as it does on a book.
                    if (i == value) {
                      await repo.clearSeriesRating(seriesId);
                    } else {
                      await repo.setSeriesRating(seriesId, i);
                    }
                    ref.invalidate(seriesRatingProvider(seriesId));
                    // Wait for the push before refetching the server-computed
                    // average, or the refetch races the sync and reads the
                    // number back unchanged.
                    await ref.read(syncNowProvider)();
                    ref.invalidate(seriesReviewsProvider(seriesId));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    child: Icon(
                      i <= value ? Icons.star : Icons.star_border,
                      size: 20,
                      color: AppColors.gold,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            l10n.seriesRatingHint,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _editReview(context, ref, myReview.valueOrNull),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(
                myReview.valueOrNull == null ? l10n.seriesWriteReview : l10n.seriesEditReview,
              ),
            ),
          ),
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              l10n.seriesReviewsHeading,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final r in reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (r['reviewer'] as Map?)?['display_name'] as String? ?? 'A reader',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (r['rating'] != null)
                          Text(
                            '★ ${r['rating']}',
                            style: TextStyle(color: AppColors.gold, fontSize: 11.5),
                          ),
                        ReportReviewButton(
                          reviewId: r['id'] as String,
                          reviewerId: (r['reviewer'] as Map?)?['id'] as String?,
                        ),
                      ],
                    ),
                    if ((r['body'] as String?)?.isNotEmpty ?? false)
                      Text(
                        r['body'] as String,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 12, height: 1.5),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _editReview(BuildContext context, WidgetRef ref, dynamic existing) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: existing?.body as String? ?? '');
    var visible = (existing?.visible as bool?) ?? false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.seriesWriteReview,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.seriesReviewHint,
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: visible,
                onChanged: (v) => setSheetState(() => visible = v),
                title: Text(l10n.reviewVisibilityHint, style: const TextStyle(fontSize: 11.5)),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(l10n.bookSave),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;

    final repo = await ref.read(reviewsRepositoryProvider.future);
    final body = controller.text.trim();
    // An emptied body means "take it back" — the same rule the book editor
    // follows, rather than silently keeping the old text.
    if (body.isEmpty) {
      await repo.removeForSeries(seriesId);
    } else {
      await repo.upsertForSeries(seriesId, body: body, visible: visible);
    }
    ref.invalidate(seriesReviewProvider(seriesId));
    await ref.read(syncNowProvider)();
    ref.invalidate(seriesReviewsProvider(seriesId));
  }
}
