import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';

/// The bug this guards: tapping the iOS Live Activity showed **"Page Not
/// Found — GoException: no routes for location:
/// `in.kitabi.kitabi://reading-timer/<id>`" on a real iPhone (owner report,
/// 26 Jul 2026).
///
/// Flutter's engine hands an incoming deep link straight to the router, so the
/// *whole URI* — scheme, host and all — arrives as a location to match, and
/// nothing in the route table is named that. The previous tests all exercised
/// `DeepLinkListener`, which this delivery path never touches; they passed
/// while the feature was broken. This one drives the router itself.
void main() {
  Widget harness(GoRouter router) => MaterialApp.router(routerConfig: router);

  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        redirect: (context, state) {
          final external = readingTimerRouteFor(state.uri);
          if (external != null) return external;
          return null;
        },
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(
            path: '/reading-timer/:libraryEntryId',
            builder: (_, state) =>
                Text('timer ${state.pathParameters['libraryEntryId']}'),
          ),
        ],
      );

  testWidgets('the raw Live Activity URI lands on the timer, not an error page',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(harness(router));

    // Exactly what the engine delivers when the card is tapped.
    router.go('in.kitabi.kitabi://reading-timer/ef85b8de-def5-428b-9c98-292ba4fa9dbb');
    await tester.pumpAndSettle();

    expect(find.text('timer ef85b8de-def5-428b-9c98-292ba4fa9dbb'), findsOneWidget);
    expect(find.textContaining('Page Not Found'), findsNothing);
  });

  testWidgets('an unrelated custom-scheme link is still an ordinary miss',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(harness(router));

    // The OAuth callback must not be swallowed into the timer.
    expect(
      readingTimerRouteFor(Uri.parse('in.kitabi.kitabi://login-callback/')),
      isNull,
    );
  });
}
