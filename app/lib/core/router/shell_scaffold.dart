import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/connections/connections_providers.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_status_bar.dart';
import 'app_router.dart';

/// The persistent bottom-nav shell (S3 mockup): Home · Library · Search · [+]
/// · Lending · Insights. The centre "+" is an action (opens the add flow) and
/// Search pushes the global search — neither is a tab, so the four real tabs
/// map to the [StatefulNavigationShell] branches. The Lending item carries a
/// badge when connection requests await approval (the first hop of the
/// notification chain: footer → ledger header → connections inbox).
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
                  onTap: () { Haptics.selection(); navigationShell.goBranch(0); },
                ),
                _NavItem(
                  icon: Icons.auto_stories_outlined,
                  activeIcon: Icons.auto_stories,
                  label: l10n.navLibrary,
                  selected: index == 1,
                  onTap: () { Haptics.selection(); navigationShell.goBranch(1); },
                ),
                // Global search from anywhere (S4) — pushed above the shell,
                // like "+", so the current tab keeps its state underneath.
                _NavItem(
                  icon: Icons.search,
                  activeIcon: Icons.search,
                  label: l10n.navSearch,
                  selected: false,
                  onTap: () { Haptics.selection(); context.push(Routes.catalogSearch); },
                ),
                // Scan-first (docs/screen-design.md): the FAB opens the camera
                // directly — one tap to the main add path. Search / manual add
                // stay one tap away via the scanner's fallback buttons.
                _AddButton(label: l10n.navAdd, onTap: () => context.push(Routes.catalogScan)),
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
