import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../l10n/app_localizations.dart';
import 'notification_service.dart';

/// The running sitting, shown *outside* the app — on the lock screen, so a
/// reader can see the clock without unlocking the phone and reopening Kitabi.
///
/// **The two platforms are not the same feature, and this class does not
/// pretend otherwise.** iOS has ActivityKit: a real Live Activity, rendered by
/// our own widget extension on the lock screen and in the Dynamic Island,
/// counting up on its own. Android has no such API below Android 16 — its
/// equivalent is an **ongoing notification with a chronometer**, which the
/// system ticks live in the shade and on the lock screen. Same promise to the
/// reader ("the clock is visible without unlocking"), two different mechanisms,
/// one API here so the session lifecycle never has to know which it's talking
/// to. (Android 16's promoted "Live Updates" would upgrade the Android side to
/// a status-bar chip; it needs `Notification.ProgressStyle`, which the
/// notifications plugin doesn't expose yet — see docs/build.md.)
///
/// Nothing here may ever throw into the timer. A reader's sitting is the real
/// thing; the lock-screen rendering of it is decoration, and the same
/// defensive stance the check-in notification takes applies — a missing
/// platform channel (a widget test, a background isolate with no registrant,
/// an iOS version below 16.1) must look like "no lock-screen clock", never
/// like "the timer failed to start".
class ReadingLiveActivity {
  ReadingLiveActivity({
    NotificationService? notifications,
    this._channel = _defaultChannel,
    TargetPlatform? platform,
  })  : _notifications =
            notifications ?? NotificationService(FlutterLocalNotificationsPlugin()),
        _platform = platform ?? defaultTargetPlatform;

  static const _defaultChannel = MethodChannel('in.kitabi.kitabi/reading_activity');

  final NotificationService _notifications;
  final MethodChannel _channel;
  final TargetPlatform _platform;

  /// One sitting runs app-wide at a time (you can't read two books in the same
  /// minute), so the ongoing notification is a single fixed id rather than one
  /// hashed per entry like the check-in.
  static const notificationId = 0x51DE;

  Future<void> start({
    required String libraryEntryId,
    required String title,
    String? author,
    required DateTime startedAt,
    int? currentPage,
    int? pageCount,
    DateTime? staleAt,
  }) async {
    if (_platform == TargetPlatform.iOS) {
      await _invoke('start', {
        'libraryEntryId': libraryEntryId,
        'title': title,
        'author': author,
        'startedAt': startedAt.millisecondsSinceEpoch ~/ 1000,
        'currentPage': currentPage,
        'pageCount': pageCount,
        // When a sitting is stopped from a background isolate there is no
        // method channel to end the activity with, so the lock screen would go
        // on counting a sitting that no longer exists (owner report, 26 Jul
        // 2026). A stale date makes iOS render it as outdated instead of
        // confidently wrong; `reconcile()` refreshes it on the next resume.
        'staleAt': staleAt == null ? null : staleAt.millisecondsSinceEpoch ~/ 1000,
      });
      return;
    }
    if (_platform == TargetPlatform.android) {
      await _showOngoing(
        libraryEntryId: libraryEntryId,
        title: title,
        startedAt: startedAt,
        currentPage: currentPage,
        pageCount: pageCount,
      );
    }
  }

  /// The page moved (or the catalogue learned how long the book is) — the
  /// clock keeps running either way, only the line under it changes.
  Future<void> update({
    required String libraryEntryId,
    required String title,
    required DateTime startedAt,
    int? currentPage,
    int? pageCount,
  }) async {
    if (_platform == TargetPlatform.iOS) {
      await _invoke('update', {
        'currentPage': currentPage,
        'pageCount': pageCount,
      });
      return;
    }
    if (_platform == TargetPlatform.android) {
      // Re-showing the same id replaces it in place; `onlyAlertOnce` keeps it
      // from buzzing again for what is only a text change.
      await _showOngoing(
        libraryEntryId: libraryEntryId,
        title: title,
        startedAt: startedAt,
        currentPage: currentPage,
        pageCount: pageCount,
      );
    }
  }

  /// Ends the live surface. Safe to call when nothing is showing — every stop
  /// path funnels through one place that calls this, and reconciliation on
  /// resume calls it again, so it has to be idempotent.
  Future<void> end() async {
    if (_platform == TargetPlatform.iOS) {
      await _invoke('end', const {});
      return;
    }
    if (_platform == TargetPlatform.android) {
      try {
        await _notifications.cancel(notificationId);
      } catch (_) {}
    }
  }

  Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // No registrant (background isolate), iOS < 16.1, or Live Activities
      // switched off in Settings. All of them mean "no lock-screen clock".
    }
  }

  Future<void> _showOngoing({
    required String libraryEntryId,
    required String title,
    required DateTime startedAt,
    int? currentPage,
    int? pageCount,
  }) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    try {
      await _notifications.showReadingSession(
        id: notificationId,
        title: title,
        body: _progressLine(l10n, currentPage, pageCount),
        startedAt: startedAt,
        // Same payload convention as the check-in, so a tap on the body lands
        // on this book's running timer (`_openReadingTimer`).
        payload: libraryEntryId,
      );
    } catch (_) {}
  }

  /// "p. 302 of 724" when the book's length is known, the page alone when it
  /// isn't, and a plain line when the reader hasn't recorded a page at all —
  /// the same "never a bare percentage" rule the rest of the app follows.
  static String _progressLine(AppLocalizations l10n, int? currentPage, int? pageCount) {
    if (currentPage != null && pageCount != null && pageCount > 0) {
      return l10n.timerLiveProgress(currentPage, pageCount);
    }
    if (currentPage != null) return l10n.timerLiveProgressPage(currentPage);
    return l10n.timerLiveRunning;
  }
}
