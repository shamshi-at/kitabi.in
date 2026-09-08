import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../period.dart';

/// The scrollable chip row above the flagship card — Today · Week · Month ·
/// 3 months · 6 months · Year. Horizontally scrolling rather than shrinking
/// to fit is deliberate: six labels at a size worth reading don't fit a phone
/// width, and a clipped last chip is the same "there's more" affordance the
/// app already uses for overflowing ticker text.
///
/// Year and Month each carry their own sub-choice, and carry it the same way:
/// a plain tap on the chip body means *this* year / *this* month, the dropdown
/// arrow opens the others — [years] being years that hold finished books,
/// [months] months that hold any reading at all. [selectedYear] is read only
/// while [selected] is [InsightsPeriod.year], [selectedMonth] only while it is
/// [InsightsPeriod.month].
///
/// Month got its arrow on 8 Sep 2026: the almanac could answer "how was 2025?"
/// and not "how was August?", which is the question a reader who has just
/// shared a month card asks next.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.selectedYear,
    required this.onYearSelected,
    required this.thisYear,
    required this.years,
    required this.selectedMonth,
    required this.onMonthSelected,
    required this.months,
  });

  final InsightsPeriod selected;
  final ValueChanged<InsightsPeriod> onSelected;
  final int? selectedYear;
  final ValueChanged<int?> onYearSelected;
  final int thisYear;

  /// Years with data, newest first — always contains [thisYear].
  final List<int> years;

  /// The first of the month being shown; null means this month.
  final DateTime? selectedMonth;
  final ValueChanged<DateTime?> onMonthSelected;

  /// Months with data, newest first, as first-of-month dates.
  final List<DateTime> months;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chips = <(InsightsPeriod, String)>[
      (InsightsPeriod.today, l10n.insightsPeriodToday),
      (InsightsPeriod.week, l10n.insightsPeriodWeek),
    ];
    final trailingChips = <(InsightsPeriod, String)>[
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
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _MonthChip(
              label: l10n.insightsPeriodMonth,
              selected: selected == InsightsPeriod.month,
              selectedMonth: selectedMonth,
              months: months,
              onChanged: (month) {
                onMonthSelected(month);
                onSelected(InsightsPeriod.month);
              },
            ),
          ),
          for (final (period, label) in trailingChips)
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

/// How a month reads in the chip and its menu: "August" inside this year,
/// "Aug 2025" outside it — the year is only worth the width when it isn't the
/// obvious one.
String monthChipLabel(DateTime month, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return month.year == n.year
      ? DateFormat.MMMM().format(month)
      : DateFormat.yMMM().format(month);
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

/// The Month chip: the body is a one-tap "this month" door; only the arrow
/// opens the menu of months that hold reading. Same shape as [_YearChip] on
/// purpose — two sub-choices that behave differently would be two things to
/// learn.
class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.label,
    required this.selected,
    required this.selectedMonth,
    required this.months,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final DateTime? selectedMonth;
  final List<DateTime> months;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = selected && selectedMonth != null ? monthChipLabel(selectedMonth!) : label;
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
              onTap: () => onChanged(null),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 7, 4, 7),
                child: Text(
                  text,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ),
            PopupMenuButton<(DateTime,)>(
              // Wrapped in a record for the same reason the year menu is: a
              // bare value that could be null is dropped by onSelected.
              tooltip: label,
              onSelected: (choice) => onChanged(choice.$1),
              itemBuilder: (context) => [
                for (final month in months)
                  PopupMenuItem(value: (month,), child: Text(monthChipLabel(month))),
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
