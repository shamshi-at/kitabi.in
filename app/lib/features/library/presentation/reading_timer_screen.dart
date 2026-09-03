import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/api/api_client.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import '../mark_finished.dart';
import '../providers/reading_timer_providers.dart';
import '../reading_progress.dart';
import 'finished_review_prompt.dart';
import 'note_page.dart';
import 'session_notes_block.dart';
import 'session_page_entry.dart';
import 'stop_session_sheet.dart';

/// The night face's companions to [AppColors.nightGold]. Numerically these are
/// the dark-mode values of `line` and `card`, but this face is constant-dark,
/// so the brightness-aware getters would flip them wrong in light mode —
/// constant surfaces get constant colors.
const _nightLine = Color(0xFF3A2F20);
const _nightCard = Color(0xFF221A11);

/// Full-screen reading session — pushed the moment a session starts (from
/// the book page's timer card, or reopened from the persistent mini-bar).
/// Two faces in one screen rather than two routes: the pocket-watch dial
/// while it's running, the wax-seal confirmation once it's stopped — "Done"
/// pops all the way back to the book page either way.
class ReadingTimerScreen extends ConsumerStatefulWidget {
  const ReadingTimerScreen({
    super.key,
    required this.libraryEntryId,
    this.title,
    this.author,
    this.currentPage,
    this.pageCount,
    this.coverUrl,
  });

  final String libraryEntryId;
  final String? title;
  final String? author;
  final int? currentPage;
  final int? pageCount;
  final String? coverUrl;

  @override
  ConsumerState<ReadingTimerScreen> createState() => _ReadingTimerScreenState();
}

class _ReadingTimerScreenState extends ConsumerState<ReadingTimerScreen>
    with SingleTickerProviderStateMixin {
  static const _zoneThreshold = Duration(minutes: 20);
  static const _handPeriod = Duration(minutes: 1);

  Timer? _clockTimer;
  late final AnimationController _hand = AnimationController(
    vsync: this,
    duration: _handPeriod,
  );
  bool _handSeeded = false;
  LoggedSession? _logged;
  late final _pageController = TextEditingController(
    text: widget.currentPage?.toString() ?? '',
  );
  final _pageFocusNode = FocusNode();
  /// The book's total pages, typed on the wax-seal face when the catalog
  /// doesn't know it — otherwise progress can never be a percentage.
  final _totalController = TextEditingController();
  bool _saving = false;

  /// This screen's own Stop & log is mid-flight — see [_stop] for why the
  /// "stopped elsewhere" guard has to know.
  bool _stopping = false;

  /// Whether [activeSessionProvider] has actually read storage yet.
  ///
  /// Until it has, an empty session means "nobody has looked", not "there is
  /// nothing running" — and this screen is reachable in exactly that window:
  /// a tap on the lock-screen clock cold-starts the process, so the Notifier's
  /// `build()` and this screen's first frame happen together. The give-up
  /// guard below used to fire on that frame and was saved only by an accident
  /// — `canPop()` is false on a cold start, so its `pop()` did nothing. Now
  /// that the guard can genuinely leave, it has to wait for the answer first
  /// or it would throw a reader out of a sitting that is running fine.
  bool _sessionResolved = false;

  /// The give-up guard has already fired. It lives in `build`, and this screen
  /// keeps rebuilding for as long as the pop transition plays (the clock ticks
  /// once a second until dispose), so without a latch a second frame would
  /// leave a *second* time — popping the book page out from under the reader.
  bool _leaving = false;

  /// Null while the typed page is savable. A backwards page must not be
  /// written by Done *or* by the back gesture, which also saves.
  PageEntryError? _pageError;

  /// The book and shelf entry, read from the database rather than taken on
  /// trust from the route's `extra`.
  ///
  /// `extra` is a snapshot the *caller* assembled, and the callers that matter
  /// most can't assemble one: a tap on the iOS Live Activity (and on the
  /// Android ongoing notification) navigates by URL, with no extra at all. The
  /// screen then believed the book had no page count and asked for the total on
  /// every single stop — while the book page, reading from the database, showed
  /// it perfectly (owner report, 26 Jul 2026). It also went in with no title
  /// and no cover. Extra is now only a first-frame hint; the database is the
  /// answer.
  CachedBook? _book;
  LibraryEntry? _entry;

  /// Where the newest sitting that noted a page ended — the fallback when the
  /// shelf entry itself has no current page.
  int? _lastLoggedPage;

  String? get _title => _book?.title ?? widget.title;
  String? get _author => _book?.authorNames ?? widget.author;
  String? get _coverUrl => _book?.coverUrl ?? widget.coverUrl;
  int? get _pageCount => _book?.pageCount ?? widget.pageCount;
  int? get _currentPage => _entry?.currentPage ?? widget.currentPage ?? _lastLoggedPage;

  Future<void> _resolveBook() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.libraryEntriesDao.getById(widget.libraryEntryId);
      if (entry == null || !mounted) return;
      final book = await db.cachedBooksDao.getByEditionId(entry.editionId);
      // A shelf entry with no page of its own can still have sittings that
      // recorded where they ended — "the page number was noted for the last
      // log, here page number came empty" (owner report, 26 Jul 2026). The most
      // recent sitting that noted a page is the best answer we have.
      int? lastLoggedPage;
      if (entry.currentPage == null) {
        final sessions = await db.readingSessionsDao.watchForEntry(entry.id).first;
        for (final s in sessions) {
          if (s.pageEnd != null) {
            lastLoggedPage = s.pageEnd;
            break; // newest first
          }
        }
      }
      if (!mounted) return;
      final seed = entry.currentPage ?? lastLoggedPage;
      setState(() {
        _entry = entry;
        _book = book;
        _lastLoggedPage = lastLoggedPage;
        // Only seed the field the reader hasn't touched — never overwrite a
        // page they've already typed.
        if (_pageController.text.trim().isEmpty && seed != null) {
          _pageController.text = '$seed';
        }
      });
    } catch (_) {
      // Falls back to whatever `extra` carried.
    }
  }

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _seedHandIfReady();
    unawaited(_resolveBook());
    unawaited(_awaitSession());
  }

  /// Arms the give-up guard once — and only once — storage has answered.
  Future<void> _awaitSession() async {
    try {
      await ref.read(activeSessionProvider.notifier).hydrated;
    } catch (_) {
      // A hydrate that blew up still counts as an answer: staying here on a
      // frozen clock is the one outcome worse than leaving.
    }
    if (!mounted) return;
    setState(() => _sessionResolved = true);
  }

  // Same deterministic forgot-to-stop safety net as the mini-bar
  // (`checkReadingTimerSafetyNet`), piggybacked on the tick this screen
  // already runs for its own live clock — if someone leaves the watch face
  // open for 90+ minutes, landing straight on the wax-seal face here is a
  // more coherent outcome than a bare snackbar on some other screen.
  Future<void> _tick() async {
    if (!mounted) return;
    final logged = await checkReadingTimerSafetyNet(ref);
    if (!mounted) return;
    if (logged == null) {
      setState(() {});
      return;
    }
    ref.invalidate(weeklyReadingSecondsProvider);
    setState(() => _logged = logged);
  }

  // Reopening a session that's already been running for a while must not
  // reset the sweeping hand to 12 o'clock — it has to pick up from the
  // actual elapsed second, same as the numeric clock next to it.
  void _seedHandIfReady() {
    if (_handSeeded) return;
    final startedAt = ref.read(activeSessionProvider)?.startedAt;
    if (startedAt == null) return;
    _handSeeded = true;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final seeded = (elapsedMs % _handPeriod.inMilliseconds) / _handPeriod.inMilliseconds;
    // Assigning `value` *stops* the controller, which completes the running
    // sweep's TickerFuture and hands `_loopHand` its cue — so a seed that
    // arrives while the hand is already turning (the late-resolve path this
    // is called from, and the only one that needs seeding at all) was undone
    // one microtask later by a `forward(from: 0)`. Restart the sweep here,
    // from the seeded position, and let `_loopHand` see it is already going.
    final wasAnimating = _hand.isAnimating;
    _hand.value = seeded;
    if (wasAnimating) _hand.forward(from: seeded).whenComplete(_loopHand);
  }

  void _loopHand() {
    if (!mounted) return;
    // A seed has already restarted the sweep from where the sitting actually
    // is; looping again from zero would throw that away.
    if (_hand.isAnimating) return;
    // `stop()` completes the TickerFuture too, so this fires when the hand is
    // deliberately halted — without this, switching the phone to reduced
    // motion mid-sitting simply started it again.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    _hand.forward(from: 0).whenComplete(_loopHand);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _seedHandIfReady();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _hand.stop();
    } else if (!_hand.isAnimating) {
      _hand.forward(from: _hand.value).whenComplete(_loopHand);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _hand.dispose();
    _pageController.dispose();
    _totalController.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  /// Stop the clock and move to the wax-seal face (where the page question is).
  ///
  /// [_stopping] is set *synchronously*, before the first await, because the
  /// stop clears the session mid-flight: the notifier nulls its state and then
  /// publishes the stop to the reader's other devices, which is a network round
  /// trip. Frames render during it — this screen animates a sweeping hand, so
  /// they certainly do — and the build below reads "no session for this book"
  /// as "stopped on another device" and pops the route. The reader tapped
  /// Stop & log and was returned to the book page, never seeing the page
  /// question (owner report, 14 Aug 2026). Same hazard the notifier's own
  /// `_stopping` flag guards the safety net against; this is its screen-side
  /// twin, and it must not wait on a `setState` to take effect.
  Future<void> _stop() async {
    if (_stopping) return;
    _stopping = true;
    Haptics.success();
    try {
      final logged = await ref.read(activeSessionProvider.notifier).stop();
      if (!mounted || logged == null) return;
      ref.invalidate(weeklyReadingSecondsProvider);
      setState(() => _logged = logged);
    } finally {
      // Cleared last: once `_logged` is set the guard no longer applies, and
      // if nothing was running the screen *should* be free to close.
      _stopping = false;
    }
  }

  /// The book had no page count and the reader typed one on the way out.
  /// Without a total there's no progress bar and no percentage, so the timer
  /// is exactly where the gap hurts — and exactly where they know the number
  /// (the book is in their hands). Owner request, 17 Jul 2026.
  ///
  /// The total belongs to the shared Edition, so it goes to the catalog; the
  /// local mirror is written either way, so their progress works offline and
  /// reconciles the next time this book is re-cached.
  Future<void> _saveTotalPages() async {
    if (_pageCount != null) return; // already known — the field isn't shown
    final total = int.tryParse(_totalController.text.trim());
    if (total == null || total <= 0) return;
    // Look the entry up directly (awaited) rather than off a stream provider
    // that may not have emitted on this route — that read returned empty here,
    // so the editionId came back null and the total was silently dropped.
    final entry = await ref.read(appDatabaseProvider).libraryEntriesDao.getById(widget.libraryEntryId);
    final editionId = entry?.editionId;
    if (editionId == null) return;
    await saveBookTotalPages(
      ref.read(appDatabaseProvider),
      ref.read(apiClientProvider),
      editionId,
      total,
    );
  }

  /// Persist the page reached (and the total, if they supplied one). Split out
  /// of [_done] because leaving this screen by the system back gesture must
  /// save too — the wax-seal face has no close button, so back/swipe used to
  /// pop the route without ever running this, silently dropping the page the
  /// reader had just typed (owner report, 16 Jul 2026).
  ///
  /// Guarded against the entry's *live* page rather than [widget.currentPage],
  /// which is a snapshot from when this screen opened and goes stale the
  /// moment progress changes anywhere else mid-session.
  /// Returns whether this save is what finished the book — the review nudge
  /// hangs off that, and only this method knows it.
  Future<bool> _savePage() async {
    await _saveTotalPages();
    final logged = _logged;
    final page = int.tryParse(_pageController.text.trim());
    if (logged == null || page == null) return false;
    // Back/swipe saves too (16 Jul 2026), so the same guard that disables Done
    // has to hold here — otherwise leaving by gesture is a way around it.
    if (_pageError != null) return false;
    final entry = await ref.read(appDatabaseProvider).libraryEntriesDao.getById(widget.libraryEntryId);
    // The sitting's own end page is always recorded — it and the entry's
    // progress are two different facts. They were behind one "unchanged"
    // guard, so a sitting that ended on the page the entry *already* held
    // wrote neither: the reading log said "no page noted" while the progress
    // bar showed the page (owner report, 26 Jul 2026). That is the normal
    // shape of a first sitting, where the reader set their page before
    // starting the clock.
    final sessionsRepo = await ref.read(readingSessionsRepositoryProvider.future);
    await sessionsRepo.updateSessionPageEnd(logged.sessionId, page);
    if (page == entry?.currentPage) return false; // progress genuinely unchanged
    final libraryRepo = await ref.read(libraryRepositoryProvider.future);
    await libraryRepo.updateProgress(widget.libraryEntryId, currentPage: page);
    // Ending a plain (non-"I finished the book") sitting on the last page
    // finishes it too — _markFinished already handles its own explicit path.
    return autoFinishIfOnLastPage(
      db: ref.read(appDatabaseProvider),
      repo: libraryRepo,
      libraryEntryId: widget.libraryEntryId,
    );
  }

  /// The review nudge, shown from the *root* navigator once this screen is on
  /// its way out — the book page (or Home) is what is left underneath, and it
  /// is where the rating the reader gives will show up. Both handles are read
  /// before the first await, because every path here is a path off this
  /// screen (19 Jul, 31 Jul 2026).
  ({ProviderContainer container, NavigatorState navigator}) _leaveHandles() => (
        container: ProviderScope.containerOf(context, listen: false),
        navigator: Navigator.of(context, rootNavigator: true),
      );

  Future<void> _promptReview(
    ({ProviderContainer container, NavigatorState navigator}) handles,
  ) async {
    if (!handles.navigator.mounted) return;
    await maybePromptForReview(
      handles.navigator.context,
      handles.container,
      libraryEntryId: widget.libraryEntryId,
    );
  }

  /// Leave the timer. Normally a pop, but this route can also be *arrived at*
  /// rather than pushed — an external link (the iOS Live Activity's tap URL)
  /// is delivered to the router as a navigation, which replaces the stack
  /// instead of stacking onto it. There is then nothing to pop, and a bare
  /// `pop()` left the reader stranded on the timer with no way out.
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  Future<void> _done() async {
    if (_logged != null) setState(() => _saving = true);
    final handles = _leaveHandles();
    final finished = await _savePage();
    if (mounted) _leave();
    if (finished) await _promptReview(handles);
  }

  /// "I finished the book" — the other way off this face. Stopping the clock
  /// and finishing the book are different claims, and until now the timer could
  /// only make the first one: a reader who closed the last page had to stop,
  /// leave, find the book, and change its status by hand (owner request,
  /// 26 Jul 2026).
  ///
  /// The page is settled *before* the status, and settled to the total when the
  /// catalogue knows it — a sitting that ended the book ended on its last page,
  /// so the session's own page range should say so too, not just the entry's
  /// progress. Everything after that is [markBookFinished], shared with the
  /// book page and the quick-stop sheet so the three can't drift.
  Future<void> _markFinished() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);

    final total = _pageCount;
    if (total != null && total > 0) {
      _pageController.text = '$total';
      // Forced from the book's own length, so any staleness in the typed-page
      // validation no longer applies — and _savePage refuses to run while an
      // error is outstanding.
      _pageError = null;
    }
    final handles = _leaveHandles();
    // The page save may already have finished the book (the line above forces
    // the field to the total), in which case `markBookFinished` has nothing
    // left to change and reports so — but the reader has still just finished a
    // book, and it is one event however many calls noticed it.
    final finishedBySave = await _savePage();

    final db = ref.read(appDatabaseProvider);
    final repo = await ref.read(libraryRepositoryProvider.future);
    final result = await markBookFinished(
      db: db,
      repo: repo,
      libraryEntryId: widget.libraryEntryId,
    );

    messenger.showSnackBar(SnackBar(
      content: Text(result.pagesFilledTo == null
          ? l10n.timerMarkFinishedDone
          : l10n.statusReadAllPages(result.pagesFilledTo!)),
    ));
    if (mounted) _leave();
    if (finishedBySave || result.justFinished) await _promptReview(handles);
  }

  /// Leaving by the back gesture saves the page too (16 Jul 2026) — so if that
  /// save is what finished the book, it earns the same nudge Done gets.
  void _savePageOnPop() {
    final handles = _leaveHandles();
    unawaited(() async {
      if (await _savePage()) await _promptReview(handles);
    }());
  }

  /// N1 -> N2. Opens a fresh note page without touching the session: the clock
  /// keeps running, and this method deliberately has no stop/pause path. The
  /// pill's main tap always lands here — mid-thought, a list of old notes in
  /// the way is friction. Re-reading is the *strip under the pill* now: the
  /// notes themselves, one line each. A bare count in a chip read as a badge,
  /// and badges are not usually buttons, so nobody found the list behind it
  /// (owner report, 14 Aug 2026).
  Future<void> _openFreshNote(ActiveSession active) async {
    final count = ref.read(sessionNotesProvider(active.id)).valueOrNull?.length ?? 0;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => NotePage(
          libraryEntryId: active.libraryEntryId,
          bookTitle: _title,
          sessionId: active.id,
          sessionStartedAt: active.startedAt,
          currentPage: _currentPage,
          noteIndex: count + 1,
        ),
      ),
    );
  }

  /// A row in the sitting's note strip — opens that note in the same editor it
  /// was written in (N5), with the live clock still pinned at the top.
  Future<void> _openExistingNote(ActiveSession active, ReadingNote note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => NotePage(
          libraryEntryId: active.libraryEntryId,
          existing: note,
          bookTitle: _title,
          sessionId: active.id,
          sessionStartedAt: active.startedAt,
          currentPage: _currentPage,
        ),
      ),
    );
  }

  /// The count badge's tap — the sitting's notes so far, to re-read or fix a
  /// thought just jotted (owner report, 21 Jul 2026). "Write another" from the
  /// sheet still lands on a fresh page.
  Future<void> _openNotesList(ActiveSession active) async {
    final existing = ref.read(sessionNotesProvider(active.id)).valueOrNull ?? const [];
    if (existing.isEmpty) return _openFreshNote(active);
    final wantsNew = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SessionNotesSheet(
        notes: existing,
        libraryEntryId: active.libraryEntryId,
      ),
    );
    if (wantsNew != true || !mounted) return;
    await _openFreshNote(active);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeSessionProvider);
    final sessionNotes =
        active == null ? const <ReadingNote>[] : (ref.watch(sessionNotesProvider(active.id)).valueOrNull ?? const []);
    // Cold-start restore case: activeSessionProvider hydrates from disk
    // asynchronously, so it can still be null on the first build or two —
    // seed the hand as soon as it resolves instead of leaving it at 0.
    ref.listen<ActiveSession?>(activeSessionProvider, (_, next) {
      if (next != null) _seedHandIfReady();
    });
    // Stopped from elsewhere (the mini-bar's own quick-stop, or the reader's
    // other device) while this screen sat in the background — nothing left to
    // show here. Never while *this* screen's stop is in flight: that window
    // looks identical from here and is the one case where the session ending
    // is precisely the reason to stay.
    if (_sessionResolved &&
        !_leaving &&
        _logged == null &&
        !_stopping &&
        active?.libraryEntryId != widget.libraryEntryId) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Whatever brought the reader to a sitting that does not exist was
        // itself stale — and the usual suspect is the lock-screen clock,
        // whose whole purpose is to be tappable. Take it down on the way out
        // rather than leaving it to invite the reader back to the same dead
        // screen (owner report, 29 Aug 2026).
        unawaited(ref.read(activeSessionProvider.notifier).reconcile());
        // `_leave()`, not a bare `pop()`. This route is *arrived at* as often
        // as it is pushed — a notification tap on a cold start replaces the
        // stack, so `canPop()` is false and the pop this guard used to make
        // silently did nothing. The reader was left on a running face with no
        // session behind it: a sweeping hand over a clock stuck at 0:00, and
        // no way off the screen (CLAUDE.md, 14 Aug 2026 — every exit needs
        // `canPop() ? pop() : go(home)`; this one never got it).
        _leave();
      });
    }

    return PopScope(
      // Leaving the wax-seal face by the back gesture must still log the page
      // (there's no close button there — only "Done" — so back was a silent
      // data-loss path). The pop itself is never blocked; we just save on the
      // way out.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePageOnPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: SafeArea(
          child: _logged == null
              ? _RunningFace(
                title: _title,
                author: _author,
                coverUrl: _coverUrl,
                startedAt: active?.startedAt,
                onClose: _leave,
                hand: _hand,
                onStop: _stop,
                onNote: active == null ? null : () => _openFreshNote(active),
                onShowNotes: active == null ? null : () => _openNotesList(active),
                notes: sessionNotes,
                onOpenNote: active == null
                    ? null
                    : (note) => _openExistingNote(active, note),
              )
              : _LoggedFace(
                  title: _title,
                  author: _author,
                  coverUrl: _coverUrl,
                  libraryEntryId: widget.libraryEntryId,
                  logged: _logged!,
                  pageController: _pageController,
                  pageFocusNode: _pageFocusNode,
                  pageCount: _pageCount,
                  totalController: _totalController,
                  saving: _saving,
                  hasPageError: _pageError != null,
                  onDone: _done,
                  onFinished: _markFinished,
                  onValidityChanged: (err) => setState(() => _pageError = err),
                ),
        ),
      ),
    );
  }
}

class _RunningFace extends StatelessWidget {
  const _RunningFace({
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.startedAt,
    required this.onClose,
    required this.hand,
    required this.onStop,
    required this.onNote,
    required this.onShowNotes,
    required this.notes,
    required this.onOpenNote,
  });

  final String? title;
  final String? author;
  final String? coverUrl;
  final DateTime? startedAt;
  final AnimationController hand;
  final VoidCallback onStop;

  /// Leaving the timer — a pop when this route was pushed, Home when it was
  /// *navigated to* from outside and there is nothing beneath it. The session
  /// keeps running either way (the chevron minimizes, music-player style).
  final VoidCallback onClose;

  /// Opens a fresh note page (N1 -> N2). Null hides the pill.
  final VoidCallback? onNote;

  /// Opens the full list of this sitting's notes — the strip's "All N" door,
  /// shown only once the strip is capped.
  final VoidCallback? onShowNotes;

  /// This sitting's notes, oldest first. Shown *as themselves* under the pill
  /// rather than as a count: the count was the reason nobody knew there was
  /// anything to open (owner pick, 14 Aug 2026 — docs/reading-notes-mockups.html
  /// direction B).
  final List<ReadingNote> notes;

  /// Opens one of them in the same editor it was written in (N5).
  final void Function(ReadingNote note)? onOpenNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt!);
    final inZone = elapsed >= _ReadingTimerScreenState._zoneThreshold;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.7),
          radius: 1.1,
          colors: [Color(0xFF3A2416), AppColors.night, Color(0xFF120C08)],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              // A chevron, not an X — leaving this screen backgrounds the
              // session (the mini-bar keeps following it); an X read as
              // "cancel the sitting".
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                tooltip: l10n.timerMinimizeHint,
                onPressed: onClose,
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.timerInProgress.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.nightGold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Always the cover frame — a cover-less book gets
                          // the typeset fallback, not a bare title.
                          TypesetCover(
                            title: title!,
                            author: author,
                            coverUrl: coverUrl,
                            width: 30,
                            height: 44,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              title!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.nightGold.withValues(alpha: 0.28),
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.nightGold.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                        for (var i = 0; i < 12; i++)
                          Transform.rotate(
                            angle: i * math.pi / 6,
                            child: Align(
                              alignment: const Alignment(0, -0.92),
                              child: Container(
                                width: 1.5,
                                height: i % 3 == 0 ? 12 : 8,
                                color: i % 3 == 0
                                    ? AppColors.nightGold
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        AnimatedBuilder(
                          animation: hand,
                          builder: (context, _) => Transform.rotate(
                            angle: hand.value * 2 * math.pi,
                            child: Align(
                              alignment: const Alignment(0, -0.75),
                              child: Container(
                                width: 2,
                                height: 78,
                                decoration: BoxDecoration(
                                  color: AppColors.nightGold,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.nightGold.withValues(alpha: 0.7),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.nightGold,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatClock(elapsed),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.timerElapsed,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedOpacity(
                    opacity: inZone ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.nightGold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.nightGold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _Dot(),
                          const SizedBox(width: 6),
                          Text(
                            l10n.timerInTheZone(elapsed.inMinutes),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.nightGold,
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
          // N1 — the way into a note, quiet and above Stop & log so it never
          // competes with it. One pill, one destination: a fresh page.
          //
          // What used to sit inside this pill was a second hit region — a grey
          // count chip that opened the sitting's notes. It read as a badge, and
          // badges are not usually buttons, so the notes behind it were
          // effectively undiscoverable (owner report, 14 Aug 2026). The strip
          // below replaces it: the notes *are* the list, which also makes the
          // stop sheet's "your 2 notes are already saved" self-evidently true.
          if (onNote != null)
            Padding(
              padding: EdgeInsets.only(bottom: notes.isEmpty ? 14 : 10),
              child: Center(
                child: Material(
                  color: _nightCard,
                  shape: const StadiumBorder(side: BorderSide(color: _nightLine)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onNote,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_outlined,
                                size: 16, color: AppColors.nightGold),
                            const SizedBox(width: 8),
                            Text(
                              AppLocalizations.of(context)!.noteAThought,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (notes.isNotEmpty)
            _SessionNoteStrip(
              notes: notes,
              onOpenNote: onOpenNote,
              onShowAll: onShowNotes,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.nightGold,
                  foregroundColor: AppColors.night,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: onStop,
                icon: Container(width: 10, height: 10, color: AppColors.night),
                label: Text(
                  l10n.timerStopAndLog,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.nightGold,
        boxShadow: [
          BoxShadow(
            color: AppColors.nightGold.withValues(alpha: 0.7),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _LoggedFace extends ConsumerWidget {
  const _LoggedFace({
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.libraryEntryId,
    required this.logged,
    required this.pageController,
    required this.pageFocusNode,
    required this.pageCount,
    required this.totalController,
    required this.saving,
    required this.hasPageError,
    required this.onDone,
    required this.onFinished,
    required this.onValidityChanged,
  });

  final String? title;
  final String? author;
  final String? coverUrl;
  final String libraryEntryId;
  final LoggedSession logged;
  final TextEditingController pageController;
  final FocusNode pageFocusNode;
  final int? pageCount;

  /// Only used when [pageCount] is null — the reader supplying the total.
  final TextEditingController totalController;

  /// A save is in flight — Done shows its spinner and everything locks.
  final bool saving;

  /// The typed page can't be saved. Blocks Done, but not "I finished the
  /// book" when the total is known — finishing overwrites the page with the
  /// total anyway, so a typo it would itself clear must not disable it.
  final bool hasPageError;
  final VoidCallback onDone;

  /// "I finished the book" — see `_markFinished`.
  final VoidCallback onFinished;

  /// Fires when the typed page becomes (in)valid, so Done can be disabled
  /// rather than silently walking the reader's progress backwards.
  final ValueChanged<PageEntryError?> onValidityChanged;

  /// R3 from the wax-seal face — the same sittings log the quick-stop sheet
  /// reaches from its anchor line, as a sheet over this full-screen face.
  Future<void> _openLog(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) => SessionsLog(
          title: title,
          sessions:
              sheetRef.watch(stopSessionsProvider(libraryEntryId)).valueOrNull ??
                  const <ReadingSession>[],
          onBack: () => Navigator.of(ctx).pop(),
          onDelete: (session) async {
            Haptics.selection();
            // Handles captured before the awaits — same rule as quickStopSession.
            final messenger = ScaffoldMessenger.of(ctx);
            final deleted = AppLocalizations.of(ctx)!.bookLogDeleted;
            final repo =
                await sheetRef.read(readingSessionsRepositoryProvider.future);
            await repo.deleteSession(session.id);
            messenger.showSnackBar(SnackBar(content: Text(deleted)));
          },
          onEdit: (session, endedAt, pageEnd) async {
            Haptics.selection();
            final repo =
                await sheetRef.read(readingSessionsRepositoryProvider.future);
            await repo.correctSessionEnd(
              session.id,
              startedAt: session.startedAt,
              endedAt: endedAt,
              pageEnd: pageEnd,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final duration = Duration(seconds: logged.durationSeconds);
    final weekTotal = ref.watch(weeklyReadingSecondsProvider);
    final sessions = ref.watch(stopSessionsProvider(libraryEntryId)).valueOrNull ??
        const <ReadingSession>[];
    // The most recent *previous* sitting — the one just logged is already in
    // the stream and must be excluded by id (same rule as the stop sheet).
    final last = sessions
        .where((s) => s.id != logged.sessionId && s.pageEnd != null)
        .firstOrNull;
    final sessionNotes =
        ref.watch(sessionNotesProvider(logged.sessionId)).valueOrNull ??
            const <ReadingNote>[];

    return Container(
      color: AppColors.paper,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [
                          const Color(0xFFA8394A),
                          AppColors.oxblood,
                          const Color(0xFF4A161C),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.oxblood.withValues(alpha: 0.35),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '❦',
                      style: TextStyle(color: AppColors.goldSoft, fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    l10n.timerLoggedTitle(duration.inMinutes),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (title != null) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Always the cover frame — a cover-less book gets
                          // the typeset fallback, not a bare title.
                          TypesetCover(
                            title: title!,
                            author: author,
                            coverUrl: coverUrl,
                            width: 24,
                            height: 36,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              title!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatColumn(
                        value: formatDuration(duration),
                        label: l10n.timerThisSession,
                      ),
                      const SizedBox(width: 28),
                      _StatColumn(
                        value: formatDuration(
                          Duration(
                            seconds:
                                weekTotal.valueOrNull ?? logged.durationSeconds,
                          ),
                        ),
                        label: l10n.timerThisWeek,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SessionPageEntry(
                      pageController: pageController,
                      totalController: totalController,
                      pageFocusNode: pageFocusNode,
                      pageCount: pageCount,
                      pageStart: logged.pageStart,
                      duration: duration,
                      onValidityChanged: onValidityChanged,
                      // The anchor's "last time" line and the way into the
                      // sittings log, same as the quick-stop sheet — the most
                      // deliberate stop path must not be the poorer one.
                      onOpenLog: sessions.isEmpty
                          ? null
                          : () => _openLog(context, ref),
                      lastSessionLine: last == null
                          ? null
                          : formatLastSessionLine(
                              l10n,
                              endedAt: last.endedAt,
                              durationSeconds: last.durationSeconds,
                              pageStart: last.pageStart,
                              pageEnd: last.pageEnd,
                            ),
                    ),
                  ),
                  // N3 — the closing-thought moment, shared with the
                  // quick-stop sheet so the two stop paths can't drift.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: SessionNotesBlock(
                      notes: sessionNotes,
                      libraryEntryId: libraryEntryId,
                      sessionId: logged.sessionId,
                      bookTitle: title,
                      currentPage: () =>
                          int.tryParse(pageController.text.trim()),
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
          // Finishing sits *above* Done and in moss, not oxblood: it's the
          // rarer, larger claim ("that was the last page"), so it has to be
          // findable without ever competing with the ordinary way out. A page
          // typo doesn't disable it while the total is known — finishing
          // settles the page to the total anyway.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.moss,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: (saving || (hasPageError && pageCount == null))
                    ? null
                    : onFinished,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '✓  ${l10n.timerMarkFinished}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.timerMarkFinishedHint,
                      style: TextStyle(color: AppColors.inkSoft, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.oxblood,
                      side: BorderSide(color: AppColors.oxblood),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (saving || hasPageError) ? null : onDone,
                    child: saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.oxblood,
                            ),
                          )
                        : Text(
                            l10n.timerDone,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                // Names what leaving keeps — the quiet mirror of the stop
                // sheet's "Skip — keep the time, leave the page at …".
                Text(
                  l10n.timerDoneKeepsPage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.oxblood,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 8.5,
            letterSpacing: 1,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}


/// The notes already written in this sitting, reachable from the pill's count
/// badge. Each opens straight into the editor — mid-session you're still
/// writing, so a thought just jotted can be fixed (read-only is for the book
/// page, where you're revisiting old thoughts). "Note a thought" starts a
/// fresh one. The session keeps running throughout — nothing here stops it.
class _SessionNotesSheet extends StatelessWidget {
  const _SessionNotesSheet({required this.notes, required this.libraryEntryId});

  final List<ReadingNote> notes;
  final String libraryEntryId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.notesSectionThisSitting(notes.length),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final note = notes[i];
                  final pages = note.pageStart == null
                      ? null
                      : (note.pageEnd == null
                          ? 'p. ${note.pageStart}'
                          : 'p. ${note.pageStart}-${note.pageEnd}');
                  return Material(
                    color: AppColors.slip,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<bool>(
                            builder: (_) => NotePage(
                              libraryEntryId: libraryEntryId,
                              existing: note,
                              // Mid-session you're still writing, so this opens
                              // straight into the editor. Read-only is for the
                              // book page, where you're revisiting old thoughts
                              // (owner report, 21 Jul 2026).
                            ),
                          ),
                        );
                        if (context.mounted) Navigator.of(context).pop(false);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: AppColors.slipLine),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(note.body, style: const TextStyle(fontSize: 13, height: 1.5)),
                            if (pages != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                pages,
                                style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.noteAThought),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.oxblood,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// The sitting's notes, under the pill — direction B of
/// docs/reading-notes-mockups.html (owner pick, 14 Aug 2026).
///
/// One line each, page first, newest last, each row opening that note in the
/// editor it was written in. Capped at three with an honest "All N" door, the
/// same shape the Type and Genre chip rows use: this strip shares a screen
/// with Stop & log, and nothing may push that around.
class _SessionNoteStrip extends StatelessWidget {
  const _SessionNoteStrip({
    required this.notes,
    required this.onOpenNote,
    required this.onShowAll,
  });

  final List<ReadingNote> notes;
  final void Function(ReadingNote note)? onOpenNote;
  final VoidCallback? onShowAll;

  static const _visible = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Newest last matches the journal on the book page, so a reader who scans
    // down is reading forward in time in both places.
    final shown = notes.length <= _visible ? notes : notes.sublist(notes.length - _visible);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: _nightLine),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.notesThisSittingLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                ),
                if (notes.length > _visible && onShowAll != null)
                  InkWell(
                    onTap: onShowAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        l10n.notesShowAll(notes.length),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.nightGold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final note in shown)
            InkWell(
              onTap: onOpenNote == null ? null : () => onOpenNote!(note),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        _pageLabel(note, l10n),
                        style: const TextStyle(fontSize: 8.5, color: AppColors.nightGold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        note.body.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.fraunces(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.onDarkSoft,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 14, color: AppColors.onDarkSoft),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "p. 84–86" for a range, "p. 76" for a point, blank when the reader gave
  /// no page — the note is still worth showing (the 31 Jul lesson: render the
  /// half you hold).
  String _pageLabel(ReadingNote note, AppLocalizations l10n) {
    final start = note.pageStart;
    if (start == null) return '';
    final end = note.pageEnd;
    return end == null || end == start ? l10n.bookProgressPage(start) : 'p. $start–$end';
  }
}
