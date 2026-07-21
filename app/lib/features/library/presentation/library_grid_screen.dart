import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/tab_reset.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/expanding_fab.dart';
import '../../../core/widgets/shelf_cover.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import '../reading_status.dart';
import 'library_filter_sheet.dart';
import 'shelf_sheets.dart';

/// S5 — the personal library. Two faces on one screen (owner pick, 17 Jul
/// 2026): the covers-first grid, and a *shelves* view — every reading status,
/// Favourites, and the reader's own shelves (personal tags) as tiles with
/// their books fanned on a little ledge. The header scrolls away; search,
/// filter and sort live on the expanding floating control instead, so they're
/// reachable from the bottom of a long shelf.
class LibraryGridScreen extends ConsumerStatefulWidget {
  const LibraryGridScreen({super.key, this.initialStatus});

  /// A status to pre-filter by (from the home "Read"/"Wishlist" shelf cards,
  /// which deep-link here as /library?status=read).
  final String? initialStatus;

  @override
  ConsumerState<LibraryGridScreen> createState() => _LibraryGridScreenState();
}

/// The shelf currently opened from the shelves view — its display name plus
/// the one fact that defines it, so the screen can tell whether a later
/// filter-sheet edit kept the reader "at" this shelf or walked away from it.
typedef _OpenShelf = ({String label, String? tagId, String? status, bool fav});

/// A shelf the shelves view can show: built-ins (statuses, Favourites) and
/// personal tags share this shape.
class _ShelfSpec {
  const _ShelfSpec({
    required this.label,
    required this.books,
    required this.open,
    this.isStatus = false,
    this.status,
  });

  /// The reading status this tile stands for, when it is one — drives the mark.
  final String? status;

  /// Status and Favourites are shelves the app gives you; the rest are ones
  /// you made. They're different kinds of thing, so they get different rows
  /// (owner request, 21 Jul 2026) — the given ones scroll sideways, yours
  /// stay a grid you can scan.
  final bool isStatus;

  final String label;
  final List<LibraryHit> books;
  final _OpenShelf open;
}

class _LibraryGridScreenState extends ConsumerState<LibraryGridScreen> {
  late LibraryFilter _filter = widget.initialStatus == null
      ? const LibraryFilter()
      : LibraryFilter(statuses: {widget.initialStatus!});

  /// This session's view-mode override; null = follow the persisted
  /// preference. A status deep-link always lands on the grid.
  late bool? _shelvesOverride = widget.initialStatus == null ? null : false;

  _OpenShelf? _openShelf;

  /// 'recent' (createdAt desc — the default), 'title', or 'author'.
  String _sort = 'recent';

  final _scroll = ScrollController();

  // Guards the one-shot cover backfill so the stream re-emit it causes doesn't
  // re-trigger it in a loop.
  bool _coverRefreshTried = false;

  bool _hydrateTried = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Land fresh on the "All books" grid — closes any opened shelf, clears the
  /// filter and sort, forces the grid view (not the persisted shelves
  /// preference), and scrolls to the top. Fired when the reader taps the
  /// Library footer tab (owner request, 19 Jul 2026: always the first page).
  void _resetToFresh() {
    setState(() {
      _openShelf = null;
      _shelvesOverride = false;
      _filter = const LibraryFilter();
      _sort = 'recent';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

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
    // the read filter instead of leaving it stuck selected. A status link also
    // forces the grid: home's "Read" card promises a grid of read books, not
    // the shelves overview with a hidden filter.
    if (widget.initialStatus != old.initialStatus) {
      setState(() {
        _openShelf = null;
        _filter = widget.initialStatus == null
            ? const LibraryFilter()
            : LibraryFilter(statuses: {widget.initialStatus!});
        if (widget.initialStatus != null) _shelvesOverride = false;
      });
    }
  }

  void _setShelvesView(bool shelves) {
    Haptics.selection();
    setState(() {
      _shelvesOverride = shelves;
      _openShelf = null;
      if (shelves) _filter = const LibraryFilter();
    });
    // Persist the preference — a reader who thinks in shelves shouldn't have
    // to re-toggle every launch. Fire-and-forget; the provider re-reads lazily.
    ref.read(appDatabaseProvider).keyValuesDao.setValue('library_shelves_view', '$shelves');
  }

  void _openShelfTile(_ShelfSpec spec) {
    Haptics.selection();
    setState(() {
      _openShelf = spec.open;
      _filter = LibraryFilter(
        statuses: spec.open.status != null ? {spec.open.status!} : const {},
        favouritesOnly: spec.open.fav,
        shelf: spec.open.tagId,
      );
    });
  }

  void _closeShelf() {
    setState(() {
      _openShelf = null;
      _filter = const LibraryFilter();
    });
  }

  /// Whether [filter] still narrows to the opened shelf — a later filter-sheet
  /// edit that keeps the shelf facet keeps the shelf title; removing it walks
  /// the reader back to the whole library heading.
  bool _stillAtShelf(LibraryFilter filter) {
    final shelf = _openShelf;
    if (shelf == null) return false;
    if (shelf.tagId != null) return filter.shelf == shelf.tagId;
    if (shelf.fav) return filter.favouritesOnly;
    return shelf.status != null && filter.statuses.contains(shelf.status);
  }

  Future<void> _openFilterSheet(
    List<LibraryHit> all,
    List<PersonalTag> shelves,
    Map<String, Set<String>> shelvesOf,
  ) async {
    final result = await showLibraryFilterSheet(
      context,
      hits: all,
      current: _filter,
      shelves: shelves,
      shelvesOf: shelvesOf,
    );
    if (result == null) return;
    setState(() {
      _filter = result;
      if (!_stillAtShelf(result)) _openShelf = null;
      // Any filter work means the reader wants the grid, not the tiles.
      _shelvesOverride = false;
    });
  }

  Future<void> _openSortSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final options = {
      'recent': l10n.librarySortRecent,
      'title': l10n.librarySortAZ,
      'author': l10n.librarySortAuthor,
    };
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.librarySortTitle,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final entry in options.entries)
              ListTile(
                dense: true,
                title: Text(
                  entry.value,
                  style: TextStyle(
                    fontWeight: _sort == entry.key ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                trailing: _sort == entry.key
                    ? Icon(Icons.check, size: 18, color: AppColors.oxblood)
                    : null,
                onTap: () => Navigator.of(ctx).pop(entry.key),
              ),
            SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _sort = chosen);
  }

  List<LibraryHit> _sorted(List<LibraryHit> hits) {
    final list = [...hits];
    switch (_sort) {
      case 'title':
        list.sort((a, b) => a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));
      case 'author':
        list.sort((a, b) {
          final byAuthor = a.book.authorNames
              .toLowerCase()
              .compareTo(b.book.authorNames.toLowerCase());
          if (byAuthor != 0) return byAuthor;
          return a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase());
        });
      default: // recent — the shelf grows from the front, like Home's strip.
        list.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
    }
    return list;
  }

  Future<void> _newShelf() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(l10n.libraryNewShelfTitle, style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.libraryNewShelfHint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    final cleaned = name?.trim();
    if (cleaned == null || cleaned.isEmpty || !mounted) return;
    final repo = await ref.read(tagsRepositoryProvider.future);
    // Case-insensitive reuse, same as the book page — "classics" and
    // "Classics" are one shelf, not near-duplicates.
    final existing = (await ref.read(allTagsProvider.future))
        .where((t) => t.name.toLowerCase() == cleaned.toLowerCase());
    if (existing.isEmpty) await repo.createTag(cleaned);
    ref.invalidate(allTagsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // A tap on the Library footer tab bumps this — reset to the fresh first page.
    ref.listen(libraryTabResetProvider, (_, _) => _resetToFresh());
    final hits = ref.watch(libraryHitsProvider);
    final shelves = ref.watch(personalShelvesProvider).valueOrNull ?? const <PersonalTag>[];
    final shelvesOf =
        ref.watch(entryShelvesProvider).valueOrNull ?? const <String, Set<String>>{};
    // Defaults to Shelves now that it leads the toggle — a saved preference
    // still wins, so anyone who chose All books keeps it.
    final prefersShelves = ref.watch(libraryShelvesViewProvider).valueOrNull ?? true;

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

            final shelvesView = _openShelf == null && (_shelvesOverride ?? prefersShelves);
            final filtered =
                _sorted(all.where((h) => _filter.matches(h, shelvesOf: shelvesOf)).toList());
            final sortedShelves = [...shelves]
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            return Stack(
              children: [
                // An opened shelf is in-screen state, not a pushed route, so
                // the app-wide edge-swipe-back has nothing to pop and the
                // shelf felt like a trap (owner report, 21 Jul 2026). A
                // horizontal fling closes it. Both directions are accepted:
                // the grid underneath never scrolls sideways, so there's
                // nothing to disambiguate against, and "swipe back" means
                // opposite things to different hands.
                GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onHorizontalDragEnd: _openShelf == null
                      ? null
                      : (details) {
                          final v = details.primaryVelocity ?? 0;
                          if (v.abs() < 250) return; // a real fling, not a nudge
                          Haptics.selection();
                          setState(() => _openShelf = null);
                        },
                  child: RefreshIndicator(
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
                    controller: _scroll,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _Header(
                          openShelf: _openShelf?.label,
                          count: shelvesView ? all.length : filtered.length,
                          shelvesView: shelvesView,
                          showToggle: _openShelf == null && all.isNotEmpty,
                          onBack: _closeShelf,
                          onViewChanged: _setShelvesView,
                          // A visible "add books" on an open personal shelf, so
                          // filling it doesn't depend on finding the fab action.
                          onAddBooks: _openShelf?.tagId != null
                              ? () => showAddBooksToShelfSheet(
                                    context,
                                    tagId: _openShelf!.tagId!,
                                    shelfName: _openShelf!.label,
                                  )
                              : null,
                        ),
                      ),
                      if (all.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.auto_stories_outlined,
                            title: l10n.libraryEmptyTitle,
                            body: l10n.libraryEmpty,
                            action: ElevatedButton.icon(
                              onPressed: () => context.push(Routes.catalogSearch),
                              icon: Icon(Icons.add, size: 18),
                              label: Text(l10n.homeAddBook),
                            ),
                          ),
                        )
                      else if (shelvesView)
                        _ShelvesSliver(
                          specs: _shelfSpecs(l10n, all, sortedShelves, shelvesOf),
                          onOpen: _openShelfTile,
                          onNewShelf: _newShelf,
                        )
                      else if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          // An opened personal shelf with nothing on it isn't a
                          // dead end — offer to shelve books you already have,
                          // rather than the bare "no matches" the filter shows.
                          child: _openShelf?.tagId != null
                              ? EmptyState(
                                  icon: Icons.library_add_outlined,
                                  title: l10n.libraryShelfEmptyTitle,
                                  body: l10n.libraryShelfEmptyBody,
                                  action: ElevatedButton.icon(
                                    onPressed: () => showAddBooksToShelfSheet(
                                      context,
                                      tagId: _openShelf!.tagId!,
                                      shelfName: _openShelf!.label,
                                    ),
                                    icon: Icon(Icons.add, size: 18),
                                    label: Text(l10n.libraryShelfAddBooks),
                                  ),
                                )
                              : EmptyState(
                                  icon: Icons.filter_alt_off_outlined,
                                  title: l10n.libraryNoMatches,
                                ),
                        )
                      else
                        SliverPadding(
                          // Bottom padding clears the floating control, so the
                          // last row's covers are never stuck under it.
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 96),
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
                  ),
                ),
                // Search/filter/sort follow the reader down the shelf — the
                // header (and its old icon buttons) scroll away instead of
                // pinning (owner request, 17 Jul 2026). Shelves view only
                // carries Search: its tiles ARE the filter.
                ExpandingFab(
                  semanticLabel: l10n.libraryFabLabel,
                  actions: [
                    ExpandingFabAction(
                      icon: Icons.search,
                      label: l10n.searchTitle,
                      onPressed: () => context.push(Routes.catalogSearch),
                    ),
                    // On an open personal shelf, shelving more books is one tap
                    // from anywhere — not just from the empty state.
                    if (_openShelf?.tagId != null)
                      ExpandingFabAction(
                        icon: Icons.library_add_outlined,
                        label: l10n.libraryShelfAddBooksShort,
                        onPressed: () => showAddBooksToShelfSheet(
                          context,
                          tagId: _openShelf!.tagId!,
                          shelfName: _openShelf!.label,
                        ),
                      ),
                    if (!shelvesView) ...[
                      ExpandingFabAction(
                        icon: Icons.tune,
                        label: l10n.libraryFilterTitle,
                        badge: _filter.activeCount,
                        onPressed: () => _openFilterSheet(all, sortedShelves, shelvesOf),
                      ),
                      ExpandingFabAction(
                        icon: Icons.swap_vert,
                        label: l10n.librarySortTitle,
                        onPressed: _openSortSheet,
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The shelves to show: reading statuses and Favourites first (built-ins
  /// everyone has, so the view works before a single personal shelf exists),
  /// then the reader's own, A–Z. Built-ins hide when empty; personal shelves
  /// always show — you made them, they're yours even at zero.
  List<_ShelfSpec> _shelfSpecs(
    AppLocalizations l10n,
    List<LibraryHit> all,
    List<PersonalTag> shelves,
    Map<String, Set<String>> shelvesOf,
  ) {
    final specs = <_ShelfSpec>[];
    // Every status keeps its tile, even at zero (owner request, 21 Jul 2026).
    // Hiding an empty one is why "add Stopped" was ever a request: it was
    // always in this list, just invisible until something was in it — so a
    // status you can't see reads as one that doesn't exist.
    for (final status in ['reading', 'pending', 'read', 'stopped', 'wishlist']) {
      final books = all.where((h) => h.entry.status == status).toList();
      {
        specs.add(_ShelfSpec(
          label: readingStatusLabel(status),
          books: books,
          open: (label: readingStatusLabel(status), tagId: null, status: status, fav: false),
          isStatus: true,
          status: status,
        ));
      }
    }
    final favourites = all.where((h) => h.entry.isFavorite).toList();
    {
      specs.add(_ShelfSpec(
        label: l10n.libraryShelfFavourites,
        books: favourites,
        open: (label: l10n.libraryShelfFavourites, tagId: null, status: null, fav: true),
        isStatus: true,
        status: 'favourite',
      ));
    }
    for (final shelf in shelves) {
      final books =
          all.where((h) => shelvesOf[h.entry.id]?.contains(shelf.id) ?? false).toList();
      specs.add(_ShelfSpec(
        label: shelf.name,
        books: books,
        open: (label: shelf.name, tagId: shelf.id, status: null, fav: false),
      ));
    }
    return specs;
  }
}

/// The library heading. Normally the title + live count + the view toggle;
/// with a shelf open, the shelf's own name with a back affordance — the
/// mockup's "Favourites · 12 books · a shelf" heading.
class _Header extends StatelessWidget {
  const _Header({
    required this.openShelf,
    required this.count,
    required this.shelvesView,
    required this.showToggle,
    required this.onBack,
    required this.onViewChanged,
    this.onAddBooks,
  });

  final String? openShelf;
  final int count;
  final bool shelvesView;
  final bool showToggle;
  final VoidCallback onBack;
  final ValueChanged<bool> onViewChanged;

  /// When set (an open personal shelf), a visible "Add books" action.
  final VoidCallback? onAddBooks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (openShelf != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 12, 12, 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.ink),
              tooltip: l10n.libraryViewShelves,
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(openShelf!, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    l10n.libraryBookCount(count),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (onAddBooks != null)
              TextButton.icon(
                onPressed: onAddBooks,
                icon: Icon(Icons.add, size: 18, color: AppColors.oxblood),
                label: Text(
                  l10n.libraryShelfAddBooksShort,
                  style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.libraryTitle, style: Theme.of(context).textTheme.titleLarge),
          Text(
            l10n.libraryBookCount(count),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
          if (showToggle) ...[
            SizedBox(height: 10),
            _ViewToggle(shelvesView: shelvesView, onChanged: onViewChanged),
          ],
        ],
      ),
    );
  }
}

/// "Shelves ｜ All books" — the same segmented language the lending ledger's
/// tabs use: two equal halves, the active one solid oxblood. Shelves leads
/// (owner request, 21 Jul 2026) because it answers "where is my…"; the flat
/// grid of everything is the fallback, not the front door.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.shelvesView, required this.onChanged});

  final bool shelvesView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget half(String label, bool isShelves) {
      final active = shelvesView == isShelves;
      return Expanded(
        child: GestureDetector(
          onTap: active ? null : () => onChanged(isShelves),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: active ? AppColors.oxblood : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.paper : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.line),
      ),
      padding: EdgeInsets.all(3),
      child: Row(
        children: [
          half(l10n.libraryViewShelves, true),
          half(l10n.libraryViewAll, false),
        ],
      ),
    );
  }
}

/// The shelves view: a 2-up grid of shelf tiles, ending in "New shelf".
class _ShelvesSliver extends StatelessWidget {
  const _ShelvesSliver({
    required this.specs,
    required this.onOpen,
    required this.onNewShelf,
  });

  final List<_ShelfSpec> specs;
  final ValueChanged<_ShelfSpec> onOpen;
  final VoidCallback onNewShelf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Two kinds of shelf, two treatments: the ones the app gives you (status +
    // Favourites) run along one sideways row, and the ones you made get the
    // grid, because that's the set that grows and needs scanning.
    final status = [for (final s in specs) if (s.isStatus) s];
    final custom = [for (final s in specs) if (!s.isStatus) s];

    return SliverMainAxisGroup(
      slivers: [
        if (status.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionLabel(l10n.libraryShelvesStatusSection),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 20),
                itemCount: status.length,
                separatorBuilder: (_, _) => SizedBox(width: 14),
                itemBuilder: (context, i) => SizedBox(
                  width: 156,
                  child: _ShelfTile(spec: status[i], onTap: () => onOpen(status[i])),
                ),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: _SectionLabel(l10n.libraryShelvesYoursSection),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.02,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => index < custom.length
                  ? _ShelfTile(spec: custom[index], onTap: () => onOpen(custom[index]))
                  : _NewShelfTile(onTap: onNewShelf),
              childCount: custom.length + 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small caps label separating the two shelf families.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// One shelf: its first few books fanned on a little ledge (a gold shelf
/// line), the name, and a live count. A real bookcase in miniature.
class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.spec, required this.onTap});

  final _ShelfSpec spec;
  final VoidCallback onTap;

  static const _angles = [-0.16, -0.04, 0.10];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = spec.books.take(3).toList();
    final status = spec.status;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.paperDeep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            // Wishlist is the odd one out — books you don't own yet — so it
            // carries its own slate edge rather than blending into the row.
            color: status == 'wishlist' ? AppColors.slate : AppColors.line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // The ledge every book stands on — same gold hairline the
                  // home strip uses.
                  Positioned(
                    left: 2,
                    right: 2,
                    bottom: 5,
                    child: Container(
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          AppColors.gold.withValues(alpha: 0),
                          AppColors.gold.withValues(alpha: 0.6),
                          AppColors.gold.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                  for (final (i, hit) in preview.indexed)
                    Positioned(
                      left: 4.0 + i * 26,
                      bottom: 7,
                      child: Transform.rotate(
                        angle: _angles[i],
                        alignment: Alignment.bottomCenter,
                        child: TypesetCover(
                          title: hit.book.title,
                          author: hit.book.authorNames,
                          coverUrl: hit.book.coverUrl,
                          width: 40,
                          height: 60,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 7),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            Text(
              l10n.libraryBookCount(spec.books.length),
              style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
            ),
          ],
        ),
          ),
          if (status != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == 'favourite'
                      ? AppColors.goldSoft
                      : readingStatusBackground(status),
                ),
                child: Icon(
                  status == 'favourite' ? Icons.star_rounded : readingStatusIcon(status),
                  size: 13,
                  color: status == 'favourite' ? AppColors.gold : readingStatusInk(status),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The door to another shelf — gold-edged, quiet, always last.
class _NewShelfTile extends StatelessWidget {
  const _NewShelfTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 24, color: AppColors.oxblood),
            SizedBox(height: 4),
            Text(
              l10n.libraryNewShelf,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.oxblood,
              ),
            ),
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
