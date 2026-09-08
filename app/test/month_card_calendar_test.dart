import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/insights/period.dart';
import 'package:kitabi/features/insights/period_summary.dart';
import 'package:kitabi/features/share/presentation/period_card_viz.dart';

/// The month share card must show the whole month.
///
/// It used to crop every trailing week that held nothing but future days, so a
/// card sent on the 8th stopped on the 12th and read to the recipient as a
/// picture that had been cut off (owner report, 8 Sep 2026, against Apple
/// Books' card). Asserted on the pure rule rather than on the rendering,
/// because the host's test font decides the card's every other dimension and a
/// widget test that merely renders looks plausible with the crop in place.
void main() {
  List<CalendarCell> septemberOnThe8th() => computePeriodSummary(
        period: InsightsPeriod.month,
        range: rangeFor(InsightsPeriod.month, now: DateTime(2026, 9, 8)),
        sessions: const [],
        hits: const [],
        ratingsByWorkId: const {},
        now: DateTime(2026, 9, 8),
      ).calendarCells!;

  test('a month card sent on the 8th still draws every week of the month', () {
    final weeks = heatWeeks(septemberOnThe8th());

    // Sept 2026 starts on a Tuesday; Sunday-first that is 5 weeks.
    expect(weeks, hasLength(5));
    expect(weeks.every((w) => w.length == 7), isTrue, reason: 'a week is seven days');

    final days = [
      for (final week in weeks)
        for (final cell in week)
          if (cell.date != null) cell.date!.day,
    ];
    expect(days, List.generate(30, (i) => i + 1));
    expect(days.last, 30, reason: 'the 30th is exactly what the crop used to eat');
  });

  test('most of the month reads as future, not as missing', () {
    final cells = septemberOnThe8th().where((c) => c.date != null);
    expect(cells.where((c) => c.isFuture).length, 22); // the 9th to the 30th
    expect(cells.where((c) => !c.isFuture).length, 8);
  });
}
