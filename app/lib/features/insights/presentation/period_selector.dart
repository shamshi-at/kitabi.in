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
/// [selectedYear] is only read while [selected] is [InsightsPeriod.year], and
/// picking any option there both selects the period and sets the year.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.selectedYear,
    required this.onYearSelected,
    required this.thisYear,
  });

  final InsightsPeriod selected;
  final ValueChanged<InsightsPeriod> onSelected;
  final int? selectedYear;
  final ValueChanged<int?> onYearSelected;
  final int thisYear;

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
          for (final (period, label) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PeriodChip(
                label: label,
                selected: selected == period,
                onTap: () => onSelected(period),
              ),
            ),
          _YearChip(
            label: l10n.insightsPeriodYear,
            allTimeLabel: l10n.insightsAllTime,
            selected: selected == InsightsPeriod.year,
            selectedYear: selectedYear,
            thisYear: thisYear,
            onChanged: (year) {
              onYearSelected(year);
              onSelected(InsightsPeriod.year);
            },
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.paper : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.label,
    required this.allTimeLabel,
    required this.selected,
    required this.selectedYear,
    required this.thisYear,
    required this.onChanged,
  });

  final String label;
  final String allTimeLabel;
  final bool selected;
  final int? selectedYear;
  final int thisYear;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = selected
        ? (selectedYear == null ? allTimeLabel : '$selectedYear')
        : label;
    return PopupMenuButton<int?>(
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: thisYear, child: Text('$thisYear')),
        PopupMenuItem(value: thisYear - 1, child: Text('${thisYear - 1}')),
        PopupMenuItem(value: null, child: Text(allTimeLabel)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.paper : AppColors.ink,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.arrow_drop_down,
              size: 15,
              color: selected ? AppColors.paper : AppColors.ink,
            ),
          ],
        ),
      ),
    );
  }
}
