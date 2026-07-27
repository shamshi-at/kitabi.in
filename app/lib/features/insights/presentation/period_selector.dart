import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../period.dart';

/// The scrollable chip row above the flagship card — Today · Week · Month ·
/// 3 months · 6 months · Year. Horizontally scrolling rather than shrinking
/// to fit is deliberate: six labels at a size worth reading don't fit a phone
/// width, and a clipped last chip is the same "there's more" affordance the
/// app already uses for overflowing ticker text.
///
/// Year carries its own sub-choice (a specific calendar year, or all time) —
/// [selectedYear] is only read while [selected] is [InsightsPeriod.year]. A
/// plain tap on the chip selects *this* year immediately; the dropdown arrow
/// opens the other choices, built from [years] (years that actually hold
/// finished books) plus all time.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.selectedYear,
    required this.onYearSelected,
    required this.thisYear,
    required this.years,
  });

  final InsightsPeriod selected;
  final ValueChanged<InsightsPeriod> onSelected;
  final int? selectedYear;
  final ValueChanged<int?> onYearSelected;
  final int thisYear;

  /// Years with data, newest first — always contains [thisYear].
  final List<int> years;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <(InsightsPeriod, String)>[
      (InsightsPeriod.today, l10n.insightsPeriodToday),
      (InsightsPeriod.week, l10n.insightsPeriodWeek),
      (InsightsPeriod.month, l10n.insightsPeriodMonth),
      (InsightsPeriod.threeMonths, l10n.insightsPeriod3Months),
      (InsightsPeriod.sixMonths, l10n.insightsPeriod6Months),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Year leads the row — it's the scope-setting chip (2026 / 2025 /
          // all time), so it reads first even though Today is what's
          // selected by default.
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _YearChip(
              label: l10n.insightsPeriodYear,
              allTimeLabel: l10n.insightsAllTime,
              selected: selected == InsightsPeriod.year,
              selectedYear: selectedYear,
              thisYear: thisYear,
              years: years,
              onChanged: (year) {
                onYearSelected(year);
                onSelected(InsightsPeriod.year);
              },
            ),
          ),
          for (final (period, label) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PeriodChip(
                label: label,
                selected: selected == period,
                onTap: () => onSelected(period),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.paper : AppColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Year chip: the body is a one-tap "this year" door; only the arrow
/// opens the menu of other years (built from years with data) and all time.
class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.label,
    required this.allTimeLabel,
    required this.selected,
    required this.selectedYear,
    required this.thisYear,
    required this.years,
    required this.onChanged,
  });

  final String label;
  final String allTimeLabel;
  final bool selected;
  final int? selectedYear;
  final int thisYear;
  final List<int> years;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = selected
        ? (selectedYear == null ? allTimeLabel : '$selectedYear')
        : label;
    final fg = selected ? AppColors.paper : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => onChanged(thisYear),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 7, 4, 7),
                child: Text(
                  text,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ),
            PopupMenuButton<(int?,)>(
              // A record wrapper so `null` (all time) survives as a real menu
              // value — PopupMenuButton drops a plain null onSelected.
              tooltip: label,
              onSelected: (choice) => onChanged(choice.$1),
              itemBuilder: (context) => [
                for (final y in years) PopupMenuItem(value: (y,), child: Text('$y')),
                PopupMenuItem(value: const (null,), child: Text(allTimeLabel)),
              ],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 7, 8, 7),
                child: Icon(Icons.arrow_drop_down, size: 15, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
