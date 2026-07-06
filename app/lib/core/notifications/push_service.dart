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

/// Registers this install's FCM token with the API for the signed-in user,
/// keeps it fresh, and routes notification taps. All Firebase calls are guarded
/// so the app is unaffected on web or when Firebase isn't initialised (tests).
class PushService {
  PushService(this._api);

  final ApiClient _api;
  String? _token;
  bool _started = false;

  bool get _available => !kIsWeb && Firebase.apps.isNotEmpty;

  Future<void> start({void Function(RemoteMessage message)? onOpen}) async {
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

    _token = await messaging.getToken();
    if (_token != null) await _register(_token!);
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
  }

  Future<void> _register(String token) async {
    try {
      await _api.registerDevice(token, Platform.isIOS ? 'ios' : 'android');
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
        push.start(onOpen: (_) => ref.read(routerProvider).push(Routes.connections));
      } else if (now == null && was != null) {
        push.stop();
      }
    },
    fireImmediately: true,
  );
});
