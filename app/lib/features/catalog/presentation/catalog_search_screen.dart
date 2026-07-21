import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../providers/catalog_providers.dart';
import 'catalog_entity_tiles.dart';
import 'catalog_result_tile.dart';

/// S4 — global search. One screen searches four things: the personal library
/// (offline, from Drift) and the shared catalog's books, authors, and
/// publishers (one API call). Scan/Add buttons stay for the add-a-book flow.
class CatalogSearchScreen extends ConsumerStatefulWidget {
  const CatalogSearchScreen({super.key});

  @override
  ConsumerState<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends ConsumerState<CatalogSearchScreen> {
  final _controller = TextEditingController();

  /// Every keystroke — drives the on-device library section (instant).
  String _query = '';

  /// Debounced 300ms — drives the network catalog search, so fast typing
  /// costs one request per pause instead of one per keystroke.
  String _remoteQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _remoteQuery = value);
    });
  }

  /// Tapping a Recent chip re-runs it immediately — no debounce, since the
  /// query is already complete, and it bubbles back to the top of the list.
  void _runRecent(String query) {
    _debounce?.cancel();
    _controller.text = query;
    setState(() {
      _query = query;
      _remoteQuery = query;
    });
    ref.read(recentSearchesProvider.notifier).record(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.ink),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _controller.text.isEmpty ? AppColors.line : AppColors.ink,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              // Keyboard up on arrival — the screen is useless
                              // until there's a query, so don't make the user
                              // tap the field first.
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: l10n.catalogSearchHint,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: _onQueryChanged,
                              // A submitted query is one the reader committed
                              // to — that's what earns a place in Recent, not
                              // every debounced keystroke on the way there.
                              textInputAction: TextInputAction.search,
                              onSubmitted: (v) =>
                                  ref.read(recentSearchesProvider.notifier).record(v),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _debounce?.cancel();
                                setState(() {
                                  _controller.clear();
                                  _query = '';
                                  _remoteQuery = '';
                                });
                              },
                              child: Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(l10n.catalogScanButton),
                      onPressed: () => context.push(Routes.catalogScan),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.edit_note, size: 18),
                      label: Text(l10n.catalogAddManualButton),
                      onPressed: () => context.push(Routes.catalogAdd),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: _query.trim().isEmpty
                  ? _SearchIdle(onPickRecent: _runRecent)
                  : _SearchResults(query: _query, remoteQuery: _remoteQuery),
            ),
          ],
        ),
      ),
    );
  }
}

/// S4 — global search results: the personal library first (offline, Drift,
/// re-queried on every keystroke), then the shared catalog's books, authors,
/// and publishers — one fuzzy, typo-tolerant, ranked API call on the
/// debounced [remoteQuery]. A library hit opens the book you own; a catalog
/// book opens it to add; an author/publisher opens their browse page.
/// S4h — what the search page shows before you type. Three sections, all of
/// them real: the reader's own recent searches (local, offline), the newest
/// catalogue arrivals in their first profile language, and the authors who
/// have the most works here. There is deliberately no "Trending" — nothing in
/// the schema counts reads or views, so that row would be sorted by nothing
/// (docs/screen-design.md). Every section hides itself when empty, so a fresh
/// install with no languages set falls back to the original help text.
class _SearchIdle extends ConsumerWidget {
  const _SearchIdle({required this.onPickRecent});

  final void Function(String) onPickRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final recent = ref.watch(recentSearchesProvider);
    final languages =
        (ref.watch(meProvider).valueOrNull?['preferred_languages'] as List?)?.cast<String>() ??
            const <String>[];
    final language = languages.isNotEmpty ? languages.first : null;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: _IdleSectionLabel(l10n.searchRecentSection)),
              GestureDetector(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(
                  l10n.searchRecentClear,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final query in recent)
                ActionChip(
                  onPressed: () => onPickRecent(query),
                  avatar: Icon(Icons.history, size: 14, color: AppColors.inkSoft),
                  label: Text(query, style: TextStyle(fontSize: 12)),
                  backgroundColor: AppColors.card,
                  side: BorderSide(color: AppColors.line),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          SizedBox(height: 18),
        ],
        _NewInLanguage(language: language),
        _PopularAuthors(),
        // The original help line still earns its place — it explains the
        // author/publisher doors that the rows above are full of.
        SizedBox(height: 4),
        Text(
          l10n.catalogSearchHelp,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.4),
        ),
        SizedBox(height: 14),
        OutlinedButton.icon(
          icon: Icon(Icons.auto_stories_outlined, size: 18),
          label: Text(l10n.browseEntry),
          onPressed: () => context.push(Routes.catalogBrowse),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.oxblood,
            padding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _IdleSectionLabel extends StatelessWidget {
  const _IdleSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.inkSoft,
      ),
    );
  }
}

/// Newest catalogue arrivals in the reader's first profile language — the
/// regional angle, and the one row that makes an empty search page feel like
/// a bookshop rather than a form. With no language (none set, or `/me`
/// unreachable — an expired token makes that routine) it degrades to the
/// catalogue-wide newest instead of vanishing, so the page never loses a
/// section for a reason the reader can't see. Still renders nothing while
/// loading or if the catalogue is empty, so there's no stranded header.
class _NewInLanguage extends ConsumerWidget {
  const _NewInLanguage({required this.language});

  final String? language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final language = this.language;
    final works = ref.watch(newInLanguageProvider(language)).valueOrNull ?? const [];
    if (works.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdleSectionLabel(
          language == null ? l10n.searchNewInCatalogue : l10n.searchNewInLanguage(language),
        ),
        SizedBox(height: 8),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: works.length,
            separatorBuilder: (_, _) => SizedBox(width: 10),
            itemBuilder: (context, i) {
              final work = works[i];
              final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
              final author = authors.isNotEmpty ? authors.first['name'] as String? : null;
              final edition = work['edition'] as Map<String, dynamic>?;
              final editionId = edition?['id'] as String?;
              return SizedBox(
                width: 64,
                child: GestureDetector(
                  onTap: editionId == null
                      ? null
                      : () => context.push(
                            Routes.bookDetailPath(work['id'] as String, editionId),
                          ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TypesetCover(
                        title: work['title'] as String? ?? '',
                        author: author,
                        coverUrl: edition?['cover_url'] as String?,
                        width: 64,
                        height: 94,
                      ),
                      SizedBox(height: 4),
                      if (author != null)
                        Text(
                          author,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9, color: AppColors.inkSoft, height: 1.25),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 5),
        Text(
          // Only claim it's filtered to their languages when it actually is.
          language == null ? l10n.searchNewInCatalogueNote : l10n.searchNewInLanguageNote,
          style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
        ),
        SizedBox(height: 18),
      ],
    );
  }
}

/// Authors ranked by how many works they have in the catalogue — the only
/// popularity signal that exists today. Named "Most in the catalogue" rather
/// than "Popular" on purpose: it counts works, not readers, and the label
/// shouldn't imply otherwise.
class _PopularAuthors extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final authors = ref.watch(popularAuthorsProvider).valueOrNull ?? const [];
    if (authors.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IdleSectionLabel(l10n.searchPopularAuthors),
        SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final author in authors)
              ActionChip(
                onPressed: () =>
                    context.push(Routes.authorBrowsePath(author['id'] as String)),
                label: Text(author['name'] as String? ?? '', style: TextStyle(fontSize: 12)),
                backgroundColor: AppColors.goldSoft,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        SizedBox(height: 18),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.remoteQuery});

  final String query;
  final String remoteQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(librarySearchProvider(query));
    final catalog = ref.watch(globalSearchProvider(remoteQuery));
    final hits = library.valueOrNull ?? const <LibraryHit>[];
    final data = catalog.valueOrNull ?? const <String, dynamic>{};
    final works = (data['works'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authors = (data['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final publishers = (data['publishers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final readers = ref.watch(_readerSearchProvider(remoteQuery));

    if (library.isLoading && catalog.isLoading) {
      return ListSkeleton();
    }
    if (catalog.hasError && hits.isEmpty) {
      return ErrorRetry(onRetry: () => ref.invalidate(globalSearchProvider(remoteQuery)));
    }
    // "Nothing found" only when every section — including matching readers —
    // came back empty; a person can be the only hit for a name query.
    final catalogEmpty = works.isEmpty &&
        authors.isEmpty &&
        publishers.isEmpty &&
        (readers.valueOrNull?.isEmpty ?? true) &&
        !readers.isLoading;
    if (!library.isLoading && !catalog.isLoading && hits.isEmpty && catalogEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            l10n.catalogSearchEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (hits.isNotEmpty) ...[
          _SectionHeader(l10n.catalogSearchSectionLibrary(hits.length)),
          SizedBox(height: 8),
          for (final hit in hits) _LibraryHitTile(hit: hit),
          SizedBox(height: 16),
        ],
        if (catalog.isLoading)
          Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (works.isNotEmpty) ...[
          _SectionHeader(l10n.catalogSearchSectionCatalog),
          SizedBox(height: 8),
          for (final work in works) CatalogResultTile(work: work),
          SizedBox(height: 16),
        ],
        if (authors.isNotEmpty) ...[
          _SectionHeader(l10n.catalogSearchSectionAuthors),
          SizedBox(height: 8),
          for (final author in authors)
            AuthorRowTile(
              author: author,
              onTap: () => context.push(Routes.authorBrowsePath(author['id'] as String)),
            ),
          SizedBox(height: 16),
        ],
        if (publishers.isNotEmpty) ...[
          _SectionHeader(l10n.catalogSearchSectionPublishers),
          SizedBox(height: 8),
          for (final publisher in publishers)
            PublisherRowTile(
              publisher: publisher,
              onTap: () => context.push(Routes.publisherBrowsePath(publisher['id'] as String)),
            ),
          SizedBox(height: 16),
        ],
        // Kitabi readers matching the query — the connections/lending side of
        // global search; each opens their public profile.
        _ReadersSection(query: remoteQuery),
      ],
    );
  }
}

final _readerSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(apiClientProvider).searchUsers(query.trim());
});

class _ReadersSection extends ConsumerWidget {
  const _ReadersSection({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final readers = ref.watch(_readerSearchProvider(query)).valueOrNull ?? const [];
    if (readers.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(l10n.searchReadersHeader.toUpperCase()),
        SizedBox(height: 8),
        for (final r in readers)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: (r['avatar_url'] as String?) != null
                  ? netImageProvider(r['avatar_url'] as String)
                  : null,
              child: Text(
                ((r['full_name'] as String?)?.trim().isNotEmpty ?? false
                        ? (r['full_name'] as String).trim()[0]
                        : (r['username'] as String? ?? '?')[0])
                    .toUpperCase(),
                style: TextStyle(
                  color: Color(0xFF8F681E),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            title: Text(
              (r['full_name'] as String?)?.trim().isNotEmpty ?? false
                  ? (r['full_name'] as String).trim()
                  : '@${r['username']}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: r['username'] != null
                ? Text('@${r['username']}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft))
                : null,
            trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
            onTap: () => context.push(
              Routes.publicProfilePath(r['id'] as String),
              extra: (r['full_name'] as String?)?.trim().isNotEmpty ?? false
                  ? (r['full_name'] as String).trim()
                  : '@${r['username']}',
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: AppColors.inkSoft, letterSpacing: 1),
    );
  }
}

class _LibraryHitTile extends StatelessWidget {
  const _LibraryHitTile({required this.hit});

  final LibraryHit hit;

  @override
  Widget build(BuildContext context) {
    final book = hit.book;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            TypesetCover(
              title: book.title,
              author: book.authorNames,
              coverUrl: book.coverUrl,
              width: 30,
              height: 44,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    book.authorNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            StatusPill(status: hit.entry.status),
          ],
        ),
      ),
    );
  }
}
