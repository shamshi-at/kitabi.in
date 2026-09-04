// "These are all the same book" — folding typo'd catalogue rows together from
// the add form.
//
// One book typed wrong three times is three rows, every one of them true: same
// book, same author, a letter out of place. Nothing in the app could say so —
// only the admin console could fold them (owner request, 4 Sep 2026).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _keepId = '11111111-1111-1111-1111-111111111111';
const _dupeAId = '22222222-2222-2222-2222-222222222222';
const _dupeBId = '33333333-3333-3333-3333-333333333333';

Map<String, dynamic> _summary(String id, String title) => {
      'id': id,
      'title': title,
      'first_publish_year': 2008,
      'authors': [
        {'id': 'a1', 'name': 'O. V. Vijayan'},
      ],
      'edition': {'id': 'e-$id', 'cover_url': null},
    };

Map<String, dynamic> _survivor() => {
      'id': _keepId,
      'title': 'Dharmapuranam',
      'subtitle': null,
      'description': null,
      'language': 'Malayalam',
      'form': null,
      'first_publish_year': 2008,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': <Map<String, dynamic>>[],
      'genres': <Map<String, dynamic>>[],
      'editions': <Map<String, dynamic>>[
        {
          'id': 'e-keep',
          'isbn': null,
          'language': null,
          'page_count': null,
          'pub_date': null,
          'format': null,
          'cover_url': null,
          'back_cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };

class _Fake extends ApiClient {
  List<Map<String, dynamic>> similar = const [];
  String? mergedInto;
  List<String>? absorbed;
  Object? mergeError;

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async => similar;

  @override
  Future<Map<String, dynamic>> getWork(String workId) async => _survivor();

  @override
  Future<Map<String, dynamic>> mergeWorks(String workId, List<String> absorbIds) async {
    if (mergeError != null) throw mergeError!;
    mergedInto = workId;
    absorbed = absorbIds;
    return {
      'work': _survivor(),
      'merged': [
        for (final id in absorbIds) {'id': id, 'title': 'Dupe $id'},
      ],
    };
  }
}

({Widget app, List<Object?> pushed}) _harness(_Fake fake) {
  final pushed = <Object?>[];
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => AddEditBookScreen()),
      GoRoute(
        path: Routes.catalogAdd,
        builder: (context, state) {
          pushed.add(state.extra);
          final map = state.extra as Map<String, dynamic>;
          return AddEditBookScreen(
            workId: map['workId'] as String?,
            seed: map['seed'] as Map<String, dynamic>?,
            editionId: map['editionId'] as String?,
          );
        },
      ),
    ],
  );
  return (
    app: ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
    pushed: pushed,
  );
}

Future<void> _openFork(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'Dharmapuranam');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dharmapuranam').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one match is a match — there is nothing to merge it with', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..similar = [_summary(_keepId, 'Dharmapuranam')];
    await tester.pumpWidget(_harness(fake).app);
    await tester.pumpAndSettle();
    await _openFork(tester);

    expect(find.text('These are all the same book'), findsNothing);
  });

  testWidgets('several near-matches offer the merge', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()
      ..similar = [
        _summary(_keepId, 'Dharmapuranam'),
        _summary(_dupeAId, 'Dharmapuranm'),
        _summary(_dupeBId, 'Dharma Puranam'),
      ];
    await tester.pumpWidget(_harness(fake).app);
    await tester.pumpAndSettle();
    await _openFork(tester);

    expect(find.text('These are all the same book'), findsOneWidget);
    expect(find.text('3 entries — keep one, fold the rest into it'), findsOneWidget);
  });

  testWidgets('the tapped row is kept and the rest are folded into it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()
      ..similar = [
        _summary(_keepId, 'Dharmapuranam'),
        _summary(_dupeAId, 'Dharmapuranm'),
        _summary(_dupeBId, 'Dharma Puranam'),
      ];
    final harness = _harness(fake);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await _openFork(tester);
    await tester.tap(find.text('These are all the same book'));
    await tester.pumpAndSettle();

    expect(find.text('Which entry should stay?'), findsOneWidget);
    await tester.tap(find.text('Merge 2 entries'));
    await tester.pumpAndSettle();

    expect(fake.mergedInto, _keepId);
    expect(fake.absorbed, unorderedEquals([_dupeAId, _dupeBId]));
    // The merge tidied the shelf; it did not put the reader's covers anywhere.
    // So the survivor opens for improving, carrying what the form held.
    final extra = harness.pushed.single as Map<String, dynamic>;
    expect(extra['workId'], _keepId);
  });

  testWidgets('the reader can keep a different row instead', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()
      ..similar = [
        _summary(_keepId, 'Dharmapuranam'),
        _summary(_dupeAId, 'Dharmapuranm'),
      ];
    await tester.pumpWidget(_harness(fake).app);
    await tester.pumpAndSettle();
    await _openFork(tester);
    await tester.tap(find.text('These are all the same book'));
    await tester.pumpAndSettle();

    // The row they tapped starts as the survivor; the fullest entry is often a
    // different one, so switching must displace it rather than add a second.
    await tester.tap(find.text('Keep this one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge 1 entry'));
    await tester.pumpAndSettle();

    expect(fake.mergedInto, _dupeAId);
    expect(fake.absorbed, [_keepId]);
  });

  testWidgets('a row another reader contributed is refused, and said so', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()
      ..similar = [
        _summary(_keepId, 'Dharmapuranam'),
        _summary(_dupeAId, 'Dharmapuranm'),
      ]
      ..mergeError = DioException(
        requestOptions: RequestOptions(path: '/catalog/works/$_keepId/merge'),
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/catalog/works/$_keepId/merge'),
          statusCode: 403,
          data: {
            'code': 'not_yours_to_merge',
            'message': '“Dharmapuranm” was added by another reader.',
          },
        ),
      );
    final harness = _harness(fake);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await _openFork(tester);
    await tester.tap(find.text('These are all the same book'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge 1 entry'));
    await tester.pumpAndSettle();

    // The server's own sentence, not "check your connection" — which is the
    // whole point of the briefError fix that came with this work.
    expect(find.textContaining('added by another reader'), findsOneWidget);
    expect(harness.pushed, isEmpty);
  });
}
