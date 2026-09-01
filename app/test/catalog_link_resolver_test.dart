import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kitabi/features/catalog/presentation/catalog_link_resolver.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The second half of the 1 Sep 2026 report: a tapped `kitabi.in/book/<slug>`
/// now reaches the app, but every screen and every catalog endpoint addresses a
/// row by UUID. The link's key has to be turned into one — and the old form,
/// `/b/<uuid>`, must not pay a round trip for it: those links are still in
/// Google's index and in every share card ever generated.
void main() {
  Widget harness(Widget child, {List<Override> overrides = const []}) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      );

  const uuid = '11111111-2222-3333-4444-555555555555';

  testWidgets('a UUID key is passed straight through — no request, no wait',
      (tester) async {
    var asked = false;
    await tester.pumpWidget(harness(
      CatalogLinkResolver(
        kind: CatalogLinkKind.book,
        linkKey: uuid,
        builder: (id) => Text('book $id'),
      ),
      overrides: [
        resolvedCatalogIdProvider.overrideWith((ref, args) async {
          asked = true;
          return uuid;
        }),
      ],
    ));

    // First frame: already the real screen, not a skeleton.
    await tester.pump();
    expect(find.text('book $uuid'), findsOneWidget);
    expect(asked, isFalse, reason: 'an id needs no resolving');
  });

  testWidgets('a slug key is resolved before the screen is built', (tester) async {
    await tester.pumpWidget(harness(
      CatalogLinkResolver(
        kind: CatalogLinkKind.book,
        linkKey: 'murder-on-the-orient-express',
        builder: (id) => Text('book $id'),
      ),
      overrides: [
        resolvedCatalogIdProvider((kind: 'book', key: 'murder-on-the-orient-express'))
            .overrideWith((ref) async => uuid),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('book $uuid'), findsOneWidget);
  });

  testWidgets('a slug that resolves to nothing offers a way out', (tester) async {
    // A shared link is often the app's entry point, and the engine *replaces*
    // into that route — with nothing beneath it, an error with only Retry on it
    // is a dead end (CLAUDE.md, 14 Aug 2026).
    final router = GoRouter(
      initialLocation: '/b/gone',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(
          path: '/b/:key',
          builder: (_, state) => CatalogLinkResolver(
            kind: CatalogLinkKind.book,
            linkKey: state.pathParameters['key']!,
            builder: (id) => Text('book $id'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resolvedCatalogIdProvider((kind: 'book', key: 'gone'))
            .overrideWith((ref) async => throw Exception('404')),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(
      AppLocalizations.of(tester.element(find.byType(Scaffold)))!.commonGoHome,
    ));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });
}
