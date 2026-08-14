import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/notifications/push_service.dart';
import 'package:kitabi/core/router/app_router.dart';

/// Where a tapped notification lands. Pulled out of the Firebase listener for
/// the same reason `readingTimerRouteFor` was: the rule is the whole feature,
/// and it cannot be tested through the plugin.
///
/// Owner report (14 Aug 2026): tapping the reading notification opened the
/// connections inbox. Everything that wasn't a lending push fell through to
/// connections, so the default was quietly deciding where most taps went.
void main() {
  test('a reading push opens that sitting on the timer', () {
    expect(
      pushTapRoute({'type': 'reading_started', 'library_entry_id': 'le-42'}),
      '/reading-timer/le-42',
    );
  });

  test('a reading push with no entry id lands on home, not on the timer', () {
    // Better a screen that makes sense than a route built from an empty id.
    expect(pushTapRoute({'type': 'reading_started'}), Routes.home);
    expect(pushTapRoute({'type': 'reading_started', 'library_entry_id': ''}), Routes.home);
  });

  test('lending pushes still open the ledger', () {
    for (final type in ['lend_new', 'lend_returned', 'lend_reminder']) {
      expect(pushTapRoute({'type': type}), Routes.lendingLedger, reason: type);
    }
  });

  test('connection pushes still open the inbox', () {
    expect(pushTapRoute({'type': 'connection_request'}), Routes.connections);
    expect(pushTapRoute({'type': 'connection_accepted'}), Routes.connections);
  });

  test('an unknown type goes home rather than somewhere unrelated', () {
    // The bug in one line: an unhandled type must not inherit another
    // feature's screen just because it was the last branch written.
    expect(pushTapRoute({'type': 'something_new'}), Routes.home);
    expect(pushTapRoute(const {}), Routes.home);
  });
}
