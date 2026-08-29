import '../router/app_router.dart';

/// What a *local* notification is about, and where tapping it should land.
///
/// A local notification carries one opaque `payload` string, and that string
/// used to be an unqualified library-entry id. So the tap handler had exactly
/// one destination it could name — the reading timer — and every other family
/// of notification had no way to say anything at all. The lending due-date
/// reminders were scheduled with no payload for precisely that reason, which
/// meant tapping one read a null payload, returned, and left the app on
/// whatever screen it had been on: Home, almost always (owner report,
/// 29 Aug 2026).
///
/// Qualifying the payload is what lets a second family exist. The pair is
/// `<target>:<id>`; ids here are UUIDs (or a `workId/editionId` pair), never
/// containing a colon, so the split is unambiguous — and a payload with no
/// recognised prefix is read as the old bare form, because a check-in
/// scheduled before this change is sitting in the OS's own queue on real
/// devices and will still be delivered days from now.
enum NotificationTarget {
  /// The running sitting — id is the library entry.
  readingTimer('reading-timer'),

  /// A due-date reminder for a book lent or borrowed. The ledger is the
  /// destination rather than the single loan: the loans-with-one-person page
  /// takes its subject through route `extra`, which a notification can't carry.
  lending('lending'),

  /// A book's own page — id is `workId/editionId`.
  book('book');

  const NotificationTarget(this.wireName);

  final String wireName;
}

/// The payload to schedule a notification with. Every `scheduleX`/`showX` call
/// builds its payload here rather than passing a bare id.
String notificationPayload(NotificationTarget target, String id) =>
    '${target.wireName}:$id';

/// The `(target, id)` a payload names, or null when it names nothing.
({NotificationTarget target, String id})? parseNotificationPayload(String? raw) {
  final payload = raw?.trim() ?? '';
  if (payload.isEmpty) return null;
  final sep = payload.indexOf(':');
  if (sep > 0) {
    final prefix = payload.substring(0, sep);
    final id = payload.substring(sep + 1);
    for (final target in NotificationTarget.values) {
      if (target.wireName == prefix) {
        return id.isEmpty ? null : (target: target, id: id);
      }
    }
  }
  // Unqualified — the pre-29-Aug-2026 form, which only ever meant a library
  // entry with a sitting on it. Still arriving from notifications scheduled
  // before the app was updated.
  return (target: NotificationTarget.readingTimer, id: payload);
}

/// Where a tap on a local notification should land — null when its payload
/// names nothing openable, which is the one case where doing nothing is right.
///
/// Pure and top-level for the same reason [pushTapRoute] and
/// [readingTimerRouteFor] are: the whole feature is the rule, and it cannot be
/// exercised through the notifications plugin.
String? localNotificationRoute(String? payload) {
  final parsed = parseNotificationPayload(payload);
  if (parsed == null) return null;
  return switch (parsed.target) {
    NotificationTarget.readingTimer => Routes.readingTimerPath(parsed.id),
    NotificationTarget.lending => Routes.lendingLedger,
    // `workId/editionId`, already joined — a malformed pair would build a
    // location no route matches, so check before trusting it.
    NotificationTarget.book =>
      parsed.id.split('/').length == 2 ? '/book/${parsed.id}' : null,
  };
}
