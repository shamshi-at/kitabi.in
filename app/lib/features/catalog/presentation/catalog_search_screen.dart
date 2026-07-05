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

/// S4 (catalog-only slice) — Phase 2 doesn't yet have a personal library to
/// merge in ("in your library" vs "in the catalog" per the mockup), so every
/// result here is a catalog work. The merge lands with Phase 3.
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

/// S4 — global search: the personal library first (offline, from Drift), then
/// the shared catalog (API). A library hit opens the book you own; a catalog
/// hit opens it to add.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(librarySearchProvider(query));
    final catalog = ref.watch(catalogSearchProvider(query));
    final hits = library.valueOrNull ?? const <LibraryHit>[];
    final works = catalog.valueOrNull ?? const <Map<String, dynamic>>[];

    if (library.isLoading && catalog.isLoading) {
      return ListSkeleton();
    }
    if (catalog.hasError && hits.isEmpty) {
      return ErrorRetry(onRetry: () => ref.invalidate(catalogSearchProvider(query)));
    }
    if (!library.isLoading && !catalog.isLoading && hits.isEmpty && works.isEmpty) {
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
        if (works.isNotEmpty || catalog.isLoading) ...[
          _SectionHeader(l10n.catalogSearchSectionCatalog),
          SizedBox(height: 8),
          if (catalog.isLoading)
            Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            )
          else
            for (final work in works) CatalogResultTile(work: work),
        ],
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
