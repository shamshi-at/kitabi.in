import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/core/router/shell_scaffold.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/connections/connections_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

GoRouter _shellRouter() => GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => ShellScaffold(navigationShell: shell),
          branches: [
            for (final path in ['/home', '/library', '/lending', '/insights'])
              StatefulShellBranch(routes: [
                GoRoute(path: path, builder: (_, _) => const SizedBox()),
              ]),
          ],
        ),
        GoRoute(
          path: Routes.catalogScan,
          builder: (_, _) => const Scaffold(body: Text('SCANNER')),
        ),
        GoRoute(
          path: Routes.catalogSearch,
          builder: (_, _) => const Scaffold(body: Text('GLOBAL SEARCH')),
        ),
      ],
    );

Widget _wrap(GoRouter router, {ConnectionsData? connections}) {
  return ProviderScope(
    overrides: [
      syncErrorCountProvider.overrideWith((ref) => Stream.value(0)),
      connectionsProvider.overrideWith(
        (ref) async =>
            connections ?? ConnectionsData(incoming: [], outgoing: [], accepted: []),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets('the [+] FAB opens the ISBN scanner directly (scan-first)', (tester) async {
    await tester.pumpWidget(_wrap(_shellRouter()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('SCANNER'), findsOneWidget);
  });

  testWidgets('the FAB is docked at the exact horizontal center of the scaffold',
      (tester) async {
    await tester.pumpWidget(_wrap(_shellRouter()));
    await tester.pump();

    final scaffoldWidth = tester.getSize(find.byType(Scaffold).first).width;
    final fabCenter = tester.getCenter(find.byType(FloatingActionButton));

    // centerDocked computes this from the Scaffold's own width — this is the
    // property a plain "Nth of N equal-width row items" layout can't
    // guarantee once the item count changes (the bug this replaces).
    expect(fabCenter.dx, closeTo(scaffoldWidth / 2, 1.0));
  });

  testWidgets('pending connection requests badge the Lending nav item', (tester) async {
    final withIncoming = ConnectionsData(
      incoming: [
        Connection(
          id: 'c1',
          status: 'pending',
          role: 'addressee',
          other: ConnectionUser(id: 'u9', username: 'anu'),
        ),
      ],
      outgoing: [],
      accepted: [],
    );
    await tester.pumpWidget(_wrap(_shellRouter(), connections: withIncoming));
    await tester.pump();
    await tester.pump();

    // The pip with the pending count sits on the Lending icon.
    expect(find.text('1'), findsOneWidget);
  });
}
