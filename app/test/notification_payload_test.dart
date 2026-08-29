import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/notifications/notification_payload.dart';
import 'package:kitabi/core/router/app_router.dart';

/// Local notifications carry one opaque payload string, and it used to be an
/// unqualified library-entry id — so the tap handler had exactly one
/// destination it could name. The lending due-date reminders were scheduled
/// with no payload at all for that reason, and tapping one read null, returned,
/// and left the app on whatever screen it had been on (owner report,
/// 29 Aug 2026).
const _entryId = '11111111-1111-1111-1111-111111111111';
const _recordId = '22222222-2222-2222-2222-222222222222';
const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';

void main() {
  group('the payload round-trips', () {
    test('every target survives being written and read back', () {
      for (final target in NotificationTarget.values) {
        final parsed = parseNotificationPayload(notificationPayload(target, 'x/y'));
        expect(parsed?.target, target);
        expect(parsed?.id, 'x/y', reason: 'an id may contain a slash, never a colon');
      }
    });

    test('nothing to route on reads as nothing', () {
      expect(parseNotificationPayload(null), isNull);
      expect(parseNotificationPayload(''), isNull);
      expect(parseNotificationPayload('   '), isNull);
      expect(parseNotificationPayload('lending:'), isNull);
    });

    /// A check-in scheduled before this change is sitting in the OS's own
    /// queue on real devices and may not be delivered for hours.
    test('an unqualified payload is still the reading timer', () {
      final parsed = parseNotificationPayload(_entryId);
      expect(parsed?.target, NotificationTarget.readingTimer);
      expect(parsed?.id, _entryId);
    });
  });

  group('where a tap lands', () {
    test('a due-date reminder opens the ledger', () {
      expect(
        localNotificationRoute(
          notificationPayload(NotificationTarget.lending, _recordId),
        ),
        Routes.lendingLedger,
      );
    });

    test('the running clock opens its own sitting', () {
      expect(
        localNotificationRoute(
          notificationPayload(NotificationTarget.readingTimer, _entryId),
        ),
        Routes.readingTimerPath(_entryId),
      );
    });

    /// The sitting is over by the time this is posted, so the timer is the one
    /// screen it must not open.
    test('"stopped while you were away" opens the book, not the timer', () {
      expect(
        localNotificationRoute(
          notificationPayload(NotificationTarget.book, '$_workId/$_editionId'),
        ),
        Routes.bookDetailPath(_workId, _editionId),
      );
    });

    test('a payload naming nothing openable opens nothing', () {
      expect(localNotificationRoute(null), isNull);
      // A book whose pair couldn't be resolved — better to stay put than to
      // build a location no route matches.
      expect(
        localNotificationRoute(notificationPayload(NotificationTarget.book, _workId)),
        isNull,
      );
    });
  });
}
