import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../recommendations/providers/recommendations_providers.dart';

/// S3 — the home dashboard, the reader's first impression. A personal
/// time-of-day greeting under the wordmark, the book(s) in progress, a
/// "fresh on your shelf" strip of real covers standing on a gold shelf line,
/// the lending nudge, a goal slip that ties into Insights, and the shelf
/// counts. Everything reads from Drift — the whole page works offline.
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
            // Title and actions share one row — removes the dead space that
            // used to sit between an icons-only row and the heading below.
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _Header(l10n: l10n)),
                  // Global search — the bottom nav no longer carries it (it broke
                  // the FAB's exact-center docking), so it lives here instead.
                  IconButton(
                    icon: Icon(Icons.search, color: AppColors.oxblood),
                    tooltip: l10n.searchTitle,
                    onPressed: () => context.push(Routes.catalogSearch),
                  ),
                  IconButton(
                    icon: Icon(Icons.auto_stories_outlined, color: AppColors.oxblood),
                    tooltip: l10n.browseEntry,
                    onPressed: () => context.push(Routes.catalogBrowse),
                  ),
                  IconButton(
                    icon: Icon(Icons.person_outline, color: AppColors.oxblood),
                    tooltip: l10n.profileEntry,
                    onPressed: () => context.push(Routes.profile),
                  ),
                ],
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

/// The wordmark plus a *personal* line: time-of-day greeting with the
/// reader's first name (from /me, already fetched at bootstrap) and today's
/// date set like a diary heading — the page should feel like their reading
/// room, not an app shell.
class _Header extends ConsumerWidget {
  const _Header({required this.l10n});

  final AppLocalizations l10n;

  String _greeting(WidgetRef ref) {
    final fullName = ref.watch(meProvider).valueOrNull?['full_name'] as String?;
    final first = fullName?.trim().split(RegExp(r'\s+')).first;
    final hour = DateTime.now().hour;
    if (first != null && first.isNotEmpty) {
      if (hour < 12) return l10n.homeGreetingMorning(first);
      if (hour < 17) return l10n.homeGreetingAfternoon(first);
      return l10n.homeGreetingEvening(first);
    }
    if (hour < 12) return l10n.homeGreetingMorningAnon;
    if (hour < 17) return l10n.homeGreetingAfternoonAnon;
    return l10n.homeGreetingEveningAnon;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('EEEE · d MMMM').format(DateTime.now());
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
          _greeting(ref),
          style: GoogleFonts.fraunces(
            fontStyle: FontStyle.italic,
            fontSize: 13,
            color: AppColors.ink,
          ),
        ),
        Text(
          date,
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: AppColors.gold,
            fontWeight: FontWeight.w600,
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

    // Newest additions first — the shelf strip shows the library growing.
    final recent = [...entries]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 24),
      children: [
        if (reading.isNotEmpty) ...[
          _SectionLabel(l10n.homeCurrentlyReading),
          for (final entry in reading) _CurrentlyReadingCard(entry: entry),
          SizedBox(height: 8),
        ],
        if (activeLent.isNotEmpty) _LendingNudge(item: activeLent.first, l10n: l10n),
        SizedBox(height: 14),
        _SectionLabel(l10n.homeFreshShelf),
        _CoverShelf(entries: recent.take(12).toList()),
        SizedBox(height: 16),
        _GoalSlip(entries: entries, l10n: l10n),
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

/// The signature bookish moment on Home: the newest additions standing as
/// real covers on a shelf — a gold hairline with a soft shadow underneath,
/// like the mockups' "real bookshelf" feel. Horizontally scrollable; each
/// cover is a door to its book page.
class _CoverShelf extends ConsumerWidget {
  const _CoverShelf({required this.entries});

  final List<LibraryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, _) => SizedBox(width: 10),
            itemBuilder: (context, i) => _ShelfCover(entry: entries[i]),
          ),
        ),
        // The shelf itself: a gold edge and the shadow the books cast on it.
        Container(height: 2.5, color: AppColors.gold.withValues(alpha: 0.65)),
        Container(
          height: 7,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.ink.withValues(alpha: 0.10),
                AppColors.ink.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShelfCover extends ConsumerWidget {
  const _ShelfCover({required this.entry});

  final LibraryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull;
    return GestureDetector(
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: TypesetCover(
        title: book?.title ?? '…',
        author: book?.authorNames,
        coverUrl: book?.coverUrl,
        width: 60,
        height: 90,
      ),
    );
  }
}

/// A slim slip tying Home to Insights: this year's finished count against the
/// reading goal, with a hairline progress bar. With nothing finished yet it
/// invites setting a goal instead of showing an empty zero.
class _GoalSlip extends ConsumerWidget {
  const _GoalSlip({required this.entries, required this.l10n});

  final List<LibraryEntry> entries;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final goal = ref.watch(_homeGoalProvider).valueOrNull ?? 30;
    final read = entries
        .where((e) =>
            e.status == 'read' && e.finishDate != null && e.finishDate!.year == year)
        .length;
    final progress = goal > 0 ? (read / goal).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        context.go(Routes.insights);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, size: 16, color: AppColors.moss),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.homeGoalLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    read > 0 ? l10n.homeGoalProgress(read, goal) : l10n.homeGoalStart(year),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (read > 0) ...[
                    SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: AppColors.line,
                        valueColor: AlwaysStoppedAnimation(AppColors.moss),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// The device-local reading goal (same key Insights edits).
final _homeGoalProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.readingGoal();
});

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
                    style: GoogleFonts.fraunces(fontWeight: FontWeight.w600, fontSize: 14.5),
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
      // A borderRadius is only allowed with uniform border colors, so the
      // gold "lending" accent is an inner stripe, not a left BorderSide.
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: AppColors.line),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: AppColors.gold),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(11),
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
              ),
            ],
          ),
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
        _ShelfCard(
          value: counts.owned,
          label: l10n.homeShelfOwned,
          color: AppColors.ink,
          onTap: () => context.go(Routes.library),
        ),
        _ShelfCard(
          value: counts.read,
          label: l10n.homeShelfRead,
          color: AppColors.moss,
          onTap: () => context.go('${Routes.library}?status=read'),
        ),
        _ShelfCard(
          value: counts.lentOut,
          label: l10n.homeShelfLentOut,
          color: AppColors.oxblood,
          onTap: () => context.go(Routes.lendingLedger),
        ),
        _ShelfCard(
          value: counts.wishlist,
          label: l10n.homeShelfWishlist,
          color: AppColors.slate,
          onTap: () => context.go('${Routes.library}?status=wishlist'),
        ),
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
  const _ShelfCard({
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final int value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
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
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first-run face of the app: the wordmark, what Kitabi *is* in three
/// bookish steps (Scan · Shelve · Lend), and the two ways in. This is the
/// very first screen a new reader judges — it should promise the product,
/// not apologise for an empty list.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(28, 24, 28, 32),
      children: [
        SizedBox(height: 12),
        Center(
          child: Text(
            l10n.homeEmptyTitle,
            style: GoogleFonts.fraunces(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
        SizedBox(height: 6),
        Center(
          child: Text(
            l10n.homeEmptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ),
        SizedBox(height: 24),
        _StepCard(
          number: '1',
          icon: Icons.qr_code_scanner,
          title: l10n.homeStepScanTitle,
          body: l10n.homeStepScanBody,
        ),
        _StepCard(
          number: '2',
          icon: Icons.auto_stories_outlined,
          title: l10n.homeStepShelveTitle,
          body: l10n.homeStepShelveBody,
        ),
        _StepCard(
          number: '3',
          icon: Icons.swap_horiz,
          title: l10n.homeStepLendTitle,
          body: l10n.homeStepLendBody,
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(Routes.catalogScan),
            icon: Icon(Icons.qr_code_scanner, size: 18),
            label: Text(l10n.homeScanBarcode),
          ),
        ),
        SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push(Routes.catalogSearch),
            icon: Icon(Icons.add),
            label: Text(l10n.homeAddBook),
          ),
        ),
        SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: () => context.push(Routes.catalogBrowse),
            child: Text(
              l10n.homeBrowseCatalogue,
              style: TextStyle(color: AppColors.oxblood, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// One numbered step on the first-run home — a big drop-cap number in the
/// margin, like a chapter opening.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Text(
            number,
            style: GoogleFonts.fraunces(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
              height: 1,
            ),
          ),
          SizedBox(width: 14),
          Icon(icon, size: 20, color: AppColors.oxblood),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
