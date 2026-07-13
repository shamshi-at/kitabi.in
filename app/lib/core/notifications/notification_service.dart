import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/library/providers/reading_timer_providers.dart';
import '../../l10n/app_localizations.dart';
import 'reading_timer_notifications.dart';

/// On-device local notifications: lending due-date reminders, and the reading
/// timer's "still reading?" check-in. No server, no push — everything is
/// scheduled locally (CLAUDE.md rule 8: no new services).
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channelId = 'lending_reminders';
  static const _checkInChannelId = 'reading_checkins';

  Future<void> _ensureReady() async {
    if (_ready) return;
    // `zonedSchedule` needs the tz database loaded. We schedule from a local
    // wall-clock DateTime and convert with `TZDateTime.from(..., tz.local)`,
    // which preserves the absolute instant (epoch) — so the reminder fires at
    // the right moment regardless of which zone `tz.local` resolves to. That
    // lets us skip a device-timezone plugin entirely.
    tz.initializeTimeZones();
    // iOS notification-category action titles are fixed at registration time
    // (unlike Android, where actions are attached fresh on every schedule
    // call — see `scheduleCheckIn` below) — English-only for now, same as the
    // rest of the app (CLAUDE.md: Malayalam is on the roadmap, not built yet).
    final l10n = lookupAppLocalizations(const Locale('en'));
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            readingCheckInCategoryId,
            actions: [
              DarwinNotificationAction.plain(
                readingCheckInYesActionId,
                l10n.timerCheckInYes,
              ),
              DarwinNotificationAction.plain(
                readingCheckInNoActionId,
                l10n.timerCheckInNo,
              ),
            ],
          ),
        ],
      ),
    );
    // Both callbacks route through the same handler — it branches on
    // `response.actionId`. The background one must be a top-level/static
    // `@pragma('vm:entry-point')` function (see reading_timer_notifications.dart).
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onReadingTimerNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onReadingTimerNotificationResponse,
    );
    _ready = true;
  }

  /// Ask for notification permission (Android 13+ / iOS). Safe to call more than
  /// once — the OS only prompts the first time.
  Future<void> requestPermission() async {
    await _ensureReady();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Schedule a one-off reminder. Past times are ignored (nothing to remind).
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await _ensureReady();
    if (!when.isAfter(DateTime.now())) return;
    await requestPermission();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Lending reminders',
          channelDescription: 'Due-date reminders for books you have lent or borrowed',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancel(int id) async {
    await _ensureReady();
    await _plugin.cancel(id);
  }

  /// The reading timer's "still reading?" check-in — a Yes/No actionable
  /// notification. `showsUserInterface: false` on both Android actions routes
  /// the tap straight to [onReadingTimerNotificationResponse] without opening
  /// the app; iOS behaves the same way by omitting the `.foreground` option
  /// on its category actions (registered once in [_ensureReady]).
  Future<void> scheduleCheckIn({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String yesLabel,
    required String noLabel,
    required String payload,
  }) async {
    await _ensureReady();
    if (!when.isAfter(DateTime.now())) return;
    await requestPermission();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _checkInChannelId,
          'Reading session check-ins',
          channelDescription: 'Checks in when a reading timer has been running a long time',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(readingCheckInYesActionId, yesLabel, showsUserInterface: false),
            AndroidNotificationAction(readingCheckInNoActionId, noLabel, showsUserInterface: false),
          ],
        ),
        iOS: const DarwinNotificationDetails(categoryIdentifier: readingCheckInCategoryId),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  /// Fires immediately — used for "reading timer stopped while you were
  /// away" once an auto-stop actually happens, so it isn't silent.
  Future<void> notifyNow({required int id, required String title, required String body}) async {
    await _ensureReady();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _checkInChannelId,
          'Reading session check-ins',
          channelDescription: 'Checks in when a reading timer has been running a long time',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FlutterLocalNotificationsPlugin()),
);
