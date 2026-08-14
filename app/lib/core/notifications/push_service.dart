import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/device_id.dart';
import '../../data/sync/sync_providers.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_service.dart';
import '../../features/library/providers/active_session_sync.dart';
import '../router/app_router.dart';

/// Handles a push that arrives while the app is backgrounded/terminated. Must be
/// a top-level, `vm:entry-point` function (it runs in its own isolate). Nothing
/// to do — the system renders the notification from its own payload.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Registers this install's FCM token with the API for the signed-in user,
/// keeps it fresh, and routes notification taps. All Firebase calls are guarded
/// so the app is unaffected on web or when Firebase isn't initialised (tests).
class PushService {
  PushService(this._api, this._deviceId);

  final ApiClient _api;

  /// This install's id, sent with the token so the server can leave this device
  /// out of a fan-out to the reader's own devices. Resolved lazily (it lives in
  /// Drift) and never fatal — a null id just means the server can't exclude us.
  final Future<String?> Function() _deviceId;

  String? _token;
  bool _started = false;

  bool get _available => !kIsWeb && Firebase.apps.isNotEmpty;

  Future<void> start({
    void Function(RemoteMessage message)? onOpen,
    void Function()? onLendEvent,
    void Function()? onReadingEvent,
  }) async {
    if (_started || !_available) return;
    _started = true;
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    // Let notifications show while the app is foregrounded (iOS default hides them).
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _acquireAndRegister(messaging);

    // Belt-and-braces: also catch the token if it only becomes available later
    // (e.g. APNs was slow past the poll window, or it rotates).
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      _register(t);
    });

    if (onOpen != null) {
      // App launched from a notification while terminated:
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen(initial);
      FirebaseMessaging.onMessageOpenedApp.listen(onOpen);
    }

    // A lending push arriving while the app is foregrounded → pull immediately so
    // a book just lent to me appears on the Borrowed shelf without waiting.
    // A reading push is the same idea for the running timer: the reader's other
    // device started or stopped a sitting, and this one should agree at once
    // rather than at the next 15-minute sync (owner request, 14 Aug 2026).
    if (onLendEvent != null || onReadingEvent != null) {
      FirebaseMessaging.onMessage.listen((m) {
        final type = m.data['type'];
        if (type == 'lend_new' || type == 'lend_returned' || type == 'lend_reminder') {
          onLendEvent?.call();
        } else if (type == 'reading_started' || type == 'reading_stopped') {
          onReadingEvent?.call();
        } else if (type == 'notes_changed') {
          // A note written on the reader's other device. Pull now rather than
          // at the next 15-minute tick — both devices are mid-sitting, which
          // is exactly when "immediately" is what the reader expects.
          onLendEvent?.call();
        }
      });
    }
  }

  Future<void> _acquireAndRegister(FirebaseMessaging messaging) async {
    try {
      // On iOS the FCM token exists only *after* the APNs token is set, which
      // arrives asynchronously (after registerForRemoteNotifications, which
      // requestPermission triggers). getToken() throws `apns-token-not-set`
      // until then, and onTokenRefresh does NOT fire for the *initial* token —
      // so a swallowed first failure loses it until reinstall. That's why iOS
      // never registered while Android (no APNs dependency) did. Poll first.
      if (Platform.isIOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; i < 20 && apns == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) {
          if (kDebugMode) {
            debugPrint('PushService: APNs token never arrived — check the App ID '
                '"Push Notifications" capability / provisioning profile.');
          }
          return; // getToken() would just throw apns-token-not-set
        }
      }
      _token = await messaging.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('PushService: token fetch failed: $e');
      _token = null;
    }
    if (_token != null) await _register(_token!);
  }

  Future<void> _register(String token) async {
    try {
      String? deviceId;
      try {
        deviceId = await _deviceId();
      } catch (_) {
        deviceId = null; // registering the token still matters more than the id
      }
      await _api.registerDevice(
        token,
        Platform.isIOS ? 'ios' : 'android',
        deviceId: deviceId,
      );
    } catch (_) {
      // Best-effort; a token refresh or the next launch retries.
    }
  }

  /// On sign-out: drop the token server-side and locally so a shared device
  /// stops receiving this account's pushes.
  Future<void> stop() async {
    final token = _token;
    if (token != null) {
      try {
        await _api.unregisterDevice(token);
      } catch (_) {
        // ignore — a dead token is pruned on the next failed send anyway
      }
    }
    if (_available) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    _token = null;
    _started = false;
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(
    ref.watch(apiClientProvider),
    // The install id, not the session's — this is device state and is wanted
    // before (and regardless of) whoever is signed in.
    () => getOrCreateDeviceId(ref.read(appDatabaseProvider)),
  ),
);

/// Where a tap on a push notification should land, from its data payload.
///
/// Pure and top-level so the rule is testable without Firebase — same reason
/// `readingTimerRouteFor` lives outside its listener. It exists at all because
/// the first version routed only lending pushes and sent *everything else* to
/// the connections inbox: tapping "『X』 is being timed on your other device"
/// opened a list of connection requests (owner report, 14 Aug 2026). A tap
/// belongs on the screen the notification is about, and a type with no obvious
/// home belongs on Home — never on an unrelated screen by default.
String pushTapRoute(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'lend_new':
    case 'lend_returned':
    case 'lend_reminder':
      return Routes.lendingLedger;
    case 'connection_request':
    case 'connection_accepted':
      return Routes.connections;
    case 'reading_started':
      // The running sitting itself — the screen that can show and stop it.
      final entryId = (data['library_entry_id'] as String?)?.trim() ?? '';
      return entryId.isEmpty ? Routes.home : Routes.readingTimerPath(entryId);
    default:
      return Routes.home;
  }
}

/// Registers the token when a user signs in and clears it on sign-out; taps on a
/// notification open the screen the event is about. Watch this once at the app root.
final pushLifecycleProvider = Provider<void>((ref) {
  final push = ref.watch(pushServiceProvider);
  ref.listen<AsyncValue<KitabiAuthUser?>>(
    authStateProvider,
    (prev, next) {
      final was = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (now != null && was == null) {
        push.start(
          onOpen: (message) {
            // Route the tap to where the event lives — via the external-nav
            // helper, so a cold-start tap survives the splash/bootstrap
            // redirect instead of being swallowed into home, and a tap on a
            // screen already open doesn't stack a second copy of it.
            final router = ref.read(routerProvider);
            final route = pushTapRoute(message.data);
            if (message.data['type'] == 'reading_started') {
              // A tapped notification is the one case where this device has
              // *not* seen the sitting yet: a background push does no work, so
              // nothing has mirrored the server's row into local state. Arrive
              // after the pull — the timer screen reads the session from local
              // state, finds none, and reads that as "stopped elsewhere", which
              // would bounce the reader straight back out of the screen they
              // just asked for. Best-effort: navigate even if the pull fails,
              // so a tap always goes somewhere.
              unawaited(ref
                  .read(activeSessionSyncProvider)
                  .pullAndApply()
                  .whenComplete(() => navigateFromExternal(router, route)));
              return;
            }
            navigateFromExternal(router, route);
          },
          onLendEvent: () => ref.read(syncTriggerProvider)(),
          // The payload carries the sitting, but the *server* is the authority
          // on what is running — so the push is only a nudge to re-read, which
          // also makes a missed or duplicated push harmless.
          onReadingEvent: () => ref.read(activeSessionSyncProvider).pullAndApply(),
        );
      } else if (now == null && was != null) {
        push.stop();
      }
    },
    fireImmediately: true,
  );
});
