import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/features/catalog/presentation/author_browse_screen.dart';
import 'package:kitabi/features/catalog/presentation/publisher_browse_screen.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Two bugs from one owner report (14 Aug 2026), both on the shared links a
/// reader sends over WhatsApp — `kitabi.in/a/:id`, `/p/:id`, `/b/:id`:
///
/// 1. **The page was a dead end.** Opening a shared author link worked, and
///    then back did nothing: no way to reach Home or anything else. This is
///    CLAUDE.md's own 26 Jul lesson — a route the engine *replaces* into has
///    nothing beneath it, so `pop()` strands the reader — applied to the
///    reading timer at the time but never to the share targets.
/// 2. **A cold start opened the app, not the page.** Tapping the link with the
///    app closed raised Kitabi on Home; only a link tapped while the app was
///    already running reached the right screen.
///
/// These drive the **router** with the raw URI the OS delivers, not
/// `DeepLinkListener`: the listener is not on the delivery path the engine
/// actually uses, and testing it is how the timer bug shipped green.
void main() {
  Widget harness(GoRouter router) => MaterialApp.router(routerConfig: router);

  /// The real redirect's shape: an external rewrite, then a boot gate that
  /// pins everything to splash until the session resolves.
  GoRouter buildRouter({required bool booted}) {
    var ready = booted;
    return GoRouter(
      initialLocation: '/splash',
      redirect: (context, state) {
        final external = externalRouteFor(state.uri);
        if (external != null) {
          pendingExternalTarget = external;
          return external;
        }
        final loc = state.matchedLocation;
        if (!ready) return loc == '/splash' ? null : '/splash';
        if (loc == '/splash') {
          final target = pendingExternalTarget;
          if (target != null) {
            pendingExternalTarget = null;
            return target;
          }
          return '/home';
        }
        if (pendingExternalTarget == loc) pendingExternalTarget = null;
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const Text('splash')),
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(path: '/a/:id', builder: (_, s) => Text('author ${s.pathParameters['id']}')),
        GoRoute(path: '/p/:id', builder: (_, s) => Text('publisher ${s.pathParameters['id']}')),
        GoRoute(path: '/b/:id', builder: (_, s) => Text('book ${s.pathParameters['id']}')),
      ],
    )..routerDelegate.addListener(() {});
  }

  setUp(() => pendingExternalTarget = null);

  group('the raw https link the OS delivers', () {
    for (final (path, label) in [('a', 'author'), ('p', 'publisher'), ('b', 'book')]) {
      testWidgets('kitabi.in/$path/ lands on the $label page, not an error',
          (tester) async {
        final router = buildRouter(booted: true);
        await tester.pumpWidget(harness(router));
        await tester.pumpAndSettle();

        router.go('https://kitabi.in/$path/abc123');
        await tester.pumpAndSettle();

        expect(find.text('$label abc123'), findsOneWidget);
        expect(find.textContaining('Page Not Found'), findsNothing);
      });
    }

    testWidgets('www. is the same link', (tester) async {
      final router = buildRouter(booted: true);
      await tester.pumpWidget(harness(router));
      await tester.pumpAndSettle();

      router.go('https://www.kitabi.in/a/abc123');
      await tester.pumpAndSettle();

      expect(find.text('author abc123'), findsOneWidget);
    });

    testWidgets('a link that arrives during boot survives the splash gate',
        (tester) async {
      // The cold-start case: the URI is delivered while auth/bootstrap are
      // still resolving, so the gate sends it to splash — and the parked
      // target has to be honoured once the session is ready.
      final router = buildRouter(booted: false);
      await tester.pumpWidget(harness(router));
      await tester.pumpAndSettle();

      router.go('https://kitabi.in/a/abc123');
      await tester.pumpAndSettle();
      expect(find.text('splash'), findsOneWidget, reason: 'held while booting');
      expect(pendingExternalTarget, '/a/abc123', reason: 'parked, not discarded');
    });

    testWidgets('another site is not ours', (tester) async {
      expect(externalRouteFor(Uri.parse('https://example.com/a/abc')), isNull);
      expect(externalRouteFor(Uri.parse('https://kitabi.in/discover')), isNull);
      expect(externalRouteFor(Uri.parse('https://kitabi.in/a/')), isNull);
      // Sign-in must keep working: that callback shares the app scheme.
      expect(externalRouteFor(Uri.parse('in.kitabi.kitabi://login-callback/')), isNull);
      // The Live Activity link still resolves through the same door.
      expect(
        externalRouteFor(Uri.parse('in.kitabi.kitabi://reading-timer/xyz')),
        '/reading-timer/xyz',
      );
    });
  });

  group('the way out of a shared page', () {
    /// A link opened from WhatsApp is *replaced* into the stack, so the page
    /// is the only thing on it — exactly what this router models by having no
    /// history to pop back to.
    Future<GoRouter> pumpShared(
      WidgetTester tester,
      String location,
      Widget screen,
    ) async {
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(path: '/a/:id', builder: (_, _) => screen),
          GoRoute(path: '/p/:id', builder: (_, _) => screen),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authorWorksProvider('abc123').overrideWith((ref) async => _body),
          publisherWorksProvider('abc123').overrideWith((ref) async => _body),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('back from a shared author page reaches Home', (tester) async {
      final router = await pumpShared(
        tester,
        '/a/abc123',
        const AuthorBrowseScreen(authorId: 'abc123'),
      );
      expect(router.routerDelegate.currentConfiguration.uri.path, '/a/abc123');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Before the fix this did nothing at all and the reader was stuck.
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('back from a shared publisher page reaches Home', (tester) async {
      final router = await pumpShared(
        tester,
        '/p/abc123',
        const PublisherBrowseScreen(publisherId: 'abc123'),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    });
  });
}

/// Enough of the payload for the page to render its header and an empty list.
const _body = {
  'author': {'id': 'abc123', 'name': 'O.V. Vijayan'},
  'publisher': {'id': 'abc123', 'name': 'DC Books'},
  'works': <Map<String, dynamic>>[],
};
