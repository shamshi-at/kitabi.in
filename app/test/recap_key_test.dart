import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/core/share_links.dart';
import 'package:kitabi/features/insights/period.dart';

/// The recap key grammar — the app's half.
///
/// **The other half is `api/app/services/recap_service.py`, and
/// `api/tests/test_recap_key.py` holds the same table.** Keep them in step: a
/// key this file emits and that parser rejects is a share link that 404s, and a
/// rule with two implementations is exactly how the app and the app-site
/// association came to disagree about which URLs Kitabi owns (1 Sep 2026).
void main() {
  // Tue 8 Sep 2026 — the day the report that started this came in.
  final now = DateTime(2026, 9, 8, 21, 40);

  ({InsightsPeriod period, PeriodRange range, int? year}) window(
    InsightsPeriod period, {
    int? year,
    DateTime? month,
  }) =>
      (period: period, range: rangeFor(period, now: now, year: year, month: month), year: year);

  test('every window has a key, and it is the one the API parses', () {
    final cases = <String, ({InsightsPeriod period, PeriodRange range, int? year})>{
      '2026-09-08': window(InsightsPeriod.today),
      // The week containing Tue 8 Sep 2026 is ISO week 37.
      '2026-w37': window(InsightsPeriod.week),
      '2026-09': window(InsightsPeriod.month),
      '2026-08': window(InsightsPeriod.month, month: DateTime(2026, 8, 17)),
      '2026': window(InsightsPeriod.year, year: 2026),
      '2025': window(InsightsPeriod.year, year: 2025),
      'all': window(InsightsPeriod.year),
      // Trailing windows end today and are named by that end.
      '90d-2026-09-08': window(InsightsPeriod.threeMonths),
      '182d-2026-09-08': window(InsightsPeriod.sixMonths),
    };
    for (final entry in cases.entries) {
      final w = entry.value;
      expect(recapKeyFor(w.period, w.range, year: w.year), entry.key);
    }
  });

  test('the week key uses the ISO week-numbering year, not the calendar one', () {
    // 1 Jan 2027 is a Friday: ISO week 53 of *2026*. A key of "2027-w53" would
    // name a week that does not exist.
    expect(isoWeekOf(DateTime(2027, 1, 1)), (2026, 53));
    // ...and 31 Dec 2029 is a Monday, which belongs to week 1 of 2030.
    expect(isoWeekOf(DateTime(2029, 12, 31)), (2030, 1));
    // An ordinary mid-year week, for a sanity anchor.
    expect(isoWeekOf(DateTime(2026, 9, 7)), (2026, 37));
  });

  test('the URL is the handle and the key, and nothing else', () {
    expect(
      recapShareUrl('shamshi', '2026-09'),
      'https://kitabi.in/reader/shamshi/recap/2026-09',
    );
    // A handle is [a-z0-9_] in practice, but the URL builder must not be the
    // place that assumes it.
    expect(recapShareUrl('a b', '2026'), 'https://kitabi.in/reader/a%20b/recap/2026');
  });

  test('a recap link is deliberately NOT a link this app claims', () {
    // The recipient of a recap is a stranger — the point is that they land on
    // a page they can read, not on a store listing. So `/reader/` is absent
    // from apple-app-site-association and from the Android manifest, and the
    // router must agree with both: claiming a URL pattern is a promise the app
    // has to keep, and the three copies of that decision disagreeing is what
    // sent a slug link to "no routes for location" (1 Sep 2026).
    expect(
      externalRouteFor(Uri.parse('https://kitabi.in/reader/shamshi/recap/2026-09')),
      isNull,
    );
    // ...while the links it *does* claim still resolve, so this is a statement
    // about /reader/ and not a broken rule.
    expect(externalRouteFor(Uri.parse('https://kitabi.in/book/chemmeen')), '/b/chemmeen');
  });
}
