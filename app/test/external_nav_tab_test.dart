import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';

/// A tab is a branch of the `StatefulShellRoute`, and a branch root cannot be
/// *pushed*: go_router renders the branch's page but leaves the shell's own
/// location alone, so the nav bar keeps highlighting the tab you were on and
/// `currentConfiguration.uri` keeps reporting it. Everything downstream then
/// reasons from the wrong place — the duplicate guard in
/// [navigateFromExternal], the redirect, `goBranch`.
///
/// Owner report, 29 Aug 2026: A lends B a book, B taps the notification, and
/// it "just opens the home page". `pushTapRoute` returns `/lending` for all
/// three lending types, which is the one tab root an external tap can reach.
void main() {
  late StatefulNavigationShell shell;

  GoRouter buildRouter() => GoRouter(
        initialLocation: Routes.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              shell = navigationShell;
              return Scaffold(
                body: navigationShell,
                bottomNavigationBar: Text('tab ${navigationShell.currentIndex}'),
              );
            },
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(path: Routes.home, builder: (_, _) => const Text('home')),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(path: Routes.lendingLedger, builder: (_, _) => const Text('ledger')),
              ]),
            ],
          ),
          // A top-level route, for contrast: this one must still be *pushed*,
          // so the reader can get back off it.
          GoRoute(
            path: '/reading-timer/:id',
            builder: (_, state) => Text('timer ${state.pathParameters['id']}'),
          ),
        ],
      );

  testWidgets('an external tap on a tab actually switches to it', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    navigateFromExternal(router, Routes.lendingLedger);
    await tester.pumpAndSettle();

    expect(find.text('ledger'), findsOneWidget);
    // The three things a push leaves behind, each of which lies to something
    // downstream about where the reader is.
    expect(shell.currentIndex, 1, reason: 'the nav bar must follow the reader');
    expect(find.text('tab 1'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.lendingLedger,
      reason: 'the location the next redirect resolves from must be the ledger',
    );
  });

  testWidgets('a second tap on the same tab changes nothing', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    navigateFromExternal(router, Routes.lendingLedger);
    await tester.pumpAndSettle();
    final depth = router.routerDelegate.currentConfiguration.matches.length;

    navigateFromExternal(router, Routes.lendingLedger);
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, depth);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.lendingLedger);
  });

  testWidgets('a route outside the shell is still pushed, so it can be left',
      (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    navigateFromExternal(router, '/reading-timer/le-1');
    await tester.pumpAndSettle();
    expect(find.text('timer le-1'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
