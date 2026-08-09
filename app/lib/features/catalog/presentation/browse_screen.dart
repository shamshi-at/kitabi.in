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
import '../../../core/quiet_error.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../../profile/providers/profile_providers.dart';
import 'catalog_entity_tiles.dart';

/// Discover (S4/browse) — wander the whole catalog: every book, author and
/// publisher. Rebuilt 18 Jul 2026 to match the library's "cool" feel (owner
/// request, Apple Books reference): the Books tab is a wall of standing covers
/// on gold ledges, the tall header steps back on scroll while the tabs stay
/// pinned. Filtering is the web's doors bar (owner pick, 9 Aug 2026,
/// docs/browse-filters-mockups.html direction C + A's sort): a segmented sort
/// control plus one small per-facet sheet — Type, Genre, Language, Length —
/// whose door label carries its value ("Genre · History"), so the bar reads
/// as a sentence. The fab keeps only Search; the old one-big-filter-sheet is
/// gone (two filter surfaces would drift — CLAUDE.md, 19 Jul lesson).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Books facets — lifted out of the tab into the screen so the doors bar
  // drives them (the tab just reads them and re-keys on change).
  String _sort = 'title';
  // null = the whole catalogue; otherwise a server-side language filter. The
  // catalogue *opens* filtered to the reader's profile languages (their
  // configured reading languages) — Discover should greet a Malayalam reader
  // with Malayalam shelves, not the global alphabet.
  List<String>? _languages;
  // Set once the reader touches the Language door (or the empty-state
  // escape) — after that, a late /me arrival must not overwrite their pick.
  bool _langTouched = false;
  String? _form;
  String? _genre;
  String? _length;

  // What the doors offer — best-effort; a failed fetch just leaves that
  // door showing "All", never blocks browsing.
  List<String> _languageOptions = [];
  List<String> _forms = [];
  List<String> _genres = [];
  // The same genres with their work counts — the "All N" door's picker ranks
  // and annotates by count, so the established spelling wins.
  List<Map<String, dynamic>> _genreRows = [];

  /// The reader's profile languages, straight from /me (empty when signed out,
  /// offline before the first /me, or none configured).
  List<String> get _preferred =>
      (ref.read(meProvider).valueOrNull?['preferred_languages'] as List?)?.cast<String>() ??
      const <String>[];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Default filter: the reader's configured languages. /me is normally
    // cached by the router's onboarding gate long before Discover opens, but
    // a cold start straight into this screen can beat it — listen and apply
    // the default late, unless the reader has already made a choice.
    if (_preferred.isNotEmpty) _languages = List.of(_preferred);
    ref.listenManual(meProvider, (_, next) {
      final langs = (next.valueOrNull?['preferred_languages'] as List?)?.cast<String>();
      if (!_langTouched && _languages == null && langs != null && langs.isNotEmpty) {
        setState(() => _languages = List.of(langs));
      }
    });
    final api = ref.read(apiClientProvider);
    api.browseLanguages().then((v) {
      if (mounted) setState(() => _languageOptions = v);
    }).catchError((_) {});
    api.browseForms().then((v) {
      if (mounted) setState(() => _forms = v);
    }).catchError((_) {});
    api.browseGenres().then((v) {
      if (mounted) {
        setState(() {
          _genreRows = v;
          _genres = [for (final g in v) g['name'] as String];
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  bool get _anyActive =>
      _sort != 'title' ||
      _languages != null ||
      _form != null ||
      _genre != null ||
      _length != null;

  bool _isPreferredSet(List<String> langs) =>
      _preferred.isNotEmpty &&
      langs.length == _preferred.length &&
      langs.toSet().containsAll(_preferred);

  /// The Language door's value label: nothing, "Your languages", or the one
  /// picked language.
  String? _languageValue(AppLocalizations l10n) {
    final langs = _languages;
    if (langs == null) return null;
    if (_isPreferredSet(langs)) return l10n.browseFilterYourLanguages;
    return langs.first;
  }

  /// One door's sheet: rows with optional counts, the current pick marked.
  /// Returns a 1-field record so "picked the clearing row" (value null) and
  /// "dismissed, change nothing" (record null) stay distinguishable.
  Future<(String?,)?> _openDoor({
    required String title,
    required List<_DoorOption> options,
    required String? selected,
  }) {
    return showModalBottomSheet<(String?,)>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FacetDoorSheet(title: title, options: options, selected: selected),
    );
  }

  Future<void> _typeDoor(AppLocalizations l10n) async {
    final picked = await _openDoor(
      title: l10n.libraryFilterType,
      options: [
        _DoorOption(null, l10n.browseAllTypes),
        for (final f in _forms) _DoorOption(f, f),
      ],
      selected: _form,
    );
    if (picked == null || !mounted) return;
    setState(() => _form = picked.$1);
  }

  Future<void> _genreDoor(AppLocalizations l10n) async {
    final counts = {
      for (final g in _genreRows)
        if (g['name'] is String) g['name'] as String: g['work_count'] as int?,
    };
    final picked = await _openDoor(
      title: l10n.libraryFilterGenre,
      options: [
        _DoorOption(null, l10n.browseAllGenres),
        for (final g in _genres) _DoorOption(g, g, count: counts[g]),
      ],
      selected: _genre,
    );
    if (picked == null || !mounted) return;
    setState(() => _genre = picked.$1);
  }

  /// "Your languages" travels as this sentinel so the sheet stays a plain
  /// single-select over strings.
  static const _kMine = '__your_languages__';

  Future<void> _languageDoor(AppLocalizations l10n) async {
    final langs = _languages;
    final picked = await _openDoor(
      title: l10n.libraryFilterLanguage,
      options: [
        if (_preferred.isNotEmpty) _DoorOption(_kMine, l10n.browseFilterYourLanguages),
        _DoorOption(null, l10n.browseAllLanguages),
        for (final lang in _languageOptions) _DoorOption(lang, lang),
      ],
      selected: langs == null
          ? null
          : _isPreferredSet(langs)
              ? _kMine
              : langs.first,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _langTouched = true;
      _languages = picked.$1 == null
          ? null
          : picked.$1 == _kMine
              ? List.of(_preferred)
              : [picked.$1!];
    });
  }

  Future<void> _lengthDoor(AppLocalizations l10n) async {
    final picked = await _openDoor(
      title: l10n.browseFilterLength,
      options: [
        _DoorOption(null, l10n.browseAnyLength),
        _DoorOption('short', l10n.browseLengthShort),
        _DoorOption('medium', l10n.browseLengthMedium),
        _DoorOption('long', l10n.browseLengthLong),
      ],
      selected: _length,
    );
    if (picked == null || !mounted) return;
    setState(() => _length = picked.$1);
  }

  void _clearAll() => setState(() {
        _sort = 'title';
        _languages = null;
        _langTouched = true;
        _form = null;
        _genre = null;
        _length = null;
      });

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
                    key: ValueKey('books|$_sort|${_languages?.join('+')}|$_form|$_genre|$_length'),
                    storageKey: 'catalog-books',
                    // The doors bar scrolls with the shelf (not pinned) and
                    // survives the empty state, so a dead-end filter can
                    // always be undone from where you stand.
                    headerSliver: SliverToBoxAdapter(
                      child: _DoorsBar(
                        sort: _sort,
                        sortLabels: {
                          'title': l10n.browseSortTitle,
                          'rating': l10n.browseSortTopRated,
                          'added': l10n.browseSortJustAdded,
                          'year_desc': l10n.browseSortNewest,
                          'year_asc': l10n.browseSortOldest,
                          'author': l10n.browseSortAuthor,
                        },
                        onSort: (v) => setState(() => _sort = v),
                        doors: [
                          _DoorSpec(l10n.libraryFilterType, _form, () => _typeDoor(l10n)),
                          _DoorSpec(l10n.libraryFilterGenre, _genre, () => _genreDoor(l10n)),
                          _DoorSpec(
                            l10n.libraryFilterLanguage,
                            _languageValue(l10n),
                            () => _languageDoor(l10n),
                          ),
                          _DoorSpec(
                            l10n.browseFilterLength,
                            switch (_length) {
                              'short' => l10n.browseLengthShortWord,
                              'medium' => l10n.browseLengthMediumWord,
                              'long' => l10n.browseLengthLongWord,
                              _ => null,
                            },
                            () => _lengthDoor(l10n),
                          ),
                        ],
                        showClearAll: _anyActive,
                        onClearAll: _clearAll,
                        clearAllLabel: l10n.browseClearAll,
                      ),
                    ),
                    fetch: (limit, offset) => api.browseWorks(
                      limit: limit,
                      offset: offset,
                      sort: _sort,
                      languages: _languages,
                      form: _form,
                      genre: _genre,
                      length: _length,
                    ),
                    emptyText:
                        _languages != null ? l10n.browseEmptyInYourLanguages : l10n.browseEmpty,
                    // The default filter must never dead-end a reader whose
                    // languages have no books yet — offer the whole catalogue.
                    emptyAction: _languages == null
                        ? null
                        : TextButton(
                            onPressed: () => setState(() {
                              _languages = null;
                              _langTouched = true;
                            }),
                            child: Text(
                              l10n.browseShowAllBooks,
                              style: TextStyle(
                                color: AppColors.oxblood,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
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
            // Search follows you down every tab. Filtering lives in the
            // Books tab's doors bar (9 Aug 2026) — the fab's old Filter
            // action would have been a second surface for the same facets,
            // and two surfaces drift (CLAUDE.md, 19 Jul lesson).
            ExpandingFab(
              semanticLabel: l10n.browseFabLabel,
              actions: [
                ExpandingFabAction(
                  icon: Icons.search,
                  label: l10n.searchTitle,
                  onPressed: () => context.push(Routes.catalogSearch),
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
    this.emptyAction,
    this.headerSliver,
  });

  final Future<List<Map<String, dynamic>>> Function(int limit, int offset) fetch;
  final Widget Function(BuildContext, List<Map<String, dynamic>>) sliverBuilder;
  final String emptyText;
  final String storageKey;

  /// Optional escape hatch under the empty state (e.g. "Show all books" when
  /// the your-languages default filter matched nothing).
  final Widget? emptyAction;

  /// Optional sliver rendered above the content — the Books tab's doors bar.
  /// Present in the empty state too, so a dead-end filter can be undone.
  final Widget? headerSliver;

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.emptyText,
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                  if (widget.emptyAction != null) ...[
                    const SizedBox(height: 8),
                    widget.emptyAction!,
                  ],
                ],
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
          if (widget.headerSliver != null) widget.headerSliver!,
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
                          top: -4,
                          right: -4,
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

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final edition = work['edition'] as Map<String, dynamic>;
      await cacheBookForOffline(ref.read(appDatabaseProvider), work, edition);
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.add(editionId: editionId);
      // Success feedback only after the write actually landed.
      Haptics.success();
      ref.invalidate(libraryEntryProvider(editionId));
    } catch (err) {
      if (context.mounted) showQuietError(context, l10n.quickAddFailed, err);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(libraryEntryProvider(editionId)).valueOrNull != null;
    // A 40px transparent target around the 24px visual circle — mis-taps were
    // opening the book instead of adding it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: owned ? null : () => _add(context, ref),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              // Theme-aware: `card` keeps the badge legible on night covers
              // instead of a hardcoded near-white disc.
              color: owned ? AppColors.moss : AppColors.card.withValues(alpha: 0.95),
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
        ),
      ),
    );
  }
}

/// The four Books facets the catalogue can narrow by. Sort always has a value;
/// languages/form/genre are null when "All". [languages] is a *list*: the
/// default filter is the reader's profile languages, and a single sheet pick
/// travels as a one-element list.

/// One door's descriptor: its noun, its current value (null = inactive), and
/// what opens it.
class _DoorSpec {
  const _DoorSpec(this.label, this.value, this.open);

  final String label;
  final String? value;
  final VoidCallback open;
}

/// One row a door's sheet offers. [value] null is the clearing row
/// ("All genres" / "Any length").
class _DoorOption {
  const _DoorOption(this.value, this.label, {this.count});

  final String? value;
  final String label;
  final int? count;
}

/// The web's doors bar, in Flutter (docs/browse-filters-mockups.html,
/// direction C + A's sort — owner pick, 9 Aug 2026): a segmented sort control
/// — the pick-exactly-one shape, so sort doesn't dress like a filter — then
/// one door per facet whose label carries its value ("Genre · History"), so
/// the bar reads as a sentence. Horizontally scrollable, exactly like the
/// web's control scrolls inside itself on narrow screens.
class _DoorsBar extends StatelessWidget {
  const _DoorsBar({
    required this.sort,
    required this.sortLabels,
    required this.onSort,
    required this.doors,
    required this.showClearAll,
    required this.onClearAll,
    required this.clearAllLabel,
  });

  final String sort;
  final Map<String, String> sortLabels;
  final ValueChanged<String> onSort;
  final List<_DoorSpec> doors;
  final bool showClearAll;
  final VoidCallback onClearAll;
  final String clearAllLabel;

  @override
  Widget build(BuildContext context) {
    // Two rows, like the web bar wraps on a phone: the segmented sort on its
    // own line (it scrolls inside itself — six labels outgrow any phone), the
    // doors on the next, always on screen. A single scrolling line hid the
    // doors entirely behind the seg on a 360dp device (caught on-device,
    // 9 Aug 2026) — filters a reader can't see are filters that don't exist.
    // SingleChildScrollView + Row, NOT a lazy ListView, so the tail (Length,
    // Clear all) exists for finders and semantics without scrolling.
    Widget scrollRow(Widget child) => SizedBox(
          height: 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: child,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          scrollRow(_SegSort(sort: sort, labels: sortLabels, onSort: onSort)),
          const SizedBox(height: 8),
          scrollRow(
            Row(
              children: [
                for (final door in doors) ...[
                  _Door(spec: door),
                  const SizedBox(width: 8),
                ],
                if (showClearAll)
                  TextButton(
                    onPressed: onClearAll,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.oxblood,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    child: Text(clearAllLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Joined single-choice buttons — the universal "exactly one of these" shape.
class _SegSort extends StatelessWidget {
  const _SegSort({required this.sort, required this.labels, required this.onSort});

  final String sort;
  final Map<String, String> labels;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        // Uniform border on purpose (CLAUDE.md, 21 Jul 2026).
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, entry) in labels.entries.indexed)
            InkWell(
              onTap: () => onSort(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.key == sort ? AppColors.oxblood : null,
                  border: i == 0
                      ? null
                      : Border(left: BorderSide(color: AppColors.line)),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: entry.key == sort ? AppColors.paper : AppColors.inkSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A facet's door: its noun, and its value when active ("Genre · History").
class _Door extends StatelessWidget {
  const _Door({required this.spec});

  final _DoorSpec spec;

  @override
  Widget build(BuildContext context) {
    final live = spec.value != null;
    return Material(
      color: live ? AppColors.oxblood : AppColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: spec.open,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: live ? AppColors.oxblood : AppColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                live ? '${spec.label} · ${spec.value}' : spec.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: live ? AppColors.paper : AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more,
                size: 14,
                color: live ? AppColors.paper : AppColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One facet's small sheet — the web door's popover: rows with the name left
/// and the count right, the current pick filled oxblood, the clearing row
/// first. Pops a 1-field record so "picked All" (value null) and "dismissed"
/// (record null) stay distinguishable.
class _FacetDoorSheet extends StatelessWidget {
  const _FacetDoorSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<_DoorOption> options;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
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
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    _DoorRow(
                      option: option,
                      selected: option.value == selected,
                      onTap: () => Navigator.of(context).pop((option.value,)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoorRow extends StatelessWidget {
  const _DoorRow({required this.option, required this.selected, required this.onTap});

  final _DoorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.oxblood : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.paper : AppColors.ink,
                  ),
                ),
              ),
              if (option.count != null)
                Text(
                  '${option.count}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: selected ? AppColors.paper.withValues(alpha: .8) : AppColors.inkSoft,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
