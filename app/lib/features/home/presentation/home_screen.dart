import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';

/// Interim home — a library-first landing so the app opens onto your books
/// (and anything just added shows up here immediately), not an empty screen.
/// The full dashboard (S3 — currently-reading nudges, shelf stats, one AI
/// pick) lands in Phase 6; this covers the "reading now" + "recently added"
/// slice using data that already exists.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(libraryEntriesProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined, color: AppColors.oxblood),
            onPressed: () => context.push(Routes.library),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: AppColors.oxblood),
            onPressed: () => context.push(Routes.lendingLedger),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.oxblood),
            onPressed: () => context.push(Routes.catalogSearch),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppColors.oxblood),
            onPressed: () => context.push(Routes.profile),
          ),
        ],
      ),
      floatingActionButton: entries.valueOrNull?.isEmpty ?? true
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.oxblood,
              foregroundColor: AppColors.paper,
              onPressed: () => context.push(Routes.catalogSearch),
              icon: const Icon(Icons.add),
              label: Text(l10n.homeAddBook),
            ),
      body: SafeArea(
        top: false,
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (all) => all.isEmpty
              ? _EmptyHome(l10n: l10n)
              : _HomeBody(entries: all, l10n: l10n),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.entries, required this.l10n});

  final List<LibraryEntry> entries;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final reading = entries.where((e) => e.status == 'reading').toList();
    final recent = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        Text(
          l10n.appTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.oxblood,
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          l10n.homeGreeting,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gold,
                letterSpacing: 2,
              ),
        ),
        const SizedBox(height: 20),
        if (reading.isNotEmpty) ...[
          _SectionHeader(title: l10n.homeCurrentlyReading),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reading.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _HomeCoverTile(entry: reading[i], showStatus: false),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            Expanded(child: _SectionHeader(title: l10n.homeYourLibrary)),
            GestureDetector(
              onTap: () => context.push(Routes.library),
              child: Text(
                l10n.homeSeeAll,
                style: const TextStyle(
                  color: AppColors.oxblood,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            childAspectRatio: 0.62,
          ),
          itemCount: recent.length > 9 ? 9 : recent.length,
          itemBuilder: (context, i) => _HomeCoverTile(entry: recent[i]),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _HomeCoverTile extends ConsumerWidget {
  const _HomeCoverTile({required this.entry, this.showStatus = true});

  final LibraryEntry entry;
  final bool showStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(cachedBookProvider(entry.editionId));
    final book = cached.valueOrNull;

    return GestureDetector(
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TypesetCover(
              title: book?.title ?? '…',
              author: book?.authorNames,
              coverUrl: book?.coverUrl,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          if (showStatus) ...[
            const SizedBox(height: 4),
            StatusPill(status: entry.status),
          ],
        ],
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.appTitle,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppColors.oxblood,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeGreeting,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 3,
                  ),
            ),
            const SizedBox(height: 40),
            const Icon(Icons.menu_book_outlined, size: 48, color: AppColors.inkSoft),
            const SizedBox(height: 16),
            Text(
              l10n.homeEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.homeEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push(Routes.catalogSearch),
              icon: const Icon(Icons.add),
              label: Text(l10n.homeAddBook),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.catalogScan),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: Text(l10n.homeScanBarcode),
            ),
          ],
        ),
      ),
    );
  }
}
