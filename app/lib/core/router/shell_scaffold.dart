import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../theme/app_theme.dart';
import '../widgets/sync_status_bar.dart';
import 'app_router.dart';

/// The persistent bottom-nav shell (S3 mockup): Home · Library · [+] · Lending
/// · Insights. The centre "+" is an action (opens the add flow), not a tab, so
/// the four real tabs map to the [StatefulNavigationShell] branches and "+"
/// pushes on top.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final index = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Column(
        children: [
          const SyncStatusBar(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
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
                _AddButton(label: l10n.navAdd, onTap: () => context.push(Routes.catalogSearch)),
                _NavItem(
                  icon: Icons.swap_horiz,
                  activeIcon: Icons.swap_horiz,
                  label: l10n.navLending,
                  selected: index == 2,
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.oxblood : AppColors.inkSoft;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 2),
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
              child: const Icon(Icons.add, size: 20, color: AppColors.paper),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
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
