import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// On-device local notifications for lending due-date reminders. No server, no
/// push — everything is scheduled locally (CLAUDE.md rule 8: no new services).
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _channelId = 'lending_reminders';

  Future<void> _ensureReady() async {
    if (_ready) return;
    // `zonedSchedule` needs the tz database loaded. We schedule from a local
    // wall-clock DateTime and convert with `TZDateTime.from(..., tz.local)`,
    // which preserves the absolute instant (epoch) — so the reminder fires at
    // the right moment regardless of which zone `tz.local` resolves to. That
    // lets us skip a device-timezone plugin entirely.
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
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
      const NotificationDetails(
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
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FlutterLocalNotificationsPlugin()),
);
