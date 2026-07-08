import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/connections/connections_providers.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_status_bar.dart';
import 'app_router.dart';

/// The persistent bottom-nav shell (S3 mockup): Home · Library · [+] ·
/// Lending · Insights. The four real tabs map to the [StatefulNavigationShell]
/// branches; "+" is an action (opens the add flow), not a tab.
///
/// The "+" is a true [FloatingActionButton] docked via
/// [FloatingActionButtonLocation.centerDocked] on a notched [BottomAppBar] —
/// Flutter computes its horizontal position from the Scaffold's own width, so
/// it sits at the *exact* pixel center regardless of how the four nav items
/// are laid out (a plain 5th-of-N row slot only centers when the item count
/// is odd and every slot is equal width — fragile the moment a 6th item, like
/// the search shortcut once did, gets added). The docked/notched combo also
/// gives it the raised, cut-out look of a proper primary action instead of
/// just another row icon.
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
          ],
        ),
      ),
      // Scan-first (docs/screen-design.md): the FAB opens the camera directly —
      // one tap to the main add path. Search / manual add stay one tap away
      // via the scanner's fallback buttons.
      floatingActionButton: FloatingActionButton(
        onPressed: () { Haptics.selection(); context.push(Routes.catalogScan); },
        backgroundColor: AppColors.oxblood,
        foregroundColor: AppColors.paper,
        tooltip: l10n.navAdd,
        elevation: 3,
        child: Icon(Icons.add, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.card,
        shape: CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 8,
        shadowColor: AppColors.ink.withValues(alpha: 0.16),
        padding: EdgeInsets.zero,
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
                  onTap: () { Haptics.selection(); navigationShell.goBranch(0); },
                ),
                _NavItem(
                  icon: Icons.auto_stories_outlined,
                  activeIcon: Icons.auto_stories,
                  label: l10n.navLibrary,
                  selected: index == 1,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(1); },
                ),
                // Clearance for the notch — the FAB floats above this gap; its
                // own label sits low enough to clear the notch's curve.
                SizedBox(
                  width: 64,
                  child: Padding(
                    padding: EdgeInsets.only(top: 38),
                    child: Text(
                      l10n.navAdd,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  icon: Icons.swap_horiz,
                  activeIcon: Icons.swap_horiz,
                  label: l10n.navLending,
                  selected: index == 2,
                  badgeCount: incoming,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(2); },
                ),
                _NavItem(
                  icon: Icons.donut_large_outlined,
                  activeIcon: Icons.donut_large,
                  label: l10n.navInsights,
                  selected: index == 3,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(3); },
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

