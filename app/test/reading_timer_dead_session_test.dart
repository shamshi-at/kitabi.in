import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/core/notifications/notification_service.dart';
import 'package:kitabi/core/notifications/reading_live_activity.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/library/presentation/reading_timer_screen.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The sitting is over, but its lock-screen clock is still on the phone —
/// every "best-effort" stop path can leave one behind (an iOS background
/// isolate has no channel to end it with, a plugin call can fail, the app can
/// be killed mid-stop). Tapping it is then the *worst* entry point in the app:
/// it cold-starts the process straight onto a route whose whole subject no
/// longer exists.
///
/// Owner report, 29 Aug 2026 — after marking a book completed from the timer,
/// "the live notification stays there, opening it opens the timer screen where
/// clock is ticking but the time stays at 0:00". Two separate failures met
/// there, one per test below.
const _pluginChannel = MethodChannel('dexterous.com/flutter/local_notifications');
const _activityChannel = MethodChannel('in.kitabi.kitabi/reading_activity');
const _entryId = 'le-dead';

class _FakeApi extends ApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pluginCalls = <MethodCall>[];

  setUp(() {
    pluginCalls.clear();
    NotificationService.resetReadyForTesting();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_activityChannel, (call) async => null);
    messenger.setMockMethodCallHandler(_pluginChannel, (call) async {
      pluginCalls.add(call);
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

  /// Hydration is the only reconciliation a cold start gets — `reconcile()`
  /// hangs off `didChangeAppLifecycleState`, which is never called for the
  /// state the app launches in. So a hydrate that finds nothing running must
  /// take the clock down itself, or a stale one survives every relaunch.
  test('a cold start with no sitting takes the lock-screen clock down', () async {
    // The notifications plugin picks its implementation from
    // `defaultTargetPlatform` *and* from whichever platform class registered
    // itself — on a macOS test host neither is Android, so `cancel` silently
    // no-ops and this would assert nothing (same setup as
    // reading_live_activity_test.dart's Android group).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // Nothing in key_values: the sitting was stopped and logged, exactly as it
    // is after "I finished the book".
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.hydrated;

    expect(
      pluginCalls.where(
        (c) => c.method == 'cancel' && c.arguments['id'] == ReadingLiveActivity.notificationId,
      ),
      isNotEmpty,
      reason: 'a hydrate that finds no sitting must end the live surface, not just return',
    );
  });

  /// …and the screen that clock opens must be able to leave. This route is
  /// *arrived at* as often as it is pushed — a notification tap on a cold
  /// start replaces the stack — so the give-up guard's `canPop()` is false and
  /// the `pop()` it used to make silently did nothing, stranding the reader on
  /// a sweeping hand over a clock frozen at 0:00.
  testWidgets('a timer opened onto a sitting that no longer exists leaves', (tester) async {
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };
    GoogleFonts.config.allowRuntimeFetching = false;

    // Never closed: db.close() deadlocks between the fake-async zone and drift.
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_FakeApi()),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
      ),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // The timer *is* the stack — nothing beneath it, which is what the engine
    // hands us when a notification tap cold-starts the app.
    final router = GoRouter(
      initialLocation: Routes.readingTimerPath(_entryId),
      routes: [
        GoRoute(
          path: Routes.home,
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: Routes.readingTimer,
          builder: (context, state) => ReadingTimerScreen(
            libraryEntryId: state.pathParameters['libraryEntryId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 30));
    }

    // On the router, not on rendering — a route that has been left stays in
    // the tree while its transition plays.
    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      Routes.home,
      reason: 'a timer with no sitting behind it must not strand the reader at 0:00',
    );

    await tester.pumpWidget(const SizedBox());
    reportTestException = reportOriginal;
  });
}
