import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/recommendations_providers.dart';

/// S11 — reasoned recommendations. Opt-in, with an always-visible off switch;
/// every pick carries a plain-words "why" from the reader's own ratings. A
/// helper, not a feed.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optIn = ref.watch(recsOptInProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        top: false,
        child: optIn.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (enabled) => enabled ? const _RecsList() : const _OptInPrompt(),
        ),
      ),
    );
  }
}

class _OptInPrompt extends ConsumerWidget {
  const _OptInPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 44, color: AppColors.gold),
            const SizedBox(height: 16),
            Text(l10n.recsTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              l10n.recsOptInBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => setRecsOptIn(ref, enabled: true),
              child: Text(l10n.recsEnable),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecsList extends ConsumerStatefulWidget {
  const _RecsList();

  @override
  ConsumerState<_RecsList> createState() => _RecsListState();
}

class _RecsListState extends ConsumerState<_RecsList> {
  // Books wishlisted or dismissed this session — filtered out of the list.
  final Set<String> _handled = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recs = ref.watch(recommendationsProvider);

    return recs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('$err')),
      data: (data) {
        final enabled = data['enabled'] == true;
        final picks = ((data['picks'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .where((p) => !_handled.contains((p['work'] as Map)['id']))
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(l10n.recsTitle, style: Theme.of(context).textTheme.titleLarge),
            Text(
              l10n.recsSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            if (!enabled)
              _Note(l10n.recsUnavailable)
            else if (picks.isEmpty)
              _Note(l10n.recsColdStart)
            else
              for (final pick in picks)
                _RecCard(
                  pick: pick,
                  onWishlist: () => _wishlist(pick),
                  onDismiss: () => setState(
                    () => _handled.add((pick['work'] as Map)['id'] as String),
                  ),
                ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => setRecsOptIn(ref, enabled: false),
                child: Text(l10n.recsTurnOff),
              ),
            ),
            Center(
              child: Text(
                l10n.recsFooter,
                style: const TextStyle(fontSize: 10, color: AppColors.inkSoft),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _wishlist(Map<String, dynamic> pick) async {
    final work = pick['work'] as Map<String, dynamic>;
    final edition = work['edition'] as Map<String, dynamic>?;
    if (edition == null) return;
    await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.add(editionId: edition['id'] as String, status: 'wishlist');
    if (mounted) setState(() => _handled.add(work['id'] as String));
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  const _RecCard({required this.pick, required this.onWishlist, required this.onDismiss});

  final Map<String, dynamic> pick;
  final VoidCallback onWishlist;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final work = pick['work'] as Map<String, dynamic>;
    final why = pick['why'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final edition = work['edition'] as Map<String, dynamic>?;
    final rating = (work['aggregate_rating'] as num?)?.toDouble();
    final workId = work['id'] as String?;
    final editionId = edition?['id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: workId != null && editionId != null
                ? () => context.push(Routes.bookDetailPath(workId, editionId))
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TypesetCover(
                  title: work['title'] as String? ?? '',
                  author: author,
                  coverUrl: edition?['cover_url'] as String?,
                  width: 44,
                  height: 64,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work['title'] as String? ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      if (author != null)
                        Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
                        ),
                      if (rating != null) ...[
                        const SizedBox(height: 3),
                        _Stars(value: rating, caption: l10n.shareCatalogAvg),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
            decoration: const BoxDecoration(
              color: AppColors.paper,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              border: Border(left: BorderSide(color: AppColors.gold, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.recsWhy,
                  style: const TextStyle(
                    fontSize: 7.5,
                    letterSpacing: 1,
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  why,
                  style: const TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onWishlist,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.oxblood,
                    side: const BorderSide(color: AppColors.line),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                  child: Text(l10n.recsWishlist, style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
                  child: Text(l10n.recsNotForMe, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.caption});

  final double value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i ? Icons.star : (value >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: 12,
            color: AppColors.gold,
          ),
        const SizedBox(width: 5),
        Text(caption, style: const TextStyle(fontSize: 7.5, color: AppColors.inkSoft)),
      ],
    );
  }
}
