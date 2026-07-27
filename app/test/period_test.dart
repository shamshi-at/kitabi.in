import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/insights/period.dart';

void main() {
  // Mon 27 Jul 2026 — a real Monday, so the week math has no slack to hide a
  // weekday-offset bug in.
  final now = DateTime(2026, 7, 27, 14, 30);

  group('rangeFor', () {
    test('today is midnight to midnight', () {
      final r = rangeFor(InsightsPeriod.today, now: now);
      expect(r.start, DateTime(2026, 7, 27));
      expect(r.end, DateTime(2026, 7, 28));
    });

    test('week starts Monday, regardless of what day "now" falls on', () {
      final onMonday = rangeFor(InsightsPeriod.week, now: DateTime(2026, 7, 27));
      final onSunday = rangeFor(InsightsPeriod.week, now: DateTime(2026, 8, 2));
      expect(onMonday.start, DateTime(2026, 7, 27));
      expect(onMonday.end, DateTime(2026, 8, 3));
      // Same week — Sunday is the last day of the week that started Monday.
      expect(onSunday.start, DateTime(2026, 7, 27));
    });

    test('month is calendar-aligned, including a December-to-January end', () {
      final r = rangeFor(InsightsPeriod.month, now: now);
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.end, DateTime(2026, 8, 1));

      final dec = rangeFor(InsightsPeriod.month, now: DateTime(2026, 12, 15));
      expect(dec.start, DateTime(2026, 12, 1));
      expect(dec.end, DateTime(2027, 1, 1));
    });

    test('year takes an explicit calendar year', () {
      final r = rangeFor(InsightsPeriod.year, now: now, year: 2026);
      expect(r.start, DateTime(2026, 1, 1));
      expect(r.end, DateTime(2027, 1, 1));

      final r2025 = rangeFor(InsightsPeriod.year, now: now, year: 2025);
      expect(r2025.start, DateTime(2025, 1, 1));
      expect(r2025.end, DateTime(2026, 1, 1));
    });

    test('a null year means all time, not "this year"', () {
      final allTime = rangeFor(InsightsPeriod.year, now: now, year: null);
      expect(allTime.start, DateTime(2000, 1, 1));
      expect(allTime.end, DateTime(2026, 7, 28));
      expect(allTime.contains(DateTime(2010, 1, 1)), isTrue);
    });

    test('3/6 months are trailing windows, not calendar quarters', () {
      final r3 = rangeFor(InsightsPeriod.threeMonths, now: now);
      expect(r3.end, DateTime(2026, 7, 27));
      expect(r3.start, DateTime(2026, 7, 27).subtract(const Duration(days: 90)));

      final r6 = rangeFor(InsightsPeriod.sixMonths, now: now);
      expect(r6.start, DateTime(2026, 7, 27).subtract(const Duration(days: 182)));
    });
  });

  group('previousRangeFor', () {
    test('today/week shift back by their own length with no gap', () {
      final today = rangeFor(InsightsPeriod.today, now: now);
      final prevToday = previousRangeFor(InsightsPeriod.today, today);
      expect(prevToday.end, today.start);
      expect(prevToday.start, DateTime(2026, 7, 26));

      final week = rangeFor(InsightsPeriod.week, now: now);
      final prevWeek = previousRangeFor(InsightsPeriod.week, week);
      expect(prevWeek.end, week.start);
      expect(prevWeek.start, DateTime(2026, 7, 20));
    });

    test('month compares against the real previous calendar month', () {
      final march = rangeFor(InsightsPeriod.month, now: DateTime(2026, 3, 10));
      final prev = previousRangeFor(InsightsPeriod.month, march);
      // Feb 2026 has 28 days — a fixed 30-day shift would get this wrong.
      expect(prev.start, DateTime(2026, 2, 1));
      expect(prev.end, DateTime(2026, 3, 1));
    });

    test('January compares against December of the previous year', () {
      final jan = rangeFor(InsightsPeriod.month, now: DateTime(2026, 1, 15));
      final prev = previousRangeFor(InsightsPeriod.month, jan);
      expect(prev.start, DateTime(2025, 12, 1));
      expect(prev.end, DateTime(2026, 1, 1));
    });

    test('year compares against the same window one calendar year earlier', () {
      final year = rangeFor(InsightsPeriod.year, now: now, year: 2026);
      final prev = previousRangeFor(InsightsPeriod.year, year);
      expect(prev.start, DateTime(2025, 1, 1));
      expect(prev.end, DateTime(2026, 1, 1));
    });

    test('3/6 months shift back by the same trailing length', () {
      final r3 = rangeFor(InsightsPeriod.threeMonths, now: now);
      final prev3 = previousRangeFor(InsightsPeriod.threeMonths, r3);
      expect(prev3.end, r3.start);
      expect(prev3.start, r3.start.subtract(r3.end.difference(r3.start)));
    });
  });
}
