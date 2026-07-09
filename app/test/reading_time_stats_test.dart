import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/reading_time_stats.dart';

ReadingSession _session(DateTime startedAt, int durationSeconds) {
  return ReadingSession(
    id: 'id-${startedAt.millisecondsSinceEpoch}',
    userId: 'u1',
    createdAt: startedAt,
    updatedAt: startedAt,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    libraryEntryId: 'le1',
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationSeconds)),
    durationSeconds: durationSeconds,
    pageStart: null,
    pageEnd: null,
  );
}

void main() {
  // A fixed "now" so the week-boundary math is deterministic: Wed 15 Jul 2026.
  final now = DateTime(2026, 7, 15, 21);
  final mondayThisWeek = DateTime(2026, 7, 13);

  test('buckets this week by day and totals this week vs last week', () {
    final sessions = [
      _session(mondayThisWeek.add(const Duration(hours: 20)), 600), // Mon this week
      _session(mondayThisWeek.add(const Duration(days: 2, hours: 21)), 1200), // Wed this week
      _session(mondayThisWeek.subtract(const Duration(days: 3)), 900), // last week
    ];

    final stats = computeReadingTimeStats(sessions, now: now);

    expect(stats.secondsByDayThisWeek[0], 600); // Monday
    expect(stats.secondsByDayThisWeek[2], 1200); // Wednesday
    expect(stats.secondsByDayThisWeek[1], 0);
    expect(stats.thisWeekSeconds, 1800);
    expect(stats.lastWeekSeconds, 900);
  });

  test('no narrative below the minimum-sessions threshold', () {
    final sessions = [
      _session(mondayThisWeek, 600),
      _session(mondayThisWeek.add(const Duration(days: 1)), 600),
    ];
    final stats = computeReadingTimeStats(sessions, now: now);
    expect(stats.busiestWeekday, isNull);
    expect(stats.busiestHour, isNull);
  });

  test('busiest weekday and hour once there is enough data', () {
    // Five sessions, three of them on Wednesday at 9pm — a real pattern.
    final sessions = [
      _session(DateTime(2026, 7, 1, 21), 1200), // Wed
      _session(DateTime(2026, 7, 8, 21), 1200), // Wed
      _session(DateTime(2026, 7, 15, 21), 1200), // Wed
      _session(DateTime(2026, 7, 6, 8), 300), // Mon morning
      _session(DateTime(2026, 7, 11, 12), 300), // Sat noon
    ];
    final stats = computeReadingTimeStats(sessions, now: now);
    expect(stats.busiestWeekday, DateTime.wednesday);
    expect(stats.busiestHour, 21);
  });

  test('deleted sessions are excluded', () {
    final deleted = _session(mondayThisWeek, 999);
    final sessions = [
      ReadingSession(
        id: deleted.id,
        userId: deleted.userId,
        createdAt: deleted.createdAt,
        updatedAt: deleted.updatedAt,
        deletedAt: now,
        syncStatus: deleted.syncStatus,
        lastSyncedAt: deleted.lastSyncedAt,
        serverSeq: deleted.serverSeq,
        libraryEntryId: deleted.libraryEntryId,
        startedAt: deleted.startedAt,
        endedAt: deleted.endedAt,
        durationSeconds: deleted.durationSeconds,
        pageStart: deleted.pageStart,
        pageEnd: deleted.pageEnd,
      ),
    ];
    final stats = computeReadingTimeStats(sessions, now: now);
    expect(stats.thisWeekSeconds, 0);
  });
}
