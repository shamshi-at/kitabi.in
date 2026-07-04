import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/features/catalog/presentation/author_browse_screen.dart';
import 'package:kitabi/features/catalog/presentation/catalog_search_screen.dart';
import 'package:kitabi/features/catalog/presentation/publisher_browse_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _authorId = '11111111-1111-1111-1111-111111111111';
const _publisherId = '22222222-2222-2222-2222-222222222222';
const _workId = '33333333-3333-3333-3333-333333333333';

Map<String, dynamic> _work({String? id}) => {
      'id': id ?? _workId,
      'title': 'Chemmeen',
      'subtitle': null,
      'description': null,
      'language': 'Malayalam',
      'first_publish_year': 1956,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': _authorId, 'name': 'Thakazhi Sivasankara Pillai'},
      ],
      'genres': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': '44444444-4444-4444-4444-444444444444',
          'isbn': '9788126415419',
          'language': 'Malayalam',
          'page_count': 184,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': {'id': _publisherId, 'name': 'DC Books'},
          'series': null,
        },
      ],
    };

class _FakeApiClient extends ApiClient {
  Map<String, dynamic>? lastCreatePayload;

  @override
  Future<List<Map<String, dynamic>>> searchCatalog(String query) async {
    if (!query.toLowerCase().contains('chemmeen')) return [];
    final work = _work();
    return [
      {
        'id': work['id'],
        'title': work['title'],
        'first_publish_year': work['first_publish_year'],
        'aggregate_rating': work['aggregate_rating'],
        'authors': work['authors'],
        'edition': (work['editions'] as List).first,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> getAuthorWorks(String authorId) async {
    final work = _work();
    return {
      'author': work['authors'].first,
      'works': [
        {
          'id': work['id'],
          'title': work['title'],
          'first_publish_year': work['first_publish_year'],
          'aggregate_rating': work['aggregate_rating'],
          'authors': work['authors'],
          'edition': (work['editions'] as List).first,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getPublisherWorks(String publisherId) async {
    final work = _work();
    return {
      'publisher': (work['editions'] as List).first['publisher'],
      'works': [
        {
          'id': work['id'],
          'title': work['title'],
          'first_publish_year': work['first_publish_year'],
          'aggregate_rating': work['aggregate_rating'],
          'authors': work['authors'],
          'edition': (work['editions'] as List).first,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getWork(String workId) async => _work(id: workId);

  @override
  Future<Map<String, dynamic>> createWork(Map<String, dynamic> payload) async {
    lastCreatePayload = payload;
    return _work();
  }

  @override
  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async =>
      _work(id: workId);
}

Widget _wrap(Widget child, {ApiClient? apiClient}) {
  return ProviderScope(
    overrides: [
      if (apiClient != null) apiClientProvider.overrideWithValue(apiClient),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets('catalog search shows a matching result with tappable author', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const CatalogSearchScreen(), apiClient: fake));
    await tester.enterText(find.byType(TextField), 'chemmeen');
    await tester.pumpAndSettle();

    // Title/author appear twice — once on the typeset cover, once as tile text.
    expect(find.text('Chemmeen'), findsWidgets);
    expect(find.text('Thakazhi Sivasankara Pillai'), findsWidgets);
  });

  testWidgets('author browse shows the author and their works', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AuthorBrowseScreen(authorId: _authorId), apiClient: fake));
    await tester.pumpAndSettle();

    expect(find.text('Thakazhi Sivasankara Pillai'), findsWidgets);
    expect(find.text('Chemmeen'), findsWidgets);
  });

  testWidgets('publisher browse shows the publisher and their works', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(
      _wrap(const PublisherBrowseScreen(publisherId: _publisherId), apiClient: fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('DC Books'), findsWidgets);
    expect(find.text('Chemmeen'), findsWidgets);
  });

  testWidgets('add form validates a required title before saving', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The button sits at the bottom of a long ListView, past the test
    // viewport — scroll it into view before tapping.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(fake.lastCreatePayload, isNull);
  });

  testWidgets('add form submits a new work to the catalog', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Oru Deshathinte Katha');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload?['title'], 'Oru Deshathinte Katha');
  });

  testWidgets('edit form pre-fills from the existing work', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    expect(find.text('Edit book'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
  });
}
