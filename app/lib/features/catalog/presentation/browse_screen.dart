import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/api/api_client.dart';
import '../../../l10n/app_localizations.dart';
import 'catalog_entity_tiles.dart';
import 'catalog_result_tile.dart';

/// Discover (S4/browse) — a place to wander the whole catalog: every book,
/// author, and publisher, alphabetical and lazily paged. Distinct from search
/// (which needs a query) — this is the "just show me everything" surface.
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final api = ref.read(apiClientProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColors.ink),
                      onPressed: () => context.pop(),
                    ),
                    Text(l10n.browseTitle, style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.search, color: AppColors.oxblood),
                      tooltip: l10n.searchTitle,
                      onPressed: () => context.push(Routes.catalogSearch),
                    ),
                  ],
                ),
              ),
              TabBar(
                labelColor: AppColors.oxblood,
                unselectedLabelColor: AppColors.inkSoft,
                indicatorColor: AppColors.oxblood,
                tabs: [
                  Tab(text: l10n.browseTabBooks),
                  Tab(text: l10n.browseTabAuthors),
                  Tab(text: l10n.browseTabPublishers),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _BooksBrowseTab(api: api),
                    _PaginatedList(
                      fetch: (limit, offset) => api.browseAuthors(limit: limit, offset: offset),
                      emptyText: l10n.browseEmpty,
                      itemBuilder: (author) => AuthorRowTile(
                        author: author,
                        onTap: () =>
                            context.push(Routes.authorBrowsePath(author['id'] as String)),
                      ),
                    ),
                    _PaginatedList(
                      fetch: (limit, offset) => api.browsePublishers(limit: limit, offset: offset),
                      emptyText: l10n.browseEmpty,
                      itemBuilder: (publisher) => PublisherRowTile(
                        publisher: publisher,
                        onTap: () =>
                            context.push(Routes.publisherBrowsePath(publisher['id'] as String)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Books tab — a sort control (title / newest / oldest / author) plus
/// language, Type and genre filters above the paged list. Changing any of them
/// re-keys the list so it reloads cleanly from the first page with the new
/// query. Every facet is applied server-side: the list is paged, so filtering
/// the page already fetched would silently hide matches further in.
class _BooksBrowseTab extends StatefulWidget {
  const _BooksBrowseTab({required this.api});

  final ApiClient api;

  @override
  State<_BooksBrowseTab> createState() => _BooksBrowseTabState();
}

class _BooksBrowseTabState extends State<_BooksBrowseTab> {
  String _sort = 'title';
  String? _language;
  String? _form;
  String? _genre;
  List<String> _languages = [];
  List<String> _forms = [];
  List<String> _genres = [];

  @override
  void initState() {
    super.initState();
    // Each facet list is best-effort: a failed fetch just leaves that filter
    // showing "all", never blocks browsing.
    widget.api.browseLanguages().then((langs) {
      if (mounted) setState(() => _languages = langs);
    }).catchError((_) {});
    widget.api.browseForms().then((forms) {
      if (mounted) setState(() => _forms = forms);
    }).catchError((_) {});
    widget.api.browseGenres().then((genres) {
      if (mounted) setState(() => _genres = genres);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sorts = {
      'title': l10n.browseSortTitle,
      'year_desc': l10n.browseSortNewest,
      'year_asc': l10n.browseSortOldest,
      'author': l10n.browseSortAuthor,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _FilterChipDropdown<String>(
                      icon: Icons.sort,
                      value: _sort,
                      label: sorts[_sort]!,
                      items: [
                        for (final e in sorts.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => setState(() => _sort = v ?? 'title'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChipDropdown<String?>(
                      icon: Icons.translate,
                      value: _language,
                      label: _language ?? l10n.browseFilterAllLanguages,
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.browseFilterAllLanguages)),
                        for (final lang in _languages)
                          DropdownMenuItem(value: lang, child: Text(lang)),
                      ],
                      onChanged: (v) => setState(() => _language = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Type and genre — the two axes the add form makes primary, so
              // Discover can be read the same way the shelf is filtered.
              Row(
                children: [
                  Expanded(
                    child: _FilterChipDropdown<String?>(
                      icon: Icons.menu_book_outlined,
                      value: _form,
                      label: _form ?? l10n.browseFilterAllTypes,
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.browseFilterAllTypes)),
                        for (final form in _forms)
                          DropdownMenuItem(value: form, child: Text(form)),
                      ],
                      onChanged: (v) => setState(() => _form = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FilterChipDropdown<String?>(
                      icon: Icons.local_offer_outlined,
                      value: _genre,
                      label: _genre ?? l10n.browseFilterAllGenres,
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.browseFilterAllGenres)),
                        for (final genre in _genres)
                          DropdownMenuItem(value: genre, child: Text(genre)),
                      ],
                      onChanged: (v) => setState(() => _genre = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _PaginatedList(
            // Re-key on filter/sort so pagination resets to page 1.
            key: ValueKey('$_sort|$_language|$_form|$_genre'),
            fetch: (limit, offset) => widget.api.browseWorks(
              limit: limit,
              offset: offset,
              sort: _sort,
              language: _language,
              form: _form,
              genre: _genre,
            ),
            emptyText: AppLocalizations.of(context)!.browseEmpty,
            itemBuilder: (work) => CatalogResultTile(work: work),
          ),
        ),
      ],
    );
  }
}

/// A compact pill that opens a dropdown — used for the browse sort/language
/// controls. Styled to match the Reading Room chips rather than a bare
/// Material dropdown.
class _FilterChipDropdown<T> extends StatelessWidget {
  const _FilterChipDropdown({
    required this.icon,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.inkSoft),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                icon: Icon(Icons.arrow_drop_down, color: AppColors.inkSoft),
                selectedItemBuilder: (context) => [
                  for (final _ in items)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                ],
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An offset-paged, infinite-scroll list: loads the first page on mount and
/// the next page as the user nears the bottom, until a short page signals the
/// end. Kept alive across tab switches so scroll position and loaded pages
/// survive.
class _PaginatedList extends StatefulWidget {
  const _PaginatedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyText,
  });

  final Future<List<Map<String, dynamic>>> Function(int limit, int offset) fetch;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  final String emptyText;

  @override
  State<_PaginatedList> createState() => _PaginatedListState();
}

class _PaginatedListState extends State<_PaginatedList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 40;
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _end = false;
  bool _errored = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
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

  Future<void> _retry() async {
    setState(() => _errored = false);
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty) {
      if (_loading) return ListSkeleton();
      if (_errored) return ErrorRetry(onRetry: _retry);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.emptyText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i == _items.length) {
          // Trailing row: a spinner while loading more, a retry on error,
          // otherwise nothing (end reached).
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (_errored) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: TextButton(
                  onPressed: _retry,
                  child: Text(AppLocalizations.of(context)!.commonRetry),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        return widget.itemBuilder(_items[i]);
      },
    );
  }
}
