import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/device_id.dart';
import '../../data/sync/sync_engine.dart';
import '../../features/library/providers/reading_timer_providers.dart';
import '../../l10n/app_localizations.dart';
import '../auth/supabase_auth_service.dart';
import '../format_duration.dart';
import 'notification_service.dart';

/// Schedules (or re-schedules) both halves of the "still reading?" safety
/// net for [libraryEntryId]: the actionable check-in notification, and the
/// silent workmanager enforcement task that auto-stops the session if the
/// check-in goes unanswered. [from] is normally "now" — the session's start
/// time on the very first arm, or the moment "Yes, still reading" was tapped
/// on every re-arm, since either way the next check-in is 60 minutes out.
///
/// Callable from a `BuildContext` (real `AppLocalizations`) or a background
/// isolate (`lookupAppLocalizations`) — the caller resolves copy either way.
/// Never throws: called fire-and-forget from `_ReadingSessionCard._open`, so
/// a notification-plugin hiccup (or no platform channel at all, e.g. a
/// widget test) must never be mistaken for the session itself failing to
/// start — same defensive stance as `stopAndLogActiveSession`'s cleanup.
Future<void> armReadingTimerSafetyNet({
  required String libraryEntryId,
  required DateTime from,
  required String title,
  required String body,
  required String yesLabel,
  required String noLabel,
}) async {
  try {
    final checkInAt = from.add(readingCheckInDelay);
    await NotificationService(FlutterLocalNotificationsPlugin()).scheduleCheckIn(
      id: readingCheckInNotificationId(libraryEntryId),
      title: title,
      body: body,
      when: checkInAt,
      yesLabel: yesLabel,
      noLabel: noLabel,
      payload: libraryEntryId,
    );
    final enforceDelay = checkInAt.add(readingCheckInGrace).difference(DateTime.now());
    if (enforceDelay.isNegative) return;
    await Workmanager().registerOneOffTask(
      readingEnforcementTaskName(libraryEntryId),
      readingEnforcementTaskName(libraryEntryId),
      initialDelay: enforceDelay,
      inputData: {'libraryEntryId': libraryEntryId},
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (_) {}
}

/// The response handler for both the foreground and background delivery of
/// the "still reading?" check-in — registered as both
/// `onDidReceiveNotificationResponse` and
/// `onDidReceiveBackgroundNotificationResponse` in
/// `NotificationService._ensureReady`. The background variant runs in a
/// fresh, separate isolate with no Activity/app context (Android) and is
/// only reliable while the app is backgrounded, not fully terminated, on iOS
/// — same constraints as `background_sync.dart`'s workmanager callback,
/// which this mirrors: re-init what's needed, never throw.
@pragma('vm:entry-point')
void onReadingTimerNotificationResponse(NotificationResponse response) {
  _handle(response);
}

/// iOS cannot reliably invoke [onReadingTimerNotificationResponse] in the
/// background while the app is fully terminated — call this once at app
/// startup (`main.dart`) so a cold start caused by tapping "Yes"/"No" still
/// gets handled, just a beat later than a live background delivery would.
/// Safe no-op if the app wasn't launched this way.
Future<void> handleColdStartReadingTimerResponse() async {
  final details =
      await FlutterLocalNotificationsPlugin().getNotificationAppLaunchDetails();
  final response = details?.notificationResponse;
  if (details?.didNotificationLaunchApp != true || response == null) return;
  await _handle(response);
}

Future<void> _handle(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId != readingCheckInYesActionId && actionId != readingCheckInNoActionId) {
    return;
  }
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (!supabaseConfigured) return;
    await initSupabase();
    final userId = Supabase.instance.client.auth.currentSession?.user.id;
    if (userId == null) return;

    final db = AppDatabase();
    final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
    // The notification's payload pins it to the entry it was scheduled for —
    // if the active session has since changed (stopped, or a different book
    // started), this response is stale and does nothing.
    if (entryId == null || entryId != response.payload) return;

    if (actionId == readingCheckInNoActionId) {
      await stopReadingSessionAndNotify(db: db, userId: userId, libraryEntryId: entryId);
    } else {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await armReadingTimerSafetyNet(
        libraryEntryId: entryId,
        from: DateTime.now(),
        title: l10n.timerCheckInTitle,
        body: l10n.timerCheckInBody,
        yesLabel: l10n.timerCheckInYes,
        noLabel: l10n.timerCheckInNo,
      );
    }
  } catch (_) {
    // Never let a notification-action isolate crash the OS.
  }
}

/// Stops [libraryEntryId]'s active session (if it's still the one running),
/// posts the "stopped while you were away" notification, and pushes the sync
/// queue — shared by the "No, stop it" action above and the workmanager
/// enforcement task (`background_sync.dart`) that fires when a check-in goes
/// unanswered, so both auto-stop paths behave identically.
Future<void> stopReadingSessionAndNotify({
  required AppDatabase db,
  required String userId,
  required String libraryEntryId,
}) async {
  final deviceId = await getOrCreateDeviceId(db);
  final logged = await stopAndLogActiveSession(
    db,
    SessionContext(userId: userId, deviceId: deviceId),
  );
  if (logged != null) {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await NotificationService(FlutterLocalNotificationsPlugin()).notifyNow(
      id: readingAutoStoppedNotificationId(libraryEntryId),
      title: l10n.timerAutoStoppedTitle,
      body: l10n.timerAutoStoppedBody(
        formatDuration(Duration(seconds: logged.durationSeconds)),
      ),
    );
  }
  await SyncEngine(db, ApiClient()).syncNow(userId);
}
