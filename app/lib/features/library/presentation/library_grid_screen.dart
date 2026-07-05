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
import '../reading_status.dart';

const _favouritesFilter = '__favourites__';

/// S5 — the personal library grid. Covers-first, status pills, favourite
/// ribbon, lending band; filter chips for status + favourites + personal
/// tags. The overflow-title ticker animation from the mockup is deliberately
/// not implemented (polish item, tracked in docs/tasks.md) — long titles
/// just ellipsize for now.
class LibraryGridScreen extends ConsumerStatefulWidget {
  const LibraryGridScreen({super.key});

  @override
  ConsumerState<LibraryGridScreen> createState() => _LibraryGridScreenState();
}

class _LibraryGridScreenState extends ConsumerState<LibraryGridScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(libraryEntriesProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (allEntries) {
            final filtered = allEntries.where((e) {
              if (_filter == 'all') return true;
              if (_filter == _favouritesFilter) return e.isFavorite;
              return e.status == _filter;
            }).toList();

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.libraryTitle, style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          l10n.libraryBookCount(allEntries.length),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: l10n.libraryFilterAll,
                                selected: _filter == 'all',
                                onTap: () => setState(() => _filter = 'all'),
                              ),
                              for (final status in readingStatuses)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _FilterChip(
                                    label: readingStatusLabel(status),
                                    selected: _filter == status,
                                    onTap: () => setState(() => _filter = status),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _FilterChip(
                                  label: l10n.libraryFilterFavourites,
                                  selected: _filter == _favouritesFilter,
                                  onTap: () => setState(() => _filter = _favouritesFilter),
                                ),
                              ),
                            ],
                          ),
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
                          l10n.libraryEmpty,
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
                        (context, index) => _LibraryGridItem(entry: filtered[index]),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.paper : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _LibraryGridItem extends ConsumerWidget {
  const _LibraryGridItem({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(cachedBookProvider(entry.editionId));
    final lending = ref.watch(lendingRecordsProvider(entry.id));
    final book = cached.valueOrNull;
    final activeLending = (lending.valueOrNull ?? [])
        .where((r) => r.returnedDate == null)
        .firstOrNull;

    return GestureDetector(
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TypesetCover(
                  title: book?.title ?? '…',
                  author: book?.authorNames,
                  coverUrl: book?.coverUrl,
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
