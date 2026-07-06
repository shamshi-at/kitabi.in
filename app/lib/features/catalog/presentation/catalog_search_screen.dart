import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../providers/catalog_providers.dart';
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
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                              decoration: InputDecoration(
                                hintText: l10n.catalogSearchHint,
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() {
                                _controller.clear();
                                _query = '';
                              }),
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
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          l10n.catalogSearchHelp,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      ),
                    )
                  : _SearchResults(query: _query),
            ),
          ],
        ),
      ),
    );
  }
}

/// S4 — global search results: the personal library first (offline, Drift),
/// then the shared catalog's books, authors, and publishers (one API call). A
/// library hit opens the book you own; a catalog book opens it to add; an
/// author/publisher opens their browse page.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(librarySearchProvider(query));
    final catalog = ref.watch(globalSearchProvider(query));
    final hits = library.valueOrNull ?? const <LibraryHit>[];
    final data = catalog.valueOrNull ?? const <String, dynamic>{};
    final works = (data['works'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final authors = (data['authors'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final publishers = (data['publishers'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    if (library.isLoading && catalog.isLoading) {
      return ListSkeleton();
    }
    if (catalog.hasError && hits.isEmpty) {
      return ErrorRetry(onRetry: () => ref.invalidate(globalSearchProvider(query)));
    }
    final catalogEmpty = works.isEmpty && authors.isEmpty && publishers.isEmpty;
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
          for (final author in authors) _AuthorHitTile(author: author),
          SizedBox(height: 16),
        ],
        if (publishers.isNotEmpty) ...[
          _SectionHeader(l10n.catalogSearchSectionPublishers),
          SizedBox(height: 8),
          for (final publisher in publishers) _PublisherHitTile(publisher: publisher),
        ],
      ],
    );
  }
}

/// An author row in global search — portrait/monogram, name, primary language.
/// Tapping opens the author browse page (everything they've written).
class _AuthorHitTile extends StatelessWidget {
  const _AuthorHitTile({required this.author});

  final Map<String, dynamic> author;

  @override
  Widget build(BuildContext context) {
    final name = author['name'] as String? ?? '';
    final imageUrl = author['image_url'] as String?;
    final language = author['primary_language'] as String?;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.authorBrowsePath(author['id'] as String)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
              child: imageUrl == null
                  ? Text(
                      initials,
                      style: TextStyle(
                        color: Color(0xFF8F681E),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (language != null && language.isNotEmpty)
                    Text(
                      language,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// A publisher row in global search — logo/icon, name, language. Tapping opens
/// the publisher browse page.
class _PublisherHitTile extends StatelessWidget {
  const _PublisherHitTile({required this.publisher});

  final Map<String, dynamic> publisher;

  @override
  Widget build(BuildContext context) {
    final name = publisher['name'] as String? ?? '';
    final logoUrl = publisher['logo_url'] as String?;
    final language = publisher['primary_language'] as String?;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(Routes.publisherBrowsePath(publisher['id'] as String)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: logoUrl != null
                  ? Image.network(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(Icons.business, color: AppColors.inkSoft, size: 16),
                    )
                  : Icon(Icons.business, color: AppColors.inkSoft, size: 16),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (language != null && language.isNotEmpty)
                    Text(
                      language,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
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
