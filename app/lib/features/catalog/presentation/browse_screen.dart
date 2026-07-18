import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/expanding_fab.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/catalog_cache.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import 'catalog_entity_tiles.dart';

/// Discover (S4/browse) — wander the whole catalog: every book, author and
/// publisher. Rebuilt 18 Jul 2026 to match the library's "cool" feel (owner
/// request, Apple Books reference): the Books tab is a wall of standing covers
/// on gold ledges, the tall header steps back on scroll while the tabs stay
/// pinned, and search + filter live on the same expanding floating control the
/// library uses — the old inline sort/language/type/genre dropdown row is gone,
/// folded into the fab's filter sheet.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Books facets — lifted out of the tab into the screen so the floating
  // filter sheet drives them (the tab just reads them and re-keys on change).
  String _sort = 'title';
  String? _language;
  String? _form;
  String? _genre;

  // What the filter sheet offers — best-effort; a failed fetch just leaves
  // that facet showing "All", never blocks browsing.
  List<String> _languages = [];
  List<String> _forms = [];
  List<String> _genres = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      // The fab's Filter action only exists on the Books tab (the facets are
      // book-only) — rebuild when the tab changes so it appears/vanishes.
      ..addListener(() {
        if (!_tab.indexIsChanging) setState(() {});
      });
    final api = ref.read(apiClientProvider);
    api.browseLanguages().then((v) {
      if (mounted) setState(() => _languages = v);
    }).catchError((_) {});
    api.browseForms().then((v) {
      if (mounted) setState(() => _forms = v);
    }).catchError((_) {});
    api.browseGenres().then((v) {
      if (mounted) setState(() => _genres = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  int get _activeFacetCount =>
      (_language != null ? 1 : 0) + (_form != null ? 1 : 0) + (_genre != null ? 1 : 0);

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_CatalogFacets>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CatalogFilterSheet(
        current: _CatalogFacets(sort: _sort, language: _language, form: _form, genre: _genre),
        languages: _languages,
        forms: _forms,
        genres: _genres,
      ),
    );
    if (result == null) return;
    setState(() {
      _sort = result.sort;
      _language = result.language;
      _form = result.form;
      _genre = result.genre;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final api = ref.read(apiClientProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            NestedScrollView(
              headerSliverBuilder: (context, _) => [
                // Tall header: back + title. Floating + snap, NOT pinned — it
                // scrolls away as you go down the shelf and snaps back the
                // moment you scroll up, so a long catalogue never traps you.
                SliverAppBar(
                  backgroundColor: AppColors.paper,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  floating: true,
                  snap: true,
                  titleSpacing: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.ink),
                    onPressed: () => context.pop(),
                  ),
                  title: Text(l10n.browseTitle, style: Theme.of(context).textTheme.titleLarge),
                ),
                // The tabs stay pinned once the header is gone, so you can
                // switch Books/Authors/Publishers from anywhere. Absorbed so
                // each tab's inner scroll view sits below it, not under it.
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                  sliver: SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTabBar(
                      TabBar(
                        controller: _tab,
                        labelColor: AppColors.oxblood,
                        unselectedLabelColor: AppColors.inkSoft,
                        indicatorColor: AppColors.oxblood,
                        tabs: [
                          Tab(text: l10n.browseTabBooks),
                          Tab(text: l10n.browseTabAuthors),
                          Tab(text: l10n.browseTabPublishers),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tab,
                children: [
                  _PagedCatalogView(
                    // Re-key on facet/sort change so pagination resets to page 1
                    // (every facet is applied server-side; filtering an
                    // already-fetched page would hide matches further in).
                    key: ValueKey('books|$_sort|$_language|$_form|$_genre'),
                    storageKey: 'catalog-books',
                    fetch: (limit, offset) => api.browseWorks(
                      limit: limit,
                      offset: offset,
                      sort: _sort,
                      language: _language,
                      form: _form,
                      genre: _genre,
                    ),
                    emptyText: l10n.browseEmpty,
                    sliverBuilder: (context, works) => _BooksGridSliver(works: works),
                  ),
                  _PagedCatalogView(
                    key: const ValueKey('authors'),
                    storageKey: 'catalog-authors',
                    fetch: (limit, offset) => api.browseAuthors(limit: limit, offset: offset),
                    emptyText: l10n.browseEmpty,
                    sliverBuilder: (context, authors) => _RowsSliver(
                      rows: [
                        for (final a in authors)
                          AuthorRowTile(
                            author: a,
                            onTap: () => context.push(Routes.authorBrowsePath(a['id'] as String)),
                          ),
                      ],
                    ),
                  ),
                  _PagedCatalogView(
                    key: const ValueKey('publishers'),
                    storageKey: 'catalog-publishers',
                    fetch: (limit, offset) => api.browsePublishers(limit: limit, offset: offset),
                    emptyText: l10n.browseEmpty,
                    sliverBuilder: (context, publishers) => _RowsSliver(
                      rows: [
                        for (final p in publishers)
                          PublisherRowTile(
                            publisher: p,
                            onTap: () =>
                                context.push(Routes.publisherBrowsePath(p['id'] as String)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Search follows you down every tab; Filter only where facets mean
            // something — the Books tab (owner request, 18 Jul 2026).
            ExpandingFab(
              semanticLabel: l10n.browseFabLabel,
              actions: [
                ExpandingFabAction(
                  icon: Icons.search,
                  label: l10n.searchTitle,
                  onPressed: () => context.push(Routes.catalogSearch),
                ),
                if (_tab.index == 0)
                  ExpandingFabAction(
                    icon: Icons.tune,
                    label: l10n.libraryFilterTitle,
                    badge: _activeFacetCount,
                    onPressed: _openFilterSheet,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds the TabBar at the top of the body while the header above it scrolls
/// away — a fixed-height pinned band on paper so covers don't show through.
class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  const _PinnedTabBar(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.paper,
      alignment: Alignment.center,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabBar old) => old.tabBar != tabBar;
}

/// A tab body: offset-paged, infinite-scroll, rendered as slivers so it can sit
/// under the pinned TabBar inside the [NestedScrollView]. Loads the first page
/// on mount and the next as the reader nears the bottom, until a short page
/// signals the end. Kept alive so scroll position and loaded pages survive a
/// tab switch. The Books tab re-keys on facet change (fresh state = reload).
class _PagedCatalogView extends StatefulWidget {
  const _PagedCatalogView({
    super.key,
    required this.fetch,
    required this.sliverBuilder,
    required this.emptyText,
    required this.storageKey,
  });

  final Future<List<Map<String, dynamic>>> Function(int limit, int offset) fetch;
  final Widget Function(BuildContext, List<Map<String, dynamic>>) sliverBuilder;
  final String emptyText;
  final String storageKey;

  @override
  State<_PagedCatalogView> createState() => _PagedCatalogViewState();
}

class _PagedCatalogViewState extends State<_PagedCatalogView>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 40;
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _end = false;
  bool _errored = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() {
      _loading = true;
      _errored = false;
    });
    try {
      final page = await widget.fetch(_pageSize, _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        if (page.length < _pageSize) _end = true;
      });
    } catch (_) {
      if (mounted) setState(() => _errored = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final injector = SliverOverlapInjector(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
    );

    Widget content;
    if (_items.isEmpty) {
      if (_loading) {
        // hasScrollBody: true — ListSkeleton is a shrink-wrapping ListView, and
        // a fill-remaining that measures its intrinsics would crash on the
        // shrink-wrapping viewport.
        content = SliverFillRemaining(hasScrollBody: true, child: ListSkeleton());
      } else if (_errored) {
        content = SliverFillRemaining(hasScrollBody: false, child: ErrorRetry(onRetry: _loadMore));
      } else {
        content = SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                widget.emptyText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
              ),
            ),
          ),
        );
      }
    } else {
      content = widget.sliverBuilder(context, _items);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        key: PageStorageKey(widget.storageKey),
        slivers: [
          injector,
          content,
          // Trailing row: spinner while loading more, retry on error, nothing
          // when the end is reached. Bottom pad clears the floating control.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96, top: 4),
              child: _items.isEmpty
                  ? const SizedBox.shrink()
                  : _loading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : _errored
                          ? Center(
                              child: TextButton(
                                onPressed: _loadMore,
                                child: Text(AppLocalizations.of(context)!.commonRetry),
                              ),
                            )
                          : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Apple Books wall: catalog works as standing covers, three across, each
/// on a gold ledge with its title/author beneath and a quick-add badge.
class _BooksGridSliver extends StatelessWidget {
  const _BooksGridSliver({required this.works});

  final List<Map<String, dynamic>> works;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 18,
          crossAxisSpacing: 16,
          childAspectRatio: 0.50,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _CatalogGridCell(work: works[i]),
          childCount: works.length,
        ),
      ),
    );
  }
}

/// A plain rows sliver — the Authors/Publishers tabs keep their existing list
/// tiles; only Books gets the cover wall.
class _RowsSliver extends StatelessWidget {
  const _RowsSliver({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      sliver: SliverList(delegate: SliverChildListDelegate(rows)),
    );
  }
}

/// One book on the wall: a standing cover on a gold ledge, a quick-add badge in
/// the corner, and the title/author beneath. Tapping the cover opens the book;
/// the badge adds it to the library (or shows a moss check once owned).
class _CatalogGridCell extends StatelessWidget {
  const _CatalogGridCell({required this.work});

  final Map<String, dynamic> work;

  @override
  Widget build(BuildContext context) {
    final title = work['title'] as String? ?? '';
    final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authorName = authors.isNotEmpty ? authors.first['name'] as String? : null;
    final edition = work['edition'] as Map<String, dynamic>?;
    final coverUrl = edition?['cover_url'] as String?;
    final workId = work['id'] as String?;
    final editionId = edition?['id'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: workId != null && editionId != null
                ? () => context.push(Routes.bookDetailPath(workId, editionId))
                : null,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: TypesetCover(
                          title: title,
                          author: authorName,
                          coverUrl: coverUrl,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      if (editionId != null)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _QuickAddBadge(work: work, editionId: editionId),
                        ),
                    ],
                  ),
                ),
                // The gold ledge every book stands on — the same hairline the
                // home strip and shelf tiles use.
                const SizedBox(height: 4),
                Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.gold.withValues(alpha: 0),
                      AppColors.gold.withValues(alpha: 0.55),
                      AppColors.gold.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        if (authorName != null)
          Text(
            authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
          ),
      ],
    );
  }
}

/// The corner badge on a catalog cover: a soft "＋" to add it straight to the
/// library, a moss check once owned (offline-first — writes to Drift + the
/// sync queue, same as the row tile's quick-add).
class _QuickAddBadge extends ConsumerWidget {
  const _QuickAddBadge({required this.work, required this.editionId});

  final Map<String, dynamic> work;
  final String editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(libraryEntryProvider(editionId)).valueOrNull != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: owned
          ? null
          : () async {
              Haptics.success();
              final edition = work['edition'] as Map<String, dynamic>;
              await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
              final repo = await ref.read(libraryRepositoryProvider.future);
              await repo.add(editionId: editionId);
              ref.invalidate(libraryEntryProvider(editionId));
            },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: owned ? AppColors.moss : const Color(0xF2FFFCF4),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Icon(
          owned ? Icons.check : Icons.add,
          size: 15,
          color: owned ? Colors.white : AppColors.oxblood,
        ),
      ),
    );
  }
}

/// The four Books facets the catalogue can narrow by. Sort always has a value;
/// language/form/genre are null when "All".
class _CatalogFacets {
  const _CatalogFacets({required this.sort, this.language, this.form, this.genre});

  final String sort;
  final String? language;
  final String? form;
  final String? genre;
}

/// The floating Filter's sheet — the sort/type/genre/language controls that
/// used to sit inline above the list, now reachable from the bottom of a long
/// catalogue. Edits a local copy; "Show books" applies it, "Clear" resets.
class _CatalogFilterSheet extends StatefulWidget {
  const _CatalogFilterSheet({
    required this.current,
    required this.languages,
    required this.forms,
    required this.genres,
  });

  final _CatalogFacets current;
  final List<String> languages;
  final List<String> forms;
  final List<String> genres;

  @override
  State<_CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<_CatalogFilterSheet> {
  late String _sort = widget.current.sort;
  late String? _language = widget.current.language;
  late String? _form = widget.current.form;
  late String? _genre = widget.current.genre;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorts = {
      'title': l10n.browseSortTitle,
      'year_desc': l10n.browseSortNewest,
      'year_asc': l10n.browseSortOldest,
      'author': l10n.browseSortAuthor,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    l10n.browseFilterHeading,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_language != null || _form != null || _genre != null || _sort != 'title')
                    TextButton(
                      onPressed: () => setState(() {
                        _sort = 'title';
                        _language = null;
                        _form = null;
                        _genre = null;
                      }),
                      child: Text(l10n.browseFilterClear,
                          style: TextStyle(color: AppColors.oxblood)),
                    ),
                ],
              ),
              _FacetLabel(l10n.browseSortLabel),
              _ChipRow(
                options: [for (final e in sorts.entries) (e.key, e.value)],
                selected: _sort,
                onSelect: (v) => setState(() => _sort = v),
              ),
              if (widget.forms.isNotEmpty) ...[
                _FacetLabel(l10n.libraryFilterType),
                _ChipRow(
                  options: [
                    (null, l10n.browseFilterAllTitle),
                    for (final f in widget.forms) (f, f),
                  ],
                  selected: _form,
                  onSelect: (v) => setState(() => _form = v),
                ),
              ],
              if (widget.genres.isNotEmpty) ...[
                _FacetLabel(l10n.libraryFilterGenre),
                _ChipRow(
                  options: [
                    (null, l10n.browseFilterAllTitle),
                    for (final g in widget.genres) (g, g),
                  ],
                  selected: _genre,
                  onSelect: (v) => setState(() => _genre = v),
                ),
              ],
              if (widget.languages.isNotEmpty) ...[
                _FacetLabel(l10n.libraryFilterLanguage),
                _ChipRow(
                  options: [
                    (null, l10n.browseFilterAllTitle),
                    for (final lang in widget.languages) (lang, lang),
                  ],
                  selected: _language,
                  onSelect: (v) => setState(() => _language = v),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(
                    _CatalogFacets(sort: _sort, language: _language, form: _form, genre: _genre),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.oxblood,
                    foregroundColor: AppColors.paper,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  child: Text(l10n.browseFilterApply),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FacetLabel extends StatelessWidget {
  const _FacetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A single-select chip row — the sheet's one control shape, reused for sort,
/// type, genre and language. [T] is the value; a chip's [label] is what shows.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({required this.options, required this.selected, required this.onSelect});

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          GestureDetector(
            onTap: () => onSelect(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: value == selected ? AppColors.oxblood : AppColors.paper,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: value == selected ? AppColors.oxblood : AppColors.line,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: value == selected ? AppColors.paper : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
