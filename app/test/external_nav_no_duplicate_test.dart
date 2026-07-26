import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';

/// Regression test for the duplicate route an external tap used to stack.
///
/// Found on an Android emulator (26 Jul 2026) by tapping the live reading
/// notification while the timer screen was *already* open: it pushed a second
/// copy of the same screen, and when the top one stopped the sitting, the
/// buried copy's "someone else stopped this" guard fired and popped the reader
/// out to Home — so Stop & log looked like it had thrown the page question away.
///
/// The assertion is on the router's **match list**, not on what's rendered: a
/// stacked duplicate is offstage, so `find.text` reports one widget either way
/// and a test written that way would pass against the bug.
void main() {
  Widget harness(GoRouter router) => MaterialApp.router(routerConfig: router);

  // Not '/' — that's Routes.splash, where navigateFromExternal deliberately
  // parks the target instead of navigating.
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(
            path: '/reading-timer/:id',
            builder: (_, state) => Text('timer ${state.pathParameters['id']}'),
          ),
        ],
      );

  int depth(GoRouter router) => router.routerDelegate.currentConfiguration.matches.length;

  testWidgets('a tap that lands where you already are does not stack a copy',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(harness(router));

    navigateFromExternal(router, '/reading-timer/le-1');
    await tester.pumpAndSettle();
    expect(find.text('timer le-1'), findsOneWidget);
    final afterFirst = depth(router);

    // The notification is tapped again while its own screen is showing.
    navigateFromExternal(router, '/reading-timer/le-1');
    await tester.pumpAndSettle();
    expect(depth(router), afterFirst, reason: 'the stack must not grow');

    // One back gesture leaves the timer entirely — with the duplicate it landed
    // on an identical screen, which is exactly what the reader saw.
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('timer le-1'), findsNothing);
  });

  testWidgets('a different book still pushes', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(harness(router));

    navigateFromExternal(router, '/reading-timer/le-1');
    await tester.pumpAndSettle();
    final afterFirst = depth(router);
    navigateFromExternal(router, '/reading-timer/le-2');
    await tester.pumpAndSettle();

    expect(depth(router), afterFirst + 1);
    expect(find.text('timer le-2'), findsOneWidget);
  });

  testWidgets('a target arriving on splash is parked, not navigated', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('splash')),
        GoRoute(path: '/reading-timer/:id', builder: (_, _) => const Text('timer')),
      ],
    );
    await tester.pumpWidget(harness(router));

    navigateFromExternal(router, '/reading-timer/le-9');
    await tester.pumpAndSettle();

    expect(find.text('splash'), findsOneWidget);
    expect(pendingExternalTarget, '/reading-timer/le-9');
    pendingExternalTarget = null;
  });
}
