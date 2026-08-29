import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/notifications/notification_payload.dart';
import 'package:kitabi/core/notifications/reading_live_activity.dart';
import 'package:kitabi/core/router/app_router.dart';

/// The channel flutter_local_notifications itself talks over — asserting on it
/// is how we know an *ongoing chronometer* notification was posted rather than
/// an ordinary one. The three flags below are the whole Android feature.
const _pluginChannel = MethodChannel('dexterous.com/flutter/local_notifications');
const _activityChannel = MethodChannel('in.kitabi.kitabi/reading_activity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final activityCalls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];

  setUp(() {
    activityCalls.clear();
    pluginCalls.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_activityChannel, (call) async {
      activityCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      pluginCalls.add(call);
      // `initialize` and the permission request are typed `bool` on the plugin
      // side — handing them null makes the *setup* throw before the call we
      // actually care about is ever made.
      return call.method == 'initialize' ||
              call.method == 'requestNotificationsPermission' ||
              call.method == 'requestPermissions'
          ? true
          : null;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_activityChannel, null);
    messenger.setMockMethodCallHandler(_pluginChannel, null);
  });

  final startedAt = DateTime.fromMillisecondsSinceEpoch(1750000000000);

  ReadingLiveActivity subject(TargetPlatform platform) =>
      ReadingLiveActivity(platform: platform);

  group('iOS', () {
    test('starts a Live Activity with the book and the moment reading began', () async {
      await subject(TargetPlatform.iOS).start(
        libraryEntryId: 'le1',
        title: 'The Covenant of Water',
        author: 'Abraham Verghese',
        startedAt: startedAt,
        currentPage: 302,
        pageCount: 724,
      );

      expect(activityCalls, hasLength(1));
      expect(activityCalls.single.method, 'start');
      final args = activityCalls.single.arguments as Map;
      expect(args['title'], 'The Covenant of Water');
      expect(args['author'], 'Abraham Verghese');
      // Seconds, not milliseconds — Swift reads it as a `timeIntervalSince1970`.
      expect(args['startedAt'], 1750000000);
      expect(args['currentPage'], 302);
      expect(args['pageCount'], 724);
      // Never the notification path on iOS.
      expect(pluginCalls, isEmpty);
    });

    test('update sends only what can change, and end takes no arguments', () async {
      final live = subject(TargetPlatform.iOS);
      await live.update(
        libraryEntryId: 'le1',
        title: 'X',
        startedAt: startedAt,
        currentPage: 310,
        pageCount: 724,
      );
      await live.end();

      expect(activityCalls.map((c) => c.method), ['update', 'end']);
      expect((activityCalls.first.arguments as Map)['currentPage'], 310);
    });

    test('a channel that throws is silence, never a failed sitting', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_activityChannel, (call) async {
        throw PlatformException(code: 'unavailable');
      });

      // The contract the whole class rests on: this must not throw.
      await expectLater(
        subject(TargetPlatform.iOS)
            .start(libraryEntryId: 'le1', title: 'X', startedAt: startedAt),
        completes,
      );
    });
  });

  group('Android', () {
    // The notifications plugin picks its own platform implementation from
    // `defaultTargetPlatform` *and* from whichever platform class registered
    // itself — on a macOS test host neither is Android, so `show` silently
    // no-ops. Both have to be told, or this whole group tests nothing.
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      FlutterLocalNotificationsPlatform.instance =
          AndroidFlutterLocalNotificationsPlugin();
    });
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('posts an ongoing notification the system ticks itself', () async {
      await subject(TargetPlatform.android).start(
        libraryEntryId: 'le1',
        title: 'The Covenant of Water',
        startedAt: startedAt,
        currentPage: 302,
        pageCount: 724,
      );

      final show = pluginCalls.firstWhere((c) => c.method == 'show');
      final args = show.arguments as Map;
      expect(args['id'], ReadingLiveActivity.notificationId);
      expect(args['title'], 'The Covenant of Water');
      expect(args['body'], 'p. 302 of 724');
      // Tapping the body lands on this book's timer — same payload convention
      // as the check-in notification, now qualified by what it is *about* so
      // the other families of local notification can name a screen too.
      expect(args['payload'],
          notificationPayload(NotificationTarget.readingTimer, 'le1'));
      expect(localNotificationRoute(args['payload'] as String),
          Routes.readingTimerPath('le1'));

      final android = args['platformSpecifics'] as Map;
      // The three flags that make it a live clock rather than a dead label.
      expect(android['ongoing'], isTrue);
      expect(android['usesChronometer'], isTrue);
      expect(android['when'], startedAt.millisecondsSinceEpoch);
      // Readable on a locked screen, and never buzzing. Importance has to be
      // *default*, not low: Android collapses low-importance notifications
      // into a silent dot on the lock screen, hiding the very clock this
      // exists to show (found on the emulator, 26 Jul 2026).
      expect(android['visibility'], 1); // NotificationVisibility.public
      expect(android['importance'], 3); // Importance.defaultImportance
      expect(android['playSound'], isFalse);
      expect(android['silent'], isTrue);
      expect(android['onlyAlertOnce'], isTrue);
      // No Live Activity channel on Android — the two backends never overlap.
      expect(activityCalls, isEmpty);
    });

    test('degrades the line when the book has no page count, then no page', () async {
      final live = subject(TargetPlatform.android);
      await live.start(
        libraryEntryId: 'le1',
        title: 'X',
        startedAt: startedAt,
        currentPage: 88,
      );
      await live.start(libraryEntryId: 'le1', title: 'X', startedAt: startedAt);

      final bodies = pluginCalls
          .where((c) => c.method == 'show')
          .map((c) => (c.arguments as Map)['body'])
          .toList();
      expect(bodies, ['p. 88', 'Reading now']);
    });

    test('end cancels the one ongoing notification', () async {
      await subject(TargetPlatform.android).end();

      final cancel = pluginCalls.firstWhere((c) => c.method == 'cancel');
      expect((cancel.arguments as Map)['id'], ReadingLiveActivity.notificationId);
    });
  });

  test('other platforms do nothing at all', () async {
    final live = subject(TargetPlatform.macOS);
    await live.start(libraryEntryId: 'le1', title: 'X', startedAt: startedAt);
    await live.end();

    expect(activityCalls, isEmpty);
    expect(pluginCalls, isEmpty);
  });
}
