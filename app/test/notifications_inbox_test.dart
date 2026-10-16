import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/notifications/notifications_providers.dart';
import 'package:kitabi/features/notifications/presentation/notification_bell.dart';
import 'package:kitabi/features/notifications/presentation/notifications_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The bell and its inbox (owner request, 14 Oct 2026): notifications kept
/// where the reader can find them again, new ones highlighted, opening one
/// marks it read, and "Clear all" empties it.

/// Written from `api/app/schemas/inbox.py` (InboxOut), not from the widget.
Map<String, dynamic> _body() => {
  'unread': 1,
  'items': [
    {
      'id': 'n-1',
      'type': 'borrow_ask',
      'title': 'Could they borrow it?',
      'body': 'Anu Thomas would like to borrow “Kaalam”',
      'data': {'type': 'borrow_ask', 'request_id': 'r-1'},
      'image_url': null,
      'created_at': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'read': false,
      'actor': {'id': 'u-anu', 'name': 'Anu Thomas', 'avatar_url': null},
    },
    {
      'id': 'n-2',
      'type': 'connection_accepted',
      'title': 'Connection accepted',
      'body': 'Ben accepted your connection on Kitabi',
      'data': {'type': 'connection_accepted'},
      'image_url': null,
      'created_at': '2026-10-01T10:00:00Z',
      'read': true,
      'actor': null,
    },
  ],
};

class _Api extends ApiClient {
  final marked = <String>[];
  var cleared = false;

  @override
  Future<void> markNotificationsRead(List<String> ids) async =>
      marked.addAll(ids);

  @override
  Future<void> clearNotifications() async => cleared = true;

  @override
  Future<Map<String, dynamic>> getNotifications() async => _body();

  @override
  Future<int> getUnreadNotifications() async => 0;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Widget child, List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  test('parses the server shape and tolerates a malformed row', () {
    final inbox = Inbox.fromJson({
      ..._body(),
      'items': [
        ...(_body()['items'] as List),
        {'no': 'id'},
      ],
    });
    expect(inbox.unread, 1);
    expect(inbox.items.map((i) => i.id), ['n-1', 'n-2']);
    expect(inbox.items.first.data['request_id'], 'r-1');
    expect(inbox.items.last.actorName, isNull);
  });

  test('relative times read like a letter, not a log', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 14, 18);
    expect(
      notificationWhen(l10n, now.subtract(const Duration(seconds: 20)), now),
      'Just now',
    );
    expect(
      notificationWhen(l10n, now.subtract(const Duration(minutes: 7)), now),
      '7m ago',
    );
    expect(
      notificationWhen(l10n, now.subtract(const Duration(hours: 3)), now),
      '3h ago',
    );
    expect(notificationWhen(l10n, DateTime(2026, 10, 13, 9), now), 'Yesterday');
    expect(notificationWhen(l10n, DateTime(2026, 10, 2, 9), now), 'Oct 2');
  });

  final unreadDot = find.byKey(const ValueKey('unread-dot'));

  testWidgets('new ones are highlighted; opening one marks it read', (t) async {
    final api = _Api();
    await t.pumpWidget(
      host(const NotificationsScreen(), [
        apiClientProvider.overrideWithValue(api),
      ]),
    );
    await t.pump();
    await t.pump();

    expect(
      find.text('Anu Thomas would like to borrow “Kaalam”'),
      findsOneWidget,
    );
    expect(find.text('5m ago'), findsOneWidget);
    expect(unreadDot, findsOneWidget, reason: 'only the unread one');

    await t.tap(find.text('Could they borrow it?'));
    await t.pump();
    expect(api.marked, ['n-1']);
    expect(unreadDot, findsNothing);
  });

  testWidgets('Clear all asks first, then empties the inbox', (t) async {
    final api = _Api();
    await t.pumpWidget(
      host(const NotificationsScreen(), [
        apiClientProvider.overrideWithValue(api),
      ]),
    );
    await t.pump();
    await t.pump();

    await t.tap(find.byTooltip('Clear all'));
    await t.pumpAndSettle();
    expect(find.text('Clear all notifications?'), findsOneWidget);
    await t.tap(find.text('Clear'));
    await t.pumpAndSettle();
    expect(api.cleared, isTrue);
  });

  Future<void> pumpBell(WidgetTester t, int count) async {
    await t.pumpWidget(
      host(const Scaffold(body: NotificationBell()), [
        unreadNotificationsProvider.overrideWith((ref) async => count),
      ]),
    );
    await t.pump();
    await t.pump();
  }

  testWidgets('the bell is quiet with nothing new', (t) async {
    await pumpBell(t, 0);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('the bell carries the number of new ones', (t) async {
    await pumpBell(t, 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('and stops counting at 9+', (t) async {
    await pumpBell(t, 12);
    expect(find.text('9+'), findsOneWidget);
  });
}
