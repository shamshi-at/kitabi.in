import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/insights/period.dart';
import 'package:kitabi/features/insights/presentation/period_selector.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The Month chip's sub-choice (8 Sep 2026). Asserted through the real chip
/// row rather than the screen: the rule under test is "the arrow picks a month
/// and selects the month window", and a screen test would drag in a database
/// to prove a menu.
void main() {
  testWidgets('the month arrow picks another month and switches to the month window',
      (tester) async {
    InsightsPeriod? period;
    Object? month = 'untouched';

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PeriodSelector(
          selected: InsightsPeriod.today,
          onSelected: (p) => period = p,
          selectedYear: 2026,
          onYearSelected: (_) {},
          thisYear: 2026,
          years: const [2026],
          selectedMonth: null,
          onMonthSelected: (m) => month = m,
          months: [DateTime(2026, 9), DateTime(2026, 8), DateTime(2025, 12)],
        ),
      ),
    ));

    // The chip reads "Month" until one is chosen; the menu names them.
    expect(find.text('Month'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_drop_down).last);
    await tester.pumpAndSettle();

    // Inside this year the month stands alone; outside it, it carries the year.
    expect(find.text('August'), findsOneWidget);
    expect(find.text('Dec 2025'), findsOneWidget);

    await tester.tap(find.text('August'));
    await tester.pumpAndSettle();

    expect(month, DateTime(2026, 8));
    expect(period, InsightsPeriod.month,
        reason: 'picking a month must also select the month window');
  });

  testWidgets('tapping the chip body means this month', (tester) async {
    Object? month = 'untouched';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PeriodSelector(
          selected: InsightsPeriod.month,
          onSelected: (_) {},
          selectedYear: 2026,
          onYearSelected: (_) {},
          thisYear: 2026,
          years: const [2026],
          selectedMonth: DateTime(2026, 8),
          onMonthSelected: (m) => month = m,
          months: [DateTime(2026, 9), DateTime(2026, 8)],
        ),
      ),
    ));

    // A selected month is named on the chip.
    expect(find.text('August'), findsOneWidget);
    await tester.tap(find.text('August'));
    await tester.pump();
    expect(month, isNull, reason: 'null is "this month", the same way the year chip works');
  });

  test('a month outside this year carries its year', () {
    final now = DateTime(2026, 9, 8);
    expect(monthChipLabel(DateTime(2026, 8), now: now), 'August');
    expect(monthChipLabel(DateTime(2025, 12), now: now), 'Dec 2025');
  });
}
