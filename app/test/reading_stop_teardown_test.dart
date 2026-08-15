import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/notifications/reading_live_activity.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';

/// What must be true of the *outside* of the app once a sitting stops: the
/// lock-screen clock is gone, the check-in is cancelled, and nothing is left
/// behind that could bring the sitting back.
///
/// The regression (owner report, 14 Aug 2026: "stopping the timer from the
/// timer screen, the live notification is not getting stopped"): all three
/// cleanups shared one `try`, in the order cancel-check-in → cancel-enforcement
/// → end-the-clock. "Best-effort" therefore meant "the first one that throws
/// cancels the two after it", and the clock — the one the reader can actually
/// see — was last in the queue. A background plugin channel that isn't there
/// is enough to trigger it, which is why the workmanager cancel is left
/// unmocked here: that is exactly the shape of the failure.
const _pluginChannel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cancelled = <int>[];
  var failCheckInCancel = false;

  setUp(() {
    cancelled.clear();
    failCheckInCancel = false;
    // The live surface is only a *notification* on Android, so that is the
    // half worth asserting on — and the plugin picks its implementation from
    // `defaultTargetPlatform` *and* from whichever platform class registered
    // itself. On a macOS test host neither is Android and every call silently
    // no-ops, so both have to be told (same setup as
    // reading_live_activity_test).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance = AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
      if (call.method == 'cancel') {
        final id = (call.arguments as Map)['id'] as int;
        if (failCheckInCancel && id != ReadingLiveActivity.notificationId) {
          throw PlatformException(code: 'no_channel');
        }
        cancelled.add(id);
        return null;
      }
      // `initialize` and the permission requests are typed `bool` plugin-side.
      return call.method == 'initialize' ||
              call.method == 'requestNotificationsPermission' ||
              call.method == 'requestPermissions'
          ? true
          : null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
  });

  const session = SessionContext(userId: 'u1', deviceId: 'd1');

  Future<AppDatabase> dbWithRunningSitting({String sessionId = 's-1'}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.keyValuesDao.setValue(activeSessionEntryKey, 'entry-1');
    await db.keyValuesDao.setValue(activeSessionIdKey, sessionId);
    await db.keyValuesDao.setValue(
      activeSessionStartedKey,
      DateTime.now().subtract(const Duration(minutes: 25)).toIso8601String(),
    );
    return db;
  }

  test('the lock-screen clock comes down even when the check-in cancel throws',
      () async {
    failCheckInCancel = true;
    final db = await dbWithRunningSitting();

    final logged = await stopAndLogActiveSession(db, session);

    expect(logged, isNotNull, reason: 'the sitting is the real thing');
    expect(cancelled, contains(ReadingLiveActivity.notificationId),
        reason: 'a failure cleaning up one surface must not spare another');
  });

  test('a stop with nothing left to log still clears the clock', () async {
    // Both background auto-stop paths write straight to the database, so a
    // stop arriving after one of them finds the keys already gone. Returning
    // in silence there left the notification counting a finished sitting.
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    expect(await stopAndLogActiveSession(db, session), isNull);
    expect(cancelled, contains(ReadingLiveActivity.notificationId));
  });

  test('stopping leaves a note to take the sitting off the account', () async {
    final db = await dbWithRunningSitting(sessionId: 's-42');
    await db.keyValuesDao.setValue(activeSessionMirroredKey, 's-42');

    await stopAndLogActiveSession(db, session);

    expect(await db.keyValuesDao.getValue(activeSessionPendingStopKey), 's-42',
        reason: 'the DELETE has not happened yet and may not for hours');
    // Left behind, this told a later pull that a *new* sitting from another
    // device was one this device had already adopted.
    expect(await db.keyValuesDao.getValue(activeSessionMirroredKey), isNull);
    expect(await db.keyValuesDao.getValue(activeSessionEntryKey), isNull);
  });
}
