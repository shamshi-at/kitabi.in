import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/core/router/shell_scaffold.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

void main() {
  testWidgets('the [+] FAB opens the ISBN scanner directly (scan-first)', (tester) async {
    final router = GoRouter(
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
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncErrorCountProvider.overrideWith((ref) => Stream.value(0)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('SCANNER'), findsOneWidget);
  });
}
