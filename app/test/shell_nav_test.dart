import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/core/router/shell_scaffold.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/connections/connections_providers.dart';
import 'package:kitabi/features/library/providers/reading_timer_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Never touches the database — this suite is about nav-bar layout, not the
/// reading timer, so hydration (which would otherwise pull in a real
/// disk-backed AppDatabase and leave pending timers behind) is skipped.
class _StubActiveSessionController extends ActiveSessionController {
  @override
  ActiveSession? build() => null;
}

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
      activeSessionProvider.overrideWith(_StubActiveSessionController.new),
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

  testWidgets('the [+] tile sits at the exact horizontal center of the bar',
      (tester) async {
    await tester.pumpWidget(_wrap(_shellRouter()));
    await tester.pump();

    final scaffoldWidth = tester.getSize(find.byType(Scaffold).first).width;
    final addCenter = tester.getCenter(find.byIcon(Icons.add));

    // Five equal slots → the middle slot's centre is the screen centre. Guards
    // against a 6th item creeping in and shoving "+" off-centre again.
    expect(addCenter.dx, closeTo(scaffoldWidth / 2, 1.0));
    // And it must NOT be a FloatingActionButton: the FAB lives in the
    // Scaffold's floating layer, which rendered ON TOP of every modal bottom
    // sheet (the "+" overlapped the lend sheet's own button — owner report).
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a modal bottom sheet covers the [+] tile (no punch-through)',
      (tester) async {
    await tester.pumpWidget(_wrap(_shellRouter()));
    await tester.pump();

    final addCenter = tester.getCenter(find.byIcon(Icons.add));

    // Open a modal sheet from inside the shell, tall enough to reach the bar
    // — like the lend / log-borrowed sheets do in the real app.
    final shellContext = tester.element(find.byIcon(Icons.home));
    showModalBottomSheet<void>(
      context: shellContext,
      isScrollControlled: true,
      builder: (_) => const SizedBox(height: 500, child: Center(child: Text('SHEET'))),
    );
    await tester.pumpAndSettle();

    // Whatever is hit-testable at the add tile's position must now be the
    // sheet's surface, not the tile — tapping there must NOT open the scanner.
    await tester.tapAt(addCenter);
    await tester.pumpAndSettle();
    expect(find.text('SCANNER'), findsNothing);
    expect(find.text('SHEET'), findsOneWidget);
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
