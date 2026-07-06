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
                    _PaginatedList(
                      fetch: (limit, offset) => api.browseWorks(limit: limit, offset: offset),
                      emptyText: l10n.browseEmpty,
                      itemBuilder: (work) => CatalogResultTile(work: work),
                    ),
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

/// An offset-paged, infinite-scroll list: loads the first page on mount and
/// the next page as the user nears the bottom, until a short page signals the
/// end. Kept alive across tab switches so scroll position and loaded pages
/// survive.
class _PaginatedList extends StatefulWidget {
  const _PaginatedList({
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
