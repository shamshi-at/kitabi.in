import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../auth/auth_providers.dart';
import '../auth/auth_service.dart';
import '../router/app_router.dart';

/// Handles a push that arrives while the app is backgrounded/terminated. Must be
/// a top-level, `vm:entry-point` function (it runs in its own isolate). Nothing
/// to do — the system renders the notification from its own payload.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// A snapshot of the push pipeline's health, surfaced by the in-app diagnostic
/// (Profile → "Push notifications"). Makes an otherwise-invisible release/TestFlight
/// failure legible: was Firebase available, was permission granted, did the APNs
/// token arrive (iOS), did we get an FCM token, and did the API accept it.
class PushDiagnostics {
  const PushDiagnostics({
    this.firebaseAvailable = false,
    this.permission = 'unknown',
    this.checking = false,
    this.apnsToken,
    this.fcmToken,
    this.registered = false,
    this.lastError,
  });

  final bool firebaseAvailable;
  final String permission; // authorized | denied | provisional | notDetermined
  final bool checking; // token acquisition (incl. the iOS APNs poll) in progress
  final bool? apnsToken; // iOS only: null = not yet checked, true/false = present
  final String? fcmToken;
  final bool registered; // token accepted by POST /devices
  final String? lastError;

  static const _keep = Object();

  PushDiagnostics copyWith({
    bool? firebaseAvailable,
    String? permission,
    bool? checking,
    bool? apnsToken,
    Object? fcmToken = _keep,
    bool? registered,
    Object? lastError = _keep,
  }) =>
      PushDiagnostics(
        firebaseAvailable: firebaseAvailable ?? this.firebaseAvailable,
        permission: permission ?? this.permission,
        checking: checking ?? this.checking,
        apnsToken: apnsToken ?? this.apnsToken,
        fcmToken: fcmToken == _keep ? this.fcmToken : fcmToken as String?,
        registered: registered ?? this.registered,
        lastError: lastError == _keep ? this.lastError : lastError as String?,
      );
}

/// Registers this install's FCM token with the API for the signed-in user,
/// keeps it fresh, and routes notification taps. All Firebase calls are guarded
/// so the app is unaffected on web or when Firebase isn't initialised (tests).
class PushService {
  PushService(this._api);

  final ApiClient _api;
  String? _token;
  bool _started = false;

  /// Live push state for the in-app diagnostic; watch via [diagnostics].
  final ValueNotifier<PushDiagnostics> diagnostics =
      ValueNotifier<PushDiagnostics>(const PushDiagnostics());

  bool get _available => !kIsWeb && Firebase.apps.isNotEmpty;

  void _set(PushDiagnostics Function(PushDiagnostics) f) =>
      diagnostics.value = f(diagnostics.value);

  Future<void> start({void Function(RemoteMessage message)? onOpen}) async {
    if (_started || !_available) {
      _set((d) => d.copyWith(firebaseAvailable: _available));
      return;
    }
    _started = true;
    _set((d) => d.copyWith(firebaseAvailable: true));
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    _set((d) => d.copyWith(permission: settings.authorizationStatus.name));
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
      _set((d) => d.copyWith(fcmToken: t));
      _register(t);
    });

    if (onOpen != null) {
      // App launched from a notification while terminated:
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpen(initial);
      FirebaseMessaging.onMessageOpenedApp.listen(onOpen);
    }
  }

  /// Re-run token acquisition + registration on demand — the diagnostic's "retry",
  /// useful when the APNs token was slow or push was only just granted in Settings.
  Future<void> refresh() async {
    if (!_available) {
      _set((d) => d.copyWith(firebaseAvailable: false));
      return;
    }
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();
    _set((d) => d.copyWith(firebaseAvailable: true, permission: settings.authorizationStatus.name));
    await _acquireAndRegister(messaging);
  }

  Future<void> _acquireAndRegister(FirebaseMessaging messaging) async {
    _set((d) => d.copyWith(checking: true, lastError: null));
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
        _set((d) => d.copyWith(apnsToken: apns != null));
        if (apns == null) {
          _set((d) => d.copyWith(
              checking: false,
              lastError: 'APNs token never arrived — check the App ID "Push '
                  'Notifications" capability / provisioning profile.'));
          return; // getToken() would just throw apns-token-not-set
        }
      }
      _token = await messaging.getToken();
      _set((d) => d.copyWith(fcmToken: _token, lastError: null));
    } catch (e) {
      _set((d) => d.copyWith(lastError: 'token fetch failed: $e'));
      _token = null;
    } finally {
      _set((d) => d.copyWith(checking: false));
    }
    if (_token != null) await _register(_token!);
  }

  Future<void> _register(String token) async {
    try {
      await _api.registerDevice(token, Platform.isIOS ? 'ios' : 'android');
      _set((d) => d.copyWith(registered: true, lastError: null));
    } catch (e) {
      // Best-effort; a token refresh or the next launch retries.
      _set((d) => d.copyWith(registered: false, lastError: 'register failed: $e'));
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

final pushServiceProvider =
    Provider<PushService>((ref) => PushService(ref.watch(apiClientProvider)));

/// Registers the token when a user signs in and clears it on sign-out; taps on a
/// notification open the connections inbox. Watch this once at the app root.
final pushLifecycleProvider = Provider<void>((ref) {
  final push = ref.watch(pushServiceProvider);
  ref.listen<AsyncValue<KitabiAuthUser?>>(
    authStateProvider,
    (prev, next) {
      final was = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (now != null && was == null) {
        push.start(onOpen: (message) {
          final router = ref.read(routerProvider);
          final type = message.data['type'];
          // Route the tap to where the event lives.
          if (type == 'lend_new' || type == 'lend_returned' || type == 'lend_reminder') {
            router.go(Routes.lendingLedger);
          } else {
            router.push(Routes.connections);
          }
        });
      } else if (now == null && was != null) {
        push.stop();
      }
    },
    fireImmediately: true,
  );
});
