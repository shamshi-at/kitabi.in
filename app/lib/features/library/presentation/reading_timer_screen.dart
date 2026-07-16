import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format_duration.dart';
import '../../../core/haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/library_providers.dart';
import '../providers/reading_timer_providers.dart';

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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _seedHandIfReady();
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
    _hand.value = (elapsedMs % _handPeriod.inMilliseconds) / _handPeriod.inMilliseconds;
  }

  void _loopHand() {
    if (!mounted) return;
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
    _pageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    Haptics.success();
    final logged = await ref.read(activeSessionProvider.notifier).stop();
    if (!mounted || logged == null) return;
    ref.invalidate(weeklyReadingSecondsProvider);
    setState(() => _logged = logged);
  }

  /// Persist the page reached. Split out of [_done] because leaving this
  /// screen by the system back gesture must save too — the wax-seal face has
  /// no close button, so back/swipe used to pop the route without ever running
  /// this, silently dropping the page the reader had just typed (owner report,
  /// 16 Jul 2026: "sometimes the page doesn't update when stopping").
  ///
  /// Guarded against the entry's *live* page rather than [widget.currentPage],
  /// which is a snapshot from when this screen opened and goes stale the
  /// moment progress changes anywhere else mid-session.
  Future<void> _savePage() async {
    final logged = _logged;
    final page = int.tryParse(_pageController.text.trim());
    if (logged == null || page == null) return;
    final entries = ref.read(libraryEntriesProvider).valueOrNull ?? const <LibraryEntry>[];
    final livePage = entries
        .where((e) => e.id == widget.libraryEntryId)
        .map((e) => e.currentPage)
        .firstOrNull;
    if (page == livePage) return; // genuinely unchanged — nothing to write
    final sessionsRepo = await ref.read(readingSessionsRepositoryProvider.future);
    await sessionsRepo.updateSessionPageEnd(logged.sessionId, page);
    final libraryRepo = await ref.read(libraryRepositoryProvider.future);
    await libraryRepo.updateProgress(widget.libraryEntryId, currentPage: page);
  }

  Future<void> _done() async {
    if (_logged != null) setState(() => _saving = true);
    await _savePage();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeSessionProvider);
    // Cold-start restore case: activeSessionProvider hydrates from disk
    // asynchronously, so it can still be null on the first build or two —
    // seed the hand as soon as it resolves instead of leaving it at 0.
    ref.listen<ActiveSession?>(activeSessionProvider, (_, next) {
      if (next != null) _seedHandIfReady();
    });
    // Stopped from elsewhere (the mini-bar's own quick-stop) while this
    // screen sat in the background — nothing left to show here.
    if (_logged == null && active?.libraryEntryId != widget.libraryEntryId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
    }

    return PopScope(
      // Leaving the wax-seal face by the back gesture must still log the page
      // (there's no close button there — only "Done" — so back was a silent
      // data-loss path). The pop itself is never blocked; we just save on the
      // way out.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePage();
      },
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: SafeArea(
          child: _logged == null
              ? _RunningFace(
                title: widget.title,
                coverUrl: widget.coverUrl,
                startedAt: active?.startedAt,
                hand: _hand,
                onStop: _stop,
              )
              : _LoggedFace(
                  title: widget.title,
                  coverUrl: widget.coverUrl,
                  logged: _logged!,
                  pageController: _pageController,
                  pageFocusNode: _pageFocusNode,
                  pageCount: widget.pageCount,
                  saving: _saving,
                  onDone: _done,
                ),
        ),
      ),
    );
  }
}

class _RunningFace extends StatelessWidget {
  const _RunningFace({
    required this.title,
    required this.coverUrl,
    required this.startedAt,
    required this.hand,
    required this.onStop,
  });

  final String? title;
  final String? coverUrl;
  final DateTime? startedAt;
  final AnimationController hand;
  final VoidCallback onStop;

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
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.timerInProgress,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Color(0xFFE3B14C),
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
                          if (coverUrl != null) ...[
                            TypesetCover(
                              title: title!,
                              coverUrl: coverUrl,
                              width: 30,
                              height: 44,
                            ),
                            const SizedBox(width: 10),
                          ],
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
                              color: const Color(
                                0xFFE3B14C,
                              ).withValues(alpha: 0.28),
                            ),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(
                                0xFFE3B14C,
                              ).withValues(alpha: 0.16),
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
                                    ? const Color(0xFFE3B14C)
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
                                  color: const Color(0xFFE3B14C),
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFE3B14C,
                                      ).withValues(alpha: 0.7),
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
                            color: Color(0xFFE3B14C),
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
                        color: const Color(0xFFE3B14C).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(
                            0xFFE3B14C,
                          ).withValues(alpha: 0.35),
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
                              color: Color(0xFFE3B14C),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE3B14C),
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
        color: const Color(0xFFE3B14C),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE3B14C).withValues(alpha: 0.7),
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
    required this.coverUrl,
    required this.logged,
    required this.pageController,
    required this.pageFocusNode,
    required this.pageCount,
    required this.saving,
    required this.onDone,
  });

  final String? title;
  final String? coverUrl;
  final LoggedSession logged;
  final TextEditingController pageController;
  final FocusNode pageFocusNode;
  final int? pageCount;
  final bool saving;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final duration = Duration(seconds: logged.durationSeconds);
    final weekTotal = ref.watch(weeklyReadingSecondsProvider);

    return Container(
      color: AppColors.paper,
      child: Column(
        children: [
          Expanded(
            child: Center(
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
                          if (coverUrl != null) ...[
                            TypesetCover(
                              title: title!,
                              coverUrl: coverUrl,
                              width: 24,
                              height: 36,
                            ),
                            const SizedBox(width: 8),
                          ],
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
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => pageFocusNode.requestFocus(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              l10n.timerPageFieldLabel,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 54,
                              child: TextField(
                                controller: pageController,
                                focusNode: pageFocusNode,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.oxblood,
                                    ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: AppColors.paperDeep,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  hintText: l10n.timerPageFieldHint,
                                  hintStyle: TextStyle(color: AppColors.inkSoft),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.oxblood,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 13,
                              color: AppColors.inkSoft,
                            ),
                            if (pageCount != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                l10n.timerPageFieldOf(pageCount!),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkSoft,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: pageController,
                    builder: (context, _) {
                      final pageStart = logged.pageStart;
                      final pageEnd = int.tryParse(pageController.text.trim());
                      final pages = (pageStart != null && pageEnd != null && pageEnd > pageStart)
                          ? pageEnd - pageStart
                          : null;
                      if (pages == null) return const SizedBox.shrink();
                      final hours = duration.inSeconds / 3600;
                      final pace = hours > 0 ? (pages / hours).round() : null;
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          pace != null
                              ? '${l10n.timerSessionPages(pages)} · ${l10n.timerPagesPerHour('$pace')}'
                              : l10n.timerSessionPages(pages),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.oxblood,
                  side: BorderSide(color: AppColors.oxblood),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: saving ? null : onDone,
                child: Text(
                  l10n.timerDone,
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
