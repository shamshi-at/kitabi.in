import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';

/// Listens for incoming kitabi.in universal/app links (the shareable
/// /b/:id, /a/:id, /p/:id paths) and routes them to the matching in-app
/// screen. Deliberately scoped to https kitabi.in hosts only, so it never
/// touches the Supabase OAuth callback (a custom `in.kitabi.kitabi://` scheme
/// handled by supabase_flutter's own listener) — both share the app_links
/// stream and each ignores the other's links.
class DeepLinkListener {
  DeepLinkListener(this._ref);

  final Ref _ref;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  static const _hosts = {'kitabi.in', 'www.kitabi.in'};

  void start() {
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    // A cold-start link (app launched by tapping the link) arrives here.
    unawaited(_appLinks.getInitialLink().then((uri) {
      if (uri != null) _handle(uri);
    }).catchError((_) {}));
  }

  void _handle(Uri uri) {
    if (!uri.isScheme('https') || !_hosts.contains(uri.host)) return;
    final segments = uri.pathSegments;
    if (segments.length < 2) return;
    final id = segments[1];
    if (id.isEmpty) return;
    final router = _ref.read(routerProvider);
    switch (segments[0]) {
      case 'b':
        router.go('/b/$id');
      case 'a':
        router.go('/a/$id');
      case 'p':
        router.go('/p/$id');
      default:
        break;
    }
  }

  void dispose() {
    _sub?.cancel();
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
