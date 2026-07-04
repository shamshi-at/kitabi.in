import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
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
    final results = ref.watch(catalogSearchProvider(_query));

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _controller.text.isEmpty ? AppColors.line : AppColors.ink,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                          const SizedBox(width: 8),
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
                              child: const Icon(Icons.close, size: 16, color: AppColors.inkSoft),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(l10n.catalogScanButton),
                      onPressed: () => context.push(Routes.catalogScan),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text(l10n.catalogAddManualButton),
                      onPressed: () => context.push(Routes.catalogAdd),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _query.trim().isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
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
                  : results.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('$err')),
                      data: (works) => works.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  l10n.catalogSearchEmpty,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: AppColors.inkSoft),
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              children: [
                                Text(
                                  l10n.catalogSearchSectionCatalog,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppColors.inkSoft,
                                        letterSpacing: 1,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                for (final work in works) CatalogResultTile(work: work),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
