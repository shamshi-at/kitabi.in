import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';

/// Listens for incoming kitabi.in universal/app links (the shareable
/// /b/:id, /a/:id, /p/:id paths) and routes them to the matching in-app
/// screen. Deliberately scoped to https kitabi.in hosts only, so it never
/// touches the Supabase OAuth callback (a custom `in.kitabi.kitabi://` scheme
/// handled by supabase_flutter's own listener) — both share the app_links
/// stream and each ignores the other's links.
///
/// Three deliveries feed [_handle], because no single one is reliable on both
/// platforms:
///
/// * `uriLinkStream` — a link arriving while the app is alive.
/// * `getInitialLink()` — the link that cold-started the app. On a cold start
///   the stream *also* fires, so the same tap arrives twice; the short-window
///   guard in [_handle] collapses the echo, which otherwise pushed the book
///   page onto the stack twice (verified on an Android emulator, 23 Jul 2026).
/// * `getLatestLink()` on resume — the fallback that matters on iOS, where a
///   universal link tapped while the app is backgrounded is delivered through
///   `continueUserActivity`; if that event is missed, nothing else ever
///   reports it and the app just comes to the foreground on whatever screen it
///   was showing. Reported on a real iPhone (22 Jul 2026): the first tap opened
///   the book, every tap after that only raised the app.
class DeepLinkListener {
  DeepLinkListener(this._ref);

  final Ref _ref;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  AppLifecycleListener? _lifecycle;

  /// The last link actually routed — the dedupe key for both guards below.
  Uri? _lastHandled;
  DateTime? _lastHandledAt;

  /// Window in which an identical link counts as the cold-start echo rather
  /// than a deliberate second tap.
  static const _echoWindow = Duration(milliseconds: 1500);

  void start() {
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    // A cold-start link (app launched by tapping the link) arrives here.
    unawaited(_appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri);
    }).catchError((_) {}));
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  /// Catches a link the stream never delivered. `getLatestLink()` keeps
  /// returning the same link indefinitely, so this only acts on one we have
  /// not already routed — otherwise every trip through the app switcher would
  /// re-open the last shared book.
  void _onResume() {
    unawaited(_appLinks.getLatestLink().then((uri) {
      if (uri != null && uri != _lastHandled) _handle(uri);
    }).catchError((_) {}));
  }

  void _handle(Uri uri) {
    if (_handleReadingTimer(uri)) return;
    // One rule for what a shared link means, shared with the router's redirect
    // — the engine delivers these links there, not here, so the two must not
    // drift (owner report, 14 Aug 2026: they had).
    final route = shareRouteFor(uri);
    if (route == null) return;

    // Collapse the cold-start echo (stream + getInitialLink for one tap)
    // without swallowing a genuine re-tap of the same link later on.
    final now = DateTime.now();
    if (uri == _lastHandled &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _echoWindow) {
      return;
    }
    _lastHandled = uri;
    _lastHandledAt = now;

    final router = _ref.read(routerProvider);
    // Via the external-nav helper: a cold-start link (app launched by the tap)
    // must wait out the splash/bootstrap redirect or it's swallowed into home.
    navigateFromExternal(router, route);
  }

  /// `in.kitabi.kitabi://reading-timer/:libraryEntryId` — a tap on the iOS
  /// Live Activity (lock screen or Dynamic Island). Returns whether this link
  /// was ours, so the https branch below never sees it.
  ///
  /// The scheme is shared with the Supabase OAuth callback, which is why the
  /// host is checked and not just the scheme: `login-callback` links keep going
  /// to supabase_flutter's own listener untouched. Android needs none of this —
  /// its ongoing notification carries the entry id as a payload and
  /// `_openReadingTimer` has always routed it.
  bool _handleReadingTimer(Uri uri) {
    if (!uri.isScheme(kAppScheme) || uri.host != kReadingTimerHost) return false;
    final route = readingTimerRouteFor(uri);
    if (route == null) return true;

    // The activity sits on the lock screen for a whole sitting, so the same
    // card can legitimately be tapped again minutes later — but a cold start
    // still delivers one tap twice (stream + getInitialLink), so it needs the
    // same echo guard as a shared link.
    final now = DateTime.now();
    if (uri == _lastHandled &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < _echoWindow) {
      return true;
    }
    _lastHandled = uri;
    _lastHandledAt = now;

    navigateFromExternal(_ref.read(routerProvider), route);
    return true;
  }

  void dispose() {
    _sub?.cancel();
    _lifecycle?.dispose();
  }
}

/// Activates the content deep-link listener once. `ref.watch` this high in the
/// widget tree (like the connectivity listener) so it lives for the app's life.
final deepLinkListenerProvider = Provider<DeepLinkListener>((ref) {
  final listener = DeepLinkListener(ref);
  // Desktop/web don't deliver mobile app links; the plugin no-ops there.
  if (!kIsWeb) listener.start();
  ref.onDispose(listener.dispose);
  return listener;
});
