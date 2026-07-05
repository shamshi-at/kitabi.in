import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';

/// S3 — the home dashboard. Currently reading (progress in pages), the lending
/// nudge as a gold-edged slip, and plain-number shelf cards. The AI pick card
/// (S3) is Phase 7 (recommendations), so it's deliberately not here yet.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(libraryEntriesProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('$err')),
          data: (all) => all.isEmpty
              ? _EmptyHome(l10n: l10n)
              : _Dashboard(entries: all, l10n: l10n),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline, color: AppColors.oxblood),
          onPressed: () => context.push(Routes.profile),
        ),
      ],
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.entries, required this.l10n});

  final List<LibraryEntry> entries;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lending = ref.watch(allLendingProvider).valueOrNull ?? const <LendingWithBook>[];
    final activeLent = lending
        .where((r) => r.record.direction != 'borrowed' && r.record.returnedDate == null)
        .toList()
      ..sort(_byDueDate);

    final reading = entries.where((e) => e.status == 'reading').toList();
    final counts = _ShelfCounts(
      owned: entries.length,
      read: entries.where((e) => e.status == 'read').length,
      lentOut: activeLent.length,
      wishlist: entries.where((e) => e.status == 'wishlist').length,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _Header(l10n: l10n),
        const SizedBox(height: 16),
        if (reading.isNotEmpty) ...[
          _SectionLabel(l10n.homeCurrentlyReading),
          for (final entry in reading) _CurrentlyReadingCard(entry: entry),
          const SizedBox(height: 8),
        ],
        if (activeLent.isNotEmpty) _LendingNudge(item: activeLent.first, l10n: l10n),
        const SizedBox(height: 14),
        _SectionLabel(l10n.homeYourShelves),
        _ShelfGrid(counts: counts, l10n: l10n),
        const SizedBox(height: 14),
        _RecsEntryCard(l10n: l10n),
      ],
    );
  }

  static int _byDueDate(LendingWithBook a, LendingWithBook b) {
    final da = a.record.dueDate;
    final db = b.record.dueDate;
    if (da == null && db == null) return 0;
    if (da == null) return 1; // no due date sorts last
    if (db == null) return -1;
    return da.compareTo(db);
  }
}

class _ShelfCounts {
  const _ShelfCounts({
    required this.owned,
    required this.read,
    required this.lentOut,
    required this.wishlist,
  });

  final int owned;
  final int read;
  final int lentOut;
  final int wishlist;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _CurrentlyReadingCard extends ConsumerWidget {
  const _CurrentlyReadingCard({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final book = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull;
    final page = entry.currentPage;
    final total = book?.pageCount;
    final percent =
        (page != null && total != null && total > 0) ? ((page / total) * 100).round() : null;

    return GestureDetector(
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            TypesetCover(
              title: book?.title ?? '…',
              author: book?.authorNames,
              coverUrl: book?.coverUrl,
              width: 38,
              height: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book?.title ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (book?.authorNames != null)
                    Text(
                      book!.authorNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                  if (page != null && total != null && percent != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.homeProgressLine(page, total, percent),
                      style: const TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.oxblood),
          ],
        ),
      ),
    );
  }
}

class _LendingNudge extends StatelessWidget {
  const _LendingNudge({required this.item, required this.l10n});

  final LendingWithBook item;
  final AppLocalizations l10n;

  String _message() {
    final title = item.book?.title ?? '…';
    final name = item.record.borrowerName;
    final due = item.record.dueDate;
    if (due == null) return l10n.homeNudgeNoDue(title, name);
    final days = DateUtils.dateOnly(due).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    if (days < 0) return l10n.homeNudgeOverdue(title, name);
    return l10n.homeNudgeDue(title, name, days);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.lendingLedger),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border(
            top: BorderSide(color: AppColors.line),
            right: BorderSide(color: AppColors.line),
            bottom: BorderSide(color: AppColors.line),
            left: BorderSide(color: AppColors.gold, width: 3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_bottom, size: 16, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _message(),
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.oxblood),
          ],
        ),
      ),
    );
  }
}

class _ShelfGrid extends StatelessWidget {
  const _ShelfGrid({required this.counts, required this.l10n});

  final _ShelfCounts counts;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.9,
      children: [
        _ShelfCard(value: counts.owned, label: l10n.homeShelfOwned, color: AppColors.ink),
        _ShelfCard(value: counts.read, label: l10n.homeShelfRead, color: AppColors.moss),
        _ShelfCard(value: counts.lentOut, label: l10n.homeShelfLentOut, color: AppColors.oxblood),
        _ShelfCard(value: counts.wishlist, label: l10n.homeShelfWishlist, color: AppColors.slate),
      ],
    );
  }
}

/// The quiet AI-pick entry (S3) — a dark, clearly-labelled card, never a feed.
/// Opens the opt-in recommendations screen (S11).
class _RecsEntryCard extends StatelessWidget {
  const _RecsEntryCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.recommendations),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.recsHomePick,
                style: const TextStyle(color: Color(0xFFEFE3C8), fontSize: 12, height: 1.4),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                l10n.recsForYou,
                style: const TextStyle(
                  color: AppColors.night,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Text(
            '$value',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
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
