import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edition_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The add-a-printing form. It renders here mainly so it *renders*: this repo
/// has lost a screen to a paint-time throw that `flutter analyze` and every
/// unit test waved through, and only a device screenshot caught (CLAUDE.md,
/// 21 Jul 2026). A widget test paints, so it catches that class of thing.
const _workId = '77777777-7777-7777-7777-777777777777';

class _Fake extends ApiClient {
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic> extractResult = const {};

  @override
  Future<Map<String, dynamic>> createEdition(
    String workId,
    Map<String, dynamic> payload,
  ) async {
    lastPayload = payload;
    return {'id': 'new-edition', ...payload};
  }

  @override
  Future<Map<String, dynamic>> extractFromCovers({
    String? frontUrl,
    String? backUrl,
    String? part,
  }) async {
    // Split as the server does: the blurb arrives on its own call, behind the
    // identity fields.
    if (part == 'description') return {'description': extractResult['description']};
    return {
      for (final e in extractResult.entries)
        if (e.key != 'description') e.key: e.value,
    };
  }
}

Widget _app(_Fake fake, {Map<String, dynamic>? seed, List<Object?>? popped}) {
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await context.push<Map<String, dynamic>>('/add-edition');
              popped?.add(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/add-edition',
      builder: (context, state) => AddEditionScreen(
        workId: _workId,
        workTitle: 'Naalukett',
        seed: seed,
      ),
    ),
  ]);
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the form paints, blurb and all', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_Fake()));
    await _open(tester);

    expect(find.text('Naalukett'), findsWidgets);
    expect(find.text('DESCRIPTION'), findsOneWidget);
    // The blurb belongs to the book, not the printing — say so, or a reader
    // reasonably expects to be describing this copy.
    expect(find.text('Used only if this book has no description yet'), findsOneWidget);
  });

  testWidgets('a blurb typed here rides the payload as Work-level fill', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    final popped = <Object?>[];
    await tester.pumpWidget(_app(fake, popped: popped));
    await _open(tester);

    await tester.enterText(
      find.byType(TextFormField).last,
      'A house, four wings, and a boy who leaves it.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add edition'));
    await tester.pumpAndSettle();

    expect(fake.lastPayload?['description'], 'A house, four wings, and a boy who leaves it.');
    // Popped with the edition itself, so the caller can send the reader to
    // *this* printing — landing them back on the representative one is how
    // "add to library" kept shelving the parent.
    expect((popped.single as Map)['id'], 'new-edition');
  });

  testWidgets('a seeded cover arrives already in its slot', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, seed: {
      'cover_url': 'https://x.test/storage/v1/object/public/covers/front.jpg',
      'isbn': '9788126403455',
      'page_count': 240,
    }));
    await _open(tester);

    // An own-upload is present, so the "read the covers" rescue path is on.
    expect(find.text('Fill in from photos'), findsOneWidget);

    await tester.tap(find.text('Add edition'));
    await tester.pumpAndSettle();
    expect(fake.lastPayload?['isbn'], '9788126403455');
    expect(fake.lastPayload?['page_count'], 240);
    expect(
      fake.lastPayload?['cover_url'],
      'https://x.test/storage/v1/object/public/covers/front.jpg',
    );
  });
}
