import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// Owner report, 26 Jul 2026: **"Even though I pressed 'Yes, Still reading' in
/// the notification, my timer got stopped."**
///
/// Answering Yes re-armed the check-in notification and the workmanager
/// enforcement task, but nothing recorded the answer — so the *in-app* safety
/// net, which measures a sitting's age itself and runs on every tick of any
/// live surface, still stopped it at start + 90 minutes. Opening the timer was
/// enough to trigger it, which is exactly how it was found.
void main() {
  final started = DateTime(2026, 7, 26, 9);
  // The reader's interval is a parameter now (Profile setting, 26 Aug 2026);
  // these policy tests pin the shape with an explicit 60m so the arithmetic
  // stays readable, and the delay-of-record tests below cover the default.
  const delay = Duration(minutes: 60);
  final deadline = started.add(delay + readingCheckInGrace);

  group('the deadline', () {
    test('is delay + grace from the start when nothing was confirmed', () {
      expect(
        readingSessionDeadline(startedAt: started, checkInDelay: delay),
        started.add(const Duration(minutes: 90)),
      );
    });

    test('moves to delay + grace after the reader said they were still reading', () {
      final confirmed = started.add(const Duration(minutes: 58));
      expect(
        readingSessionDeadline(
            startedAt: started, confirmedAt: confirmed, checkInDelay: delay),
        confirmed.add(const Duration(minutes: 90)),
      );
    });

    test('never moves backwards on a stale confirmation from a past sitting', () {
      final stale = started.subtract(const Duration(hours: 5));
      expect(
        readingSessionDeadline(startedAt: started, confirmedAt: stale, checkInDelay: delay),
        deadline,
      );
    });

    test('a longer per-reader interval moves the deadline with it', () {
      expect(
        readingSessionDeadline(
            startedAt: started, checkInDelay: const Duration(minutes: 240)),
        started.add(const Duration(minutes: 270)),
      );
    });
  });

  group('overdue', () {
    test('a sitting is overdue once the deadline passes', () {
      expect(
        readingSessionOverdue(startedAt: started, now: deadline, checkInDelay: delay),
        isTrue,
      );
      expect(
        readingSessionOverdue(
            startedAt: started,
            now: deadline.subtract(const Duration(minutes: 1)),
            checkInDelay: delay),
        isFalse,
      );
    });

    test('a confirmed sitting is NOT overdue at the original deadline', () {
      // The reported bug, in one assertion: Yes at 58 minutes, and at 90
      // minutes the sitting must still be running.
      final confirmed = started.add(const Duration(minutes: 58));
      expect(
        readingSessionOverdue(
          startedAt: started,
          confirmedAt: confirmed,
          now: deadline,
          checkInDelay: delay,
        ),
        isFalse,
      );
      // ...but it is not immortal either.
      expect(
        readingSessionOverdue(
          startedAt: started,
          confirmedAt: confirmed,
          now: confirmed.add(const Duration(minutes: 91)),
          checkInDelay: delay,
        ),
        isTrue,
      );
    });
  });

  group('the delay of record', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('defaults to 2 hours when nothing is stored', () async {
      expect(await readingCheckInDelayOf(db), const Duration(minutes: 120));
    });

    test('honours a stored choice', () async {
      await db.keyValuesDao.setValue(readingCheckInDelayKey, '240');
      expect(await readingCheckInDelayOf(db), const Duration(minutes: 240));
    });

    test('an unoffered or corrupt value falls back to the default', () async {
      // A corrupt value silently meaning "never check in" is exactly the
      // failure the fallback exists to prevent.
      await db.keyValuesDao.setValue(readingCheckInDelayKey, '999999');
      expect(await readingCheckInDelayOf(db), const Duration(minutes: 120));
      await db.keyValuesDao.setValue(readingCheckInDelayKey, 'soon');
      expect(await readingCheckInDelayOf(db), const Duration(minutes: 120));
    });
  });

  group('the recorded answer', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a new sitting never inherits the previous one\'s confirmation', () async {
      await db.keyValuesDao.setValue(
        activeSessionConfirmedKey,
        DateTime(2026, 7, 26, 8).toIso8601String(),
      );

      await container.read(activeSessionProvider.notifier).start('entry-1');

      expect(await db.keyValuesDao.getValue(activeSessionConfirmedKey), isNull,
          reason: 'a fresh sitting starts unconfirmed');
    });
  });
}
