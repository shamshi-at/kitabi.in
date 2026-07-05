import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import 'library_filter_sheet.dart';

/// S5 — the personal library grid. Covers-first, status pills, favourite
/// ribbon, lending band; a filter sheet (S4b) narrows by status, language, and
/// favourites with a live count.
class LibraryGridScreen extends ConsumerStatefulWidget {
  const LibraryGridScreen({super.key});

  @override
  ConsumerState<LibraryGridScreen> createState() => _LibraryGridScreenState();
}

class _LibraryGridScreenState extends ConsumerState<LibraryGridScreen> {
  LibraryFilter _filter = const LibraryFilter();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hits = ref.watch(libraryHitsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: hits.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (all) {
            final filtered = all.where(_filter.matches).toList();
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.libraryTitle,
                                  style: Theme.of(context).textTheme.titleLarge),
                              Text(
                                l10n.libraryBookCount(filtered.length),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.inkSoft),
                              ),
                            ],
                          ),
                        ),
                        _FilterButton(
                          activeCount: _filter.activeCount,
                          onTap: () async {
                            final result = await showLibraryFilterSheet(
                              context,
                              hits: all,
                              current: _filter,
                            );
                            if (result != null) setState(() => _filter = result);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          all.isEmpty ? l10n.libraryEmpty : l10n.libraryNoMatches,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 9,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.62,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _LibraryGridItem(hit: filtered[index]),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 15, color: active ? AppColors.paper : AppColors.ink),
            if (active) ...[
              const SizedBox(width: 5),
              Text(
                '$activeCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.paper,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LibraryGridItem extends ConsumerWidget {
  const _LibraryGridItem({required this.hit});

  final LibraryHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = hit.entry;
    final book = hit.book;
    final lending = ref.watch(lendingRecordsProvider(entry.id));
    final activeLending = (lending.valueOrNull ?? [])
        .where((r) => r.returnedDate == null)
        .firstOrNull;

    return GestureDetector(
      onTap: () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TypesetCover(
                  title: book.title,
                  author: book.authorNames,
                  coverUrl: book.coverUrl,
                  width: double.infinity,
                  height: double.infinity,
                ),
                if (entry.isFavorite)
                  Positioned(
                    top: -2,
                    right: 6,
                    child: ClipPath(
                      clipper: _RibbonClipper(),
                      child: Container(width: 9, height: 20, color: AppColors.gold),
                    ),
                  ),
                if (activeLending != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: const Color(0xEBB8862B),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'WITH ${activeLending.borrowerName.toUpperCase()}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF241811),
                          fontSize: 6.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          StatusPill(status: entry.status),
        ],
      ),
    );
  }
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height * 0.78)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
