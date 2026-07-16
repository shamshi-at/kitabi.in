import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/connections/connections_providers.dart';
import '../../features/library/providers/reading_timer_providers.dart';
import '../../features/library/stop_session_flow.dart';
import '../../l10n/app_localizations.dart';
import '../format_duration.dart';
import '../haptics.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_status_bar.dart';
import '../widgets/typeset_cover.dart';
import 'app_router.dart';

/// The persistent bottom-nav shell (S3 mockup): Home · Library · [+] ·
/// Lending · Insights. The four real tabs map to the [StatefulNavigationShell]
/// branches; "+" is an action (opens the add flow), not a tab.
///
/// The "+" is a flat tile in the middle of five equal-width slots — with an
/// odd count of equal slots, the middle slot's centre IS the screen centre,
/// so it needs no floating machinery to sit exactly centred (asserted in
/// shell_nav_test). A centerDocked FloatingActionButton was tried and
/// reverted (owner feedback, 8 Jul 2026): the FAB lives in the Scaffold's
/// floating layer, so every modal bottom sheet (lend, log-borrowed, filters)
/// rendered UNDER it — the "+" punched through on top of the sheet's own
/// primary button. A row tile is ordinary content: sheets cover it.
///
/// The Lending item carries a badge when connection requests await approval
/// (the first hop of the notification chain: footer → ledger header →
/// connections inbox). Global search lives in the Home/Library headers
/// instead of the footer — it doesn't need permanent nav real estate.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final index = navigationShell.currentIndex;
    // Requests waiting on this reader's approval — the lending-side signal.
    final incoming = ref.watch(connectionsProvider).valueOrNull?.incoming.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.paper,
      // The sync bar sat above the notch (over the clock). Consume the top
      // inset here so it renders just below the notch; branch screens' own
      // SafeArea then sees a zero top inset (nested SafeArea doesn't double up).
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SyncStatusBar(),
            Expanded(child: navigationShell),
            _MiniTimerBar(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: l10n.navHome,
                  selected: index == 0,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(0, initialLocation: true); },
                ),
                _NavItem(
                  icon: Icons.auto_stories_outlined,
                  activeIcon: Icons.auto_stories,
                  label: l10n.navLibrary,
                  selected: index == 1,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(1, initialLocation: true); },
                ),
                // Scan-first (docs/screen-design.md): the tile opens the camera
                // directly — one tap to the main add path. Search / manual add
                // stay one tap away via the scanner's fallback buttons.
                _AddButton(
                  label: l10n.navAdd,
                  onTap: () { Haptics.selection(); context.push(Routes.catalogScan); },
                ),
                _NavItem(
                  icon: Icons.swap_horiz,
                  activeIcon: Icons.swap_horiz,
                  label: l10n.navLending,
                  selected: index == 2,
                  badgeCount: incoming,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(2, initialLocation: true); },
                ),
                _NavItem(
                  icon: Icons.donut_large_outlined,
                  activeIcon: Icons.donut_large,
                  label: l10n.navInsights,
                  selected: index == 3,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(3, initialLocation: true); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Non-zero → a count pip on the icon (pending connection requests).
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.oxblood : AppColors.inkSoft;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? activeIcon : icon, size: 22, color: color),
                if (badgeCount > 0)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      constraints: BoxConstraints(minWidth: 14, minHeight: 14),
                      decoration:
                          BoxDecoration(color: AppColors.oxblood, shape: BoxShape.circle),
                      child: Text(
                        '$badgeCount',
                        style: TextStyle(
                          color: AppColors.paper,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim strip that follows a running reading session across every tab —
/// same idea as a music mini-player. Gates on whether a session is actually
/// running before mounting `_MiniTimerBarContent` at all, so its live-clock
/// `Timer.periodic` only ever exists (and ticks) while there's something to
/// show — not for the entire lifetime of the app shell.
class _MiniTimerBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider);
    if (active == null) return const SizedBox.shrink();
    return _MiniTimerBarContent(active: active);
  }
}

class _MiniTimerBarContent extends ConsumerStatefulWidget {
  const _MiniTimerBarContent({required this.active});

  final ActiveSession active;

  @override
  ConsumerState<_MiniTimerBarContent> createState() => _MiniTimerBarContentState();
}

class _MiniTimerBarContentState extends ConsumerState<_MiniTimerBarContent> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // Runs on every second the mini-bar is visible — piggybacks the
  // deterministic forgot-to-stop safety net (`checkReadingTimerSafetyNet`)
  // onto the tick this widget already needs for its own live clock, instead
  // of a separate lifecycle observer.
  Future<void> _tick() async {
    if (!mounted) return;
    final logged = await checkReadingTimerSafetyNet(ref);
    if (!mounted) return;
    if (logged == null) {
      setState(() {});
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    ref.invalidate(weeklyReadingSecondsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.timerResumeSafetyNetMessage(formatDuration(Duration(seconds: logged.durationSeconds))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final activeBook = ref.watch(activeSessionBookProvider);
    final elapsed = DateTime.now().difference(active.startedAt);
    final title = activeBook?.book?.title;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: GestureDetector(
        onTap: () {
          Haptics.selection();
          context.push(
            Routes.readingTimerPath(active.libraryEntryId),
            extra: {
              'title': title,
              'author': activeBook?.book?.authorNames,
              'currentPage': activeBook?.entry.currentPage,
              'pageCount': activeBook?.book?.pageCount,
              'coverUrl': activeBook?.book?.coverUrl,
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.night,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14)],
          ),
          child: Row(
            children: [
              // The book being read, not a blank tile — same cover frame the
              // rest of the app uses, so a photographed cover shows and a
              // cover-less book still reads as itself (the typeset fallback).
              TypesetCover(
                title: title ?? '…',
                author: activeBook?.book?.authorNames,
                coverUrl: activeBook?.book?.coverUrl,
                width: 28,
                height: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)!.timerMiniBarLive(formatClock(elapsed)),
                      style: TextStyle(color: AppColors.gold, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: AppLocalizations.of(context)!.timerStop,
                child: GestureDetector(
                  onTap: () => quickStopSession(context, ref),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                        child: Center(
                          child: Container(width: 8, height: 8, color: AppColors.night),
                        ),
                      ),
                    ),
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

/// The oxblood add tile — one of the five equal slots, so its centre is the
/// exact screen centre. Deliberately NOT a FloatingActionButton (see the
/// class comment on [ShellScaffold]).
class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.oxblood,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add, size: 20, color: AppColors.paper),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
