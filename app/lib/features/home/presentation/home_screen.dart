import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/haptics.dart';
import '../../../core/notifications/reading_timer_notifications.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/quote_card.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/providers/library_providers.dart';
import '../../library/providers/reading_timer_providers.dart';
import '../../library/stop_session_flow.dart';
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
        // Moved here from the profile screen (owner request, 16 Jul 2026) —
        // inspiration nobody scrolls to isn't inspiration. Last, as a closing
        // flourish: Home opens on what you're reading, not on a fortune.
        SizedBox(height: 14),
        const QuoteCard(),
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

/// The newest additions as a plain marquee of real covers — deliberately no
/// shelf-line/shadow underneath (that skeuomorphic "real bookshelf"
/// treatment read as costume, not design — owner feedback, 10 Jul 2026); the
/// covers carry it on their own. Each cover is a door to its book page.
class _CoverShelf extends ConsumerWidget {
  const _CoverShelf({required this.entries});

  final List<LibraryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => SizedBox(width: 10),
        itemBuilder: (context, i) => _ShelfCover(entry: entries[i]),
      ),
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

/// The hero number on Home: this year's finished count against the reading
/// goal, in oversized editorial type rather than a slim bordered slip — the
/// one number worth spending real emphasis on. With nothing finished yet it
/// invites setting a goal instead of showing a hero "0".
class _GoalSlip extends ConsumerWidget {
  const _GoalSlip({required this.entries, required this.l10n});

  final List<LibraryEntry> entries;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final goal = ref.watch(_homeGoalProvider).valueOrNull ?? 30;
    // A read book with no explicit finish date (only the book page's status
    // sheet sets one) falls back to when it was last touched, so it counts
    // toward the goal — same rule as Insights' computeInsights. Otherwise a
    // book you marked read never moved the ring (owner report, 17 Jul 2026).
    final read = entries.where((e) {
      if (e.status != 'read') return false;
      return (e.finishDate ?? e.updatedAt).year == year;
    }).length;
    final progress = goal > 0 ? (read / goal).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        Haptics.selection();
        context.go(Routes.insights);
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.goldSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeGoalLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
              ],
            ),
            SizedBox(height: 4),
            if (read > 0)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$read',
                    style: GoogleFonts.fraunces(
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      color: AppColors.oxblood,
                      height: 1,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    l10n.homeGoalOf(goal),
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft, fontWeight: FontWeight.w500),
                  ),
                ],
              )
            else
              Text(
                l10n.homeGoalStart(year),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            if (read > 0) ...[
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AppColors.card,
                  valueColor: AlwaysStoppedAnimation(AppColors.oxblood),
                ),
              ),
            ],
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
    final isLive = ref.watch(activeSessionProvider)?.libraryEntryId == entry.id;

    return GestureDetector(
      onTap: book == null
          ? null
          : () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.night,
          borderRadius: BorderRadius.circular(14),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book?.title ?? '…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold),
                        ),
                      ],
                    ],
                  ),
                  if (book?.authorNames != null)
                    Text(
                      book!.authorNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11),
                    ),
                  if (page != null) ...[
                    SizedBox(height: 5),
                    // A book with no known total (catalog data missing
                    // page_count) still shows the page the reader logged —
                    // it just skips the bar/percent, which need a total to
                    // mean anything. Previously the whole row was suppressed
                    // whenever total was null, so entering a page via the
                    // "+" button silently had no visible effect (owner
                    // report, 15 Jul 2026).
                    if (total != null && percent != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (page / total).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(AppColors.gold),
                        ),
                      ),
                    if (total != null && percent != null) SizedBox(height: 3),
                    Text(
                      total != null && percent != null
                          ? l10n.homeProgressLine(page, total, percent)
                          : l10n.homeProgressLineNoTotal(page),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // While this book's session is running the control IS a stop —
                // a play icon on a live timer just lies about what it does
                // (owner report, 16 Jul 2026). Stops and logs through the same
                // flow as the mini-bar, page prompt and all.
                IconButton(
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    isLive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                    color: AppColors.gold,
                    size: 22,
                  ),
                  tooltip: isLive ? l10n.timerStop : l10n.timerStart,
                  onPressed: isLive
                      ? () => quickStopSession(context, ref)
                      : () => _start(context, ref, l10n, book),
                ),
                IconButton(
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(Icons.add_circle_outline, color: AppColors.gold, size: 22),
                  tooltip: l10n.homeUpdateProgress,
                  onPressed: () => _updateProgress(context, ref, l10n),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Same start-a-session sequence as the book page's `_ReadingSessionCard._open`
  /// (owner request, 15 Jul 2026: a way to start reading straight from Home,
  /// no detour through the book page first). Starting a session already
  /// running for this entry is a harmless no-op in the notifier — it just
  /// re-opens the timer screen.
  void _start(BuildContext context, WidgetRef ref, AppLocalizations l10n, CachedBook? book) {
    Haptics.selection();
    final freshStart = ref.read(activeSessionProvider)?.libraryEntryId != entry.id;
    final startedAt = DateTime.now();
    ref.read(activeSessionProvider.notifier).start(entry.id, pageStart: entry.currentPage);
    if (freshStart) {
      armReadingTimerSafetyNet(
        libraryEntryId: entry.id,
        from: startedAt,
        title: l10n.timerCheckInTitle,
        body: l10n.timerCheckInBody,
        yesLabel: l10n.timerCheckInYes,
        noLabel: l10n.timerCheckInNo,
      );
    }
    context.push(
      Routes.readingTimerPath(entry.id),
      extra: {
        'title': book?.title,
        'author': book?.authorNames,
        'currentPage': entry.currentPage,
        'pageCount': book?.pageCount,
        'coverUrl': book?.coverUrl,
      },
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

/// Four stat columns in one typographic row instead of a bordered 2x2 grid —
/// the numbers themselves carry it (owner feedback, 10 Jul 2026: the old
/// boxed cards read as dashboard, not a page you'd want to look at).
class _ShelfGrid extends StatelessWidget {
  const _ShelfGrid({required this.counts, required this.l10n});

  final _ShelfCounts counts;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ShelfStat(
            value: counts.owned,
            label: l10n.homeShelfOwned,
            color: AppColors.ink,
            onTap: () => context.go(Routes.library),
          ),
        ),
        Expanded(
          child: _ShelfStat(
            value: counts.read,
            label: l10n.homeShelfRead,
            color: AppColors.moss,
            onTap: () => context.go('${Routes.library}?status=read'),
          ),
        ),
        Expanded(
          child: _ShelfStat(
            value: counts.lentOut,
            label: l10n.homeShelfLentOut,
            color: AppColors.oxblood,
            onTap: () => context.go(Routes.lendingLedger),
          ),
        ),
        Expanded(
          child: _ShelfStat(
            value: counts.wishlist,
            label: l10n.homeShelfWishlist,
            color: AppColors.slate,
            onTap: () => context.go('${Routes.library}?status=wishlist'),
          ),
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

/// One typographic column — big serif number, small-caps label underneath,
/// no border or fill. The number itself is the tap target's whole visual
/// weight, per the row it lives in ([_ShelfGrid]).
class _ShelfStat extends StatelessWidget {
  const _ShelfStat({
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: GoogleFonts.fraunces(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1,
                ),
              ),
              SizedBox(height: 3),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 7.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
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
