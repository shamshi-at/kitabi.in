import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The add form's fork sheet — "Kitabi already has this book. So what are you
/// adding?" — and what each answer does with the work already on the form.
///
/// The gap these cover: a reader photographs both covers of a book, has them
/// read, and only then discovers the catalogue has a bare stub for it. Every
/// answer on that sheet used to throw the photographs away (owner report,
/// 13 Aug 2026).

const _matchId = '55555555-5555-5555-5555-555555555555';
const _editionId = '66666666-6666-6666-6666-666666666666';

Map<String, dynamic> _match() => {
      'id': _matchId,
      'title': 'Meerasadhu',
      'first_publish_year': 2008,
      'authors': [
        {'id': 'a1', 'name': 'K R Meera'},
      ],
      'edition': {'id': _editionId, 'cover_url': null},
    };

/// The stub the catalogue actually holds: a title, an author, and nothing a
/// reader could use.
Map<String, dynamic> _stubWork() => {
      'id': _matchId,
      'title': 'Meerasadhu',
      'subtitle': null,
      'description': null,
      'language': null,
      'form': null,
      'first_publish_year': 2008,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': 'a1', 'name': 'K R Meera'},
      ],
      'genres': <Map<String, dynamic>>[],
      'editions': <Map<String, dynamic>>[
        {
          'id': _editionId,
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
  Map<String, dynamic> work = const {};
  Map<String, dynamic>? lastEditionPatch;
  Map<String, dynamic>? lastWorkPatch;

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async => similar;

  @override
  Future<Map<String, dynamic>> getWork(String workId) async => work;

  @override
  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async {
    lastWorkPatch = patch;
    return {'applied': true, 'work': work};
  }

  @override
  Future<Map<String, dynamic>> updateEdition(String editionId, Map<String, dynamic> patch) async {
    lastEditionPatch = patch;
    return {...(work['editions'] as List).first as Map<String, dynamic>, ...patch};
  }
}

/// A two-route router: the add form, and a stand-in for wherever a fork sends
/// the reader — recorded so the test can read the `extra` it was handed.
/// Driving the real router matters here: `pushReplacement` is not something a
/// bare MaterialApp can answer, and the seed travels as route `extra`.
({Widget app, List<Object?> pushed}) _harness(
  _Fake fake, {
  String? workId,
  Map<String, dynamic>? seed,
}) {
  final pushed = <Object?>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => AddEditBookScreen(workId: workId, seed: seed),
      ),
      GoRoute(
        path: Routes.catalogAdd,
        builder: (context, state) {
          pushed.add(state.extra);
          final map = state.extra as Map<String, dynamic>;
          return AddEditBookScreen(
            workId: map['workId'] as String?,
            seed: map['seed'] as Map<String, dynamic>?,
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
  await tester.enterText(find.byType(TextFormField).first, 'Meerasadhu');
  // The duplicate check is debounced by 450ms.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Meerasadhu').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing captured, there is nothing to carry over', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..similar = [_match()];
    await tester.pumpWidget(_harness(fake).app);
    await tester.pumpAndSettle();
    await _openFork(tester);

    expect(find.text('Kitabi already has this book.'), findsOneWidget);
    expect(find.text('I own this one — put it on my shelf'), findsOneWidget);
    // Offering "add my covers and details" with no covers and no details
    // would be "I own this one" with extra steps.
    expect(find.text('This is it — add my covers and details'), findsNothing);
  });

  testWidgets('captured details are carried onto the matched entry', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()
      ..similar = [_match()]
      ..work = _stubWork();
    final harness = _harness(fake);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    // Something worth carrying: the Type, which the stub entry has no answer
    // for. (In the wild it is usually two cover photographs; those need an
    // upload, this needs a tap, and both travel the same way.)
    await tester.enterText(find.byType(TextFormField).first, 'Meerasadhu');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meerasadhu').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('This is it — add my covers and details'));
    await tester.pumpAndSettle();

    expect(harness.pushed, hasLength(1));
    final extra = harness.pushed.single as Map<String, dynamic>;
    expect(extra['workId'], _matchId);
    final seed = extra['seed'] as Map<String, dynamic>;
    expect(seed['form'], 'Novel');
  });

  testWidgets('a seed fills the stub and rides the save', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..work = _stubWork();
    await tester.pumpWidget(_harness(fake, workId: _matchId, seed: {
      'cover_url': 'https://x.test/storage/v1/object/public/covers/front.jpg',
      'isbn': '9788126419470',
      'page_count': 96,
      'description': 'A woman, a rope, and a city.',
      'publisher': {'name': 'DC Books'},
      'author_names': const <String>[],
    }).app);
    await tester.pumpAndSettle();

    // The banner says where it came from — a form that silently grew content
    // is a form the reader can't trust.
    expect(find.text('Your covers and details came with you — check and save'), findsOneWidget);

    await tester.tap(find.text('Save to catalogue'));
    await tester.pumpAndSettle();

    // The blurb is Work-level, the rest is the printing's.
    expect(fake.lastWorkPatch?['description'], 'A woman, a rope, and a city.');
    final patch = fake.lastEditionPatch!;
    expect(patch['cover_url'], 'https://x.test/storage/v1/object/public/covers/front.jpg');
    expect(patch['isbn'], '9788126419470');
    expect(patch['page_count'], 96);
    // A publisher by name on an entry that had none used to be dropped.
    expect(patch['publisher_name'], 'DC Books');
  });

  testWidgets('a seed never overwrites what the entry already says', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final filled = _stubWork();
    filled['description'] = 'The catalogue already has a blurb.';
    (filled['editions'] as List).first = {
      ...(filled['editions'] as List).first as Map<String, dynamic>,
      'cover_url': 'https://x.test/storage/v1/object/public/covers/theirs.jpg',
      'page_count': 320,
    };
    final fake = _Fake()..work = filled;
    await tester.pumpWidget(_harness(fake, workId: _matchId, seed: {
      'cover_url': 'https://x.test/storage/v1/object/public/covers/mine.jpg',
      'description': 'Mine, read off a back cover.',
      'page_count': 96,
      'author_names': const <String>[],
    }).app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to catalogue'));
    await tester.pumpAndSettle();

    expect(fake.lastWorkPatch?['description'], 'The catalogue already has a blurb.');
    // Nothing on the edition changed, so no edition patch was sent at all.
    expect(fake.lastEditionPatch, isNull);
  });
}
