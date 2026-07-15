import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/shelf_cover.dart';
import '../../../core/widgets/sticky_header_delegate.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import 'library_filter_sheet.dart';

/// S5 — the personal library grid. Covers-first, status pills, favourite
/// ribbon, lending band; a filter sheet (S4b) narrows by status, language, and
/// favourites with a live count.
class LibraryGridScreen extends ConsumerStatefulWidget {
  const LibraryGridScreen({super.key, this.initialStatus});

  /// A status to pre-filter by (from the home "Read"/"Wishlist" shelf cards,
  /// which deep-link here as /library?status=read).
  final String? initialStatus;

  @override
  ConsumerState<LibraryGridScreen> createState() => _LibraryGridScreenState();
}

class _LibraryGridScreenState extends ConsumerState<LibraryGridScreen> {
  late LibraryFilter _filter = widget.initialStatus == null
      ? const LibraryFilter()
      : LibraryFilter(statuses: {widget.initialStatus!});

  // Guards the one-shot cover backfill so the stream re-emit it causes doesn't
  // re-trigger it in a loop.
  bool _coverRefreshTried = false;

  bool _hydrateTried = false;

  Future<void> _refreshMissingCovers() async {
    await refreshMissingCovers(
      ref.read(appDatabaseProvider),
      ref.read(apiClientProvider),
    );
  }

  /// Fresh-install self-heal: sync restores the entries but the cached-book
  /// rows are device-local, so without this the grid's join drops every book
  /// (home says 5 owned, library says 0). Cheap no-op when nothing is missing.
  /// Covers borrowed entries too now (they're real library_entries rows since
  /// 15 Jul 2026) — no separate borrowed-catalog hydration needed here.
  Future<void> _hydrateMissingBooks() async {
    await cacheMissingLibraryBooks(
      ref.read(appDatabaseProvider),
      ref.read(apiClientProvider),
    );
  }

  @override
  void didUpdateWidget(LibraryGridScreen old) {
    super.didUpdateWidget(old);
    // The library tab keeps its state alive, so a fresh deep-link from home
    // (a different status) must re-apply on the same widget instance — including
    // back to *no* status, so tapping "Owned" (no status) after "Read" clears
    // the read filter instead of leaving it stuck selected.
    if (widget.initialStatus != old.initialStatus) {
      setState(() => _filter = widget.initialStatus == null
          ? const LibraryFilter()
          : LibraryFilter(statuses: {widget.initialStatus!}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hits = ref.watch(libraryHitsProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: hits.when(
          loading: () => CoverGridSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(libraryHitsProvider)),
          data: (all) {
            // Fresh-install hydration: entries synced down without their
            // device-local cached-book rows are invisible to the join above —
            // rehydrate once per mount; the stream re-emits as rows land.
            if (!_hydrateTried) {
              _hydrateTried = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateMissingBooks());
            }
            // Opportunistically pull covers that were added upstream after these
            // books were cached (e.g. a catalog backfill). Once per screen mount;
            // the reactive join re-shows them as the cache rows update.
            if (!_coverRefreshTried && all.any((h) => h.book.coverUrl == null)) {
              _coverRefreshTried = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMissingCovers());
            }
            final filtered = all.where(_filter.matches).toList();
            return RefreshIndicator(
              color: AppColors.oxblood,
              onRefresh: () async {
                // A real sync round-trip — push pending local ops, pull deltas
                // (e.g. a loan the lender just marked returned) — not just a
                // provider refresh of unchanged local data.
                await ref.read(syncNowProvider)();
                ref.invalidate(libraryHitsProvider);
                ref.invalidate(allLendingProvider);
                await _hydrateMissingBooks();
                await _refreshMissingCovers();
              },
              child: CustomScrollView(
              slivers: [
                // Pinned (owner request, 16 Jul 2026) so search stays reachable
                // without scrolling back to the top of a long shelf.
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyHeaderDelegate(
                    height: 72,
                    child: Container(
                      color: AppColors.paper,
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                          IconButton(
                            icon: Icon(Icons.search, color: AppColors.oxblood),
                            tooltip: l10n.searchTitle,
                            onPressed: () => context.push(Routes.catalogSearch),
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
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: all.isEmpty
                        ? EmptyState(
                            icon: Icons.auto_stories_outlined,
                            title: l10n.libraryEmptyTitle,
                            body: l10n.libraryEmpty,
                            action: ElevatedButton.icon(
                              onPressed: () => context.push(Routes.catalogSearch),
                              icon: Icon(Icons.add, size: 18),
                              label: Text(l10n.homeAddBook),
                            ),
                          )
                        : EmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: l10n.libraryNoMatches,
                          ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 9,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.66,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        // Borrowed books (ownership: 'borrowed') are real
                        // entries now (15 Jul 2026) — one grid, banded by
                        // _LibraryGridItem, not a separate lending-sourced
                        // section.
                        (context, index) => _LibraryGridItem(hit: filtered[index]),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
              ],
              ),
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
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              SizedBox(width: 5),
              Text(
                '$activeCount',
                style: TextStyle(
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
    // Derived from the reactive ledger stream (not a one-shot per-entry
    // fetch), so lending/borrowing a book anywhere shows the band here
    // instantly.
    final activeLending = (ref.watch(allLendingProvider).valueOrNull ?? [])
        .map((r) => r.record)
        .where((r) =>
            r.libraryEntryId == entry.id &&
            r.direction != 'borrowed' &&
            r.returnedDate == null)
        .firstOrNull;
    // This entry's own borrow record, if it's ownership: 'borrowed' — the
    // unified shape every borrow gets now (15 Jul 2026). Active (not yet
    // returned) shows the "FROM name" band, same as a book lent OUT shows
    // "WITH name"; once returned the band drops so the status pill (which a
    // band otherwise hides) is visible again — reading status still matters
    // on a book you've given back.
    final borrowRecord =
        entry.ownership == 'borrowed' ? ref.watch(lendingByLibraryEntryIdProvider)[entry.id] : null;
    final isReturned = borrowRecord?.returnedDate != null;
    // The reading sliver — only when actively reading and both pages are known.
    final total = book.pageCount;
    final page = entry.currentPage;
    final progress = (entry.status == 'reading' && total != null && total > 0 && page != null)
        ? page / total
        : null;

    return GestureDetector(
      onTap: () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: ShelfCover(
        title: book.title,
        author: book.authorNames,
        coverUrl: book.coverUrl,
        status: entry.status,
        progress: progress,
        favorite: entry.isFavorite,
        lentToName: activeLending?.borrowerName,
        borrowedFromName: isReturned ? null : borrowRecord?.borrowerName,
        returned: isReturned,
      ),
    );
  }
}
