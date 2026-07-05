import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../../recommendations/providers/recommendations_providers.dart';

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
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.person_outline, color: AppColors.oxblood),
                tooltip: l10n.profileEntry,
                onPressed: () => context.push(Routes.profile),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.oxblood,
                onRefresh: () async => ref.invalidate(libraryEntriesProvider),
                child: entries.when(
                  loading: () => CoverGridSkeleton(),
                  error: (err, _) =>
                      ErrorRetry(onRetry: () => ref.invalidate(libraryEntriesProvider)),
                  data: (all) => all.isEmpty
                      ? _EmptyHome(l10n: l10n)
                      : _Dashboard(entries: all, l10n: l10n),
                ),
              ),
            ),
          ],
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
    return Column(
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
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        _Header(l10n: l10n),
        SizedBox(height: 16),
        if (reading.isNotEmpty) ...[
          _SectionLabel(l10n.homeCurrentlyReading),
          for (final entry in reading) _CurrentlyReadingCard(entry: entry),
          SizedBox(height: 8),
        ],
        if (activeLent.isNotEmpty) _LendingNudge(item: activeLent.first, l10n: l10n),
        SizedBox(height: 14),
        _SectionLabel(l10n.homeYourShelves),
        _ShelfGrid(counts: counts, l10n: l10n),
        SizedBox(height: 14),
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
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
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
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(10),
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
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book?.title ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (book?.authorNames != null)
                    Text(
                      book!.authorNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
                    ),
                  if (page != null && total != null && percent != null) ...[
                    SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (page / total).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: AppColors.line,
                        valueColor: AlwaysStoppedAnimation(AppColors.gold),
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      l10n.homeProgressLine(page, total, percent),
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: AppColors.oxblood, size: 22),
              tooltip: l10n.homeUpdateProgress,
              onPressed: () => _updateProgress(context, ref, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateProgress(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final controller = TextEditingController(text: entry.currentPage?.toString() ?? '');
    final newPage = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.homeUpdateProgress),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.bookCurrentPage),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (newPage == null) return;
    Haptics.selection();
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateProgress(
      entry.id,
      currentPage: newPage,
      startDate: entry.startDate == null ? DateTime.now() : null,
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
        padding: EdgeInsets.all(11),
        decoration: BoxDecoration(
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
            Icon(Icons.hourglass_bottom, size: 16, color: AppColors.gold),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                _message(),
                style: TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.oxblood),
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
      physics: NeverScrollableScrollPhysics(),
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
/// Only shown once the reader has opted into recommendations (discovered via
/// the profile), so a first-time user is never led to a dormant feature.
class _RecsEntryCard extends ConsumerWidget {
  const _RecsEntryCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(recsOptInProvider).valueOrNull != true) return SizedBox.shrink();
    return GestureDetector(
      onTap: () => context.push(Routes.recommendations),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: AppColors.gold),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.recsHomePick,
                style: TextStyle(color: Color(0xFFEFE3C8), fontSize: 12, height: 1.4),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                l10n.recsForYou,
                style: TextStyle(
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
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
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
        padding: EdgeInsets.all(28),
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
            SizedBox(height: 8),
            Text(
              l10n.homeGreeting,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.gold,
                    letterSpacing: 3,
                  ),
            ),
            SizedBox(height: 40),
            Icon(Icons.menu_book_outlined, size: 48, color: AppColors.inkSoft),
            SizedBox(height: 16),
            Text(
              l10n.homeEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
            ),
            SizedBox(height: 6),
            Text(
              l10n.homeEmptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 240,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push(Routes.catalogSearch),
                      icon: Icon(Icons.add),
                      label: Text(l10n.homeAddBook),
                    ),
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(Routes.catalogScan),
                      icon: Icon(Icons.qr_code_scanner, size: 18),
                      label: Text(l10n.homeScanBarcode),
                    ),
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
