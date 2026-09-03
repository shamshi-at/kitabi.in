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
import '../../../core/widgets/pulsing_dot.dart';
import '../../../core/widgets/quote_card.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../insights/providers/insights_providers.dart';
import '../../library/mark_finished.dart';
import '../../library/presentation/finished_review_prompt.dart';
import '../../library/providers/library_providers.dart';
import '../../library/providers/reading_timer_providers.dart';
import '../../library/reading_progress.dart';
import '../../library/stop_session_flow.dart';
import '../../profile/presentation/profile_screen.dart' show showUsernameSheet;
import '../../profile/providers/profile_providers.dart';
import '../../promotions/providers/promotions_providers.dart';
import '../../promotions/widgets/promo_surfaces.dart';
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
                    // local_library, not auto_stories — the open-book glyph
                    // already means "your shelf" on the empty state.
                    icon: Icon(Icons.local_library_outlined, color: AppColors.oxblood),
                    tooltip: l10n.browseEntry,
                    onPressed: () => context.push(Routes.catalogBrowse),
                  ),
                  // A blinking dot rides the profile icon until the reader has
                  // picked a username — a quiet nudge toward finishing setup.
                  Builder(
                    builder: (context) {
                      final me = ref.watch(meProvider).valueOrNull;
                      final username = me?['username'] as String?;
                      final needsUsername = me != null && (username == null || username.isEmpty);
                      final button = IconButton(
                        icon: Icon(Icons.person_outline, color: AppColors.oxblood),
                        tooltip: l10n.profileEntry,
                        onPressed: () => context.push(Routes.profile),
                      );
                      if (!needsUsername) return button;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          button,
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IgnorePointer(child: PulsingDot()),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.oxblood,
                onRefresh: () => ref.refresh(libraryEntriesProvider.future),
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
    // A wishlisted book is a book you *don't have* — "Wishlist is a shelf, not
    // a reading stage" (design note U4). It must never be counted as owned or
    // stood up on the shelf strip: a reader who wishlisted one book and owns
    // one read "2 OWNED" and saw a book they don't have under "Fresh on your
    // shelf" (owner report, 31 Jul 2026). Wishlist has its own stat, one
    // column over — a book in both places is a book counted twice.
    final shelved = entries.where((e) => e.status != 'wishlist').toList();
    final counts = _ShelfCounts(
      owned: shelved.length,
      read: entries.where((e) => e.status == 'read').length,
      lentOut: activeLent.length,
      wishlist: entries.where((e) => e.status == 'wishlist').length,
    );

    // Newest additions first — the shelf strip shows the library growing.
    final recent = [...shelved]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Promotions (docs/promotions-plan.md). Null unless something is live and
    // this reader matches it — with nothing published, not a single widget of
    // this feature is built and Home is exactly the page it was before.
    final banner = ref.watch(homeBannerProvider);
    final card = ref.watch(homeCardProvider);

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 24),
      children: [
        if (banner != null) PromoBanner(promo: banner),
        if (reading.isNotEmpty) ...[
          SectionLabel(l10n.homeCurrentlyReading),
          for (final entry in reading) _CurrentlyReadingCard(entry: entry),
          SizedBox(height: 8),
        ],
        if (activeLent.isNotEmpty) _LendingNudge(item: activeLent.first, l10n: l10n),
        SizedBox(height: 14),
        // Hidden rather than shown empty: now that wishlisted books are filtered
        // out, a reader whose only entries are wishlist would otherwise get a
        // section heading over a 96px hole.
        if (recent.isNotEmpty) ...[
          SectionLabel(l10n.homeFreshShelf),
          _CoverShelf(entries: recent.take(12).toList()),
          SizedBox(height: 16),
        ],
        _GoalSlip(entries: entries, l10n: l10n),
        // Sits with the goal slip because it is the same kind of thing: a
        // one-off invitation to set something up, below what Home is actually
        // for. It removes itself the moment a username exists.
        const _ClaimUsernameCard(),
        SizedBox(height: 14),
        SectionLabel(l10n.homeYourShelves),
        _ShelfGrid(counts: counts, l10n: l10n),
        SizedBox(height: 14),
        _RecsEntryCard(l10n: l10n),
        // Last before the quote, deliberately: Home opens on what you're
        // reading, not on a pitch. A reader who never scrolls never sees it —
        // and never has an impression counted against them.
        if (card != null) ...[
          SizedBox(height: 14),
          PromoCard(promo: card),
        ],
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

/// The nudge to claim a username, shown on Home only while there isn't one.
///
/// A username is the one piece of setup nothing else in the app forces: you
/// can shelve, read and lend for months without it, and then a friend can't
/// find you. Profile has always offered it, but a reader with no reason to
/// open Profile never saw the offer.
///
/// Deliberately quiet and deliberately *not* dismissible: it disappears the
/// moment it is acted on, which is the only ending it needs. Nothing renders
/// while `/me` is still loading or has failed — an invitation that flashes up
/// on every cold start, or on a phone with no signal, reads as a bug.
///
/// Lives on the dashboard, so a reader with an empty library sees `_EmptyHome`
/// and never meets it. That is on purpose: their first task is a first book,
/// not a handle — and the pulsing dot on the profile icon above still carries
/// the hint until they have one.
class _ClaimUsernameCard extends ConsumerWidget {
  const _ClaimUsernameCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final me = ref.watch(meProvider);
    // `.valueOrNull` alone is null both for "no username" and for "we haven't
    // asked yet" — the same conflation that used to flash the language picker
    // at signed-in readers (CLAUDE.md, 15 Jul 2026). Only an answer that
    // actually arrived gets to put this on screen.
    if (!me.hasValue) return const SizedBox.shrink();
    final username = me.value?['username'] as String?;
    if (username != null && username.isNotEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GestureDetector(
        onTap: () async {
          Haptics.selection();
          if (await showUsernameSheet(context) && context.mounted) {
            ref.invalidate(meProvider);
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const PulsingDot(size: 7),
                  const SizedBox(width: 7),
                  Expanded(
                    child: SectionLabel(l10n.homeUsernameLabel, padding: EdgeInsets.zero),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.inkSoft),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '@',
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gold,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Same shape as the goal slip above, same reason.
                  Flexible(
                    child: Text(
                      l10n.homeUsernameTitle,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                l10n.homeUsernameWhy,
                style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
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
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? 30;
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
                  child: SectionLabel(l10n.homeGoalLabel, padding: EdgeInsets.zero),
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
                  // Flexible, not a bare Text: the numeral beside it is set at
                  // 40px and grows with the reader's font scale, so on a 320dp
                  // phone at 1.5x this label is sized to its natural width and
                  // the Row has nothing to give — it striped over the goal slip
                  // (verified on-emulator, 2 Sep 2026). Let it wrap instead.
                  Flexible(
                    child: Text(
                      l10n.homeGoalOf(goal),
                      style: TextStyle(fontSize: 13, color: AppColors.inkSoft, fontWeight: FontWeight.w500),
                    ),
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

// Home used to keep its own private goal provider over the same key Insights
// edits. Insights invalidated *its* provider on save, so Home kept serving a
// stale cached value and still offered "Set a goal for 2026" after one was set
// (owner report, 21 Jul 2026). One provider, one source of truth.

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
      // Light card with the oxblood bar, per mockup 3 — the dark-slab look
      // put three constant-dark panels on one page (the constitution allows
      // one, and the quote card owns it).
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
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
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        SizedBox(width: 6),
                        PulsingDot(size: 6),
                      ],
                    ],
                  ),
                  if (book?.authorNames != null)
                    Text(
                      book!.authorNames,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 11),
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
                          backgroundColor: AppColors.paperDeep,
                          valueColor: AlwaysStoppedAnimation(AppColors.oxblood),
                        ),
                      ),
                    if (total != null && percent != null) SizedBox(height: 3),
                    Text(
                      total != null && percent != null
                          ? l10n.homeProgressLine(page, total, percent)
                          : l10n.homeProgressLineNoTotal(page),
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
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
                    color: AppColors.oxblood,
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
                  // A pencil, not a "+" — the nav's "+" means add-a-book, and
                  // two nearby plus glyphs meant two different things.
                  icon: Icon(Icons.edit, color: AppColors.oxblood, size: 20),
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
        db: ref.read(appDatabaseProvider),
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

  /// Mirrors the book page's pencil editor: "of N pages" context when the
  /// total is known, an optional total field (routed through the shared
  /// [saveBookTotalPages]) when it isn't, replace-on-tap, and range checks —
  /// this dialog used to accept "-3" and "9999" without blinking.
  Future<void> _updateProgress(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final knownTotal = ref.read(cachedBookProvider(entry.editionId)).valueOrNull?.pageCount;
    final controller = TextEditingController(text: entry.currentPage?.toString() ?? '');
    // Pre-selected, so the autofocused field is overwritten by the first digit.
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final totalController = TextEditingController();
    String? errorText;
    final result = await showDialog<(int, int?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.homeUpdateProgress),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                onTap: () => controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                ),
                decoration: InputDecoration(
                  labelText: l10n.bookCurrentPage,
                  helperText: knownTotal != null ? l10n.homeProgressOfTotal(knownTotal) : null,
                  errorText: errorText,
                ),
              ),
              if (knownTotal == null)
                TextField(
                  controller: totalController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.timerTotalFieldLabel),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
            TextButton(
              onPressed: () {
                final page = int.tryParse(controller.text.trim());
                final total = knownTotal ?? int.tryParse(totalController.text.trim());
                if (page == null || page < 0) {
                  setDialogState(() => errorText = l10n.homeProgressInvalid);
                  return;
                }
                if (total != null && page > total) {
                  setDialogState(() => errorText = l10n.homeProgressTooFar(total));
                  return;
                }
                Navigator.pop(ctx, (page, int.tryParse(totalController.text.trim())));
              },
              child: Text(l10n.bookSave),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final (newPage, typedTotal) = result;
    Haptics.selection();
    // The total belongs to the shared Edition — mirror it locally + sync it.
    if (knownTotal == null && typedTotal != null) {
      await saveBookTotalPages(
        ref.read(appDatabaseProvider),
        ref.read(apiClientProvider),
        entry.editionId,
        typedTotal,
      );
    }
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateProgress(
      entry.id,
      currentPage: newPage,
      startDate: entry.startDate == null ? DateTime.now() : null,
    );
    final finished = await autoFinishIfOnLastPage(
      db: ref.read(appDatabaseProvider),
      repo: repo,
      libraryEntryId: entry.id,
    );
    // Typing the last page finishes the book, here as everywhere else — so it
    // gets the same nudge to say something about it.
    if (finished && context.mounted) {
      await maybePromptForReview(
        context,
        ProviderScope.containerOf(context, listen: false),
        libraryEntryId: entry.id,
      );
    }
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
                      Text(
                        l10n.homeNudgeView,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.oxblood,
                        ),
                      ),
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
          color: AppColors.darkPanel,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: AppColors.gold),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.recsHomePick,
                style: TextStyle(color: AppColors.onDark, fontSize: 12, height: 1.4),
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
                  color: AppColors.darkPanel,
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
                  fontSize: 9,
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
