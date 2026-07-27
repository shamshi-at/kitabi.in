import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One tab in a [SegTabBar]. [count] renders as a softened " · N" suffix; a
/// label that already carries its count can pass null.
class SegTabItem {
  const SegTabItem(this.label, {this.count});

  final String label;
  final int? count;
}

/// The app's one segmented control — the pill-on-paperDeep pattern the public
/// profile introduced, promoted to `core/widgets/` so the lending ledger (and
/// any future tabbed screen) uses the same segments instead of a Material
/// underline TabBar (28 Jul 2026; "two segmented-control implementations"
/// finding). Casing is applied here, in code, so labels stay sentence case in
/// the arb for future locales.
class SegTabBar extends StatelessWidget {
  const SegTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<SegTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paperDeep,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          for (final (i, tab) in tabs.indexed)
            _SegTab(
              label: tab.label,
              count: tab.count,
              active: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          elevation: 0,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: active ? AppColors.oxblood : AppColors.inkSoft,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      ' · $count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: (active ? AppColors.oxblood : AppColors.inkSoft)
                            .withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
