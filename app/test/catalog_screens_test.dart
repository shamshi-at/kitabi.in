import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/features/catalog/presentation/author_browse_screen.dart';
import 'package:kitabi/features/catalog/presentation/author_picker_screen.dart';
import 'package:kitabi/features/catalog/presentation/browse_screen.dart';
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
  Map<String, dynamic> extractResult = const {};
  String? lastExtractFront;
  String? lastExtractBack;

  /// When set, extraction blocks on this until the test completes it — lets a
  /// test assert the "reading your cover" overlay is visible mid-extraction.
  Completer<void>? extractGate;

  /// Canned duplicate suggestions for the add form's typo check.
  List<Map<String, dynamic>> similarResult = const [];
  String? lastSimilarQuery;

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async {
    lastSimilarQuery = title;
    return similarResult;
  }

  @override
  Future<Map<String, dynamic>> extractFromCovers({String? frontUrl, String? backUrl}) async {
    lastExtractFront = frontUrl;
    lastExtractBack = backUrl;
    if (extractGate != null) await extractGate!.future;
    return extractResult;
  }

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

  int searchAllCalls = 0;

  @override
  Future<Map<String, dynamic>> searchAll(String query) async {
    searchAllCalls++;
    return {
      'works': await searchCatalog(query),
      'authors': <Map<String, dynamic>>[],
      'publishers': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> createAuthor(Map<String, dynamic> payload) async {
    return {'id': _authorId, ...payload};
  }

  /// The facets the browse screen last asked the server for — the filters are
  /// server-side (the list is paged), so the query is the thing to assert.
  String? lastBrowseForm;
  String? lastBrowseGenre;

  @override
  Future<List<Map<String, dynamic>>> browseWorks({
    int limit = 40,
    int offset = 0,
    String? language,
    String? form,
    String? genre,
    String sort = 'title',
  }) async {
    lastBrowseForm = form;
    lastBrowseGenre = genre;
    if (offset > 0) return []; // one page, then end
    return searchCatalog('chemmeen');
  }

  @override
  Future<List<String>> browseLanguages() async => ['Malayalam', 'Tamil'];

  @override
  Future<List<String>> browseForms() async => ['Novel', 'Poetry'];

  @override
  Future<List<String>> browseGenres() async => ['Fiction', 'Historical'];

  @override
  Future<List<Map<String, dynamic>>> browseAuthors({
    int limit = 40,
    int offset = 0,
    String sort = 'name',
  }) async {
    if (offset > 0) return [];
    return [
      {'id': _authorId, 'name': 'Thakazhi Sivasankara Pillai', 'primary_language': 'Malayalam'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> browsePublishers({
    int limit = 40,
    int offset = 0,
    String sort = 'name',
  }) async {
    if (offset > 0) return [];
    return [
      {'id': _publisherId, 'name': 'DC Books'},
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
  Future<List<Map<String, dynamic>>> searchAuthors(String query) async {
    if (!query.toLowerCase().startsWith('k')) return [];
    return [
      {'id': _authorId, 'name': 'Kamala Das'},
    ];
  }

  /// Optional cover URL injected into the work's edition — lets tests light up
  /// the fill-from-photos button (it only shows for our own uploads).
  String? workCoverUrl;

  @override
  Future<Map<String, dynamic>> getWork(String workId) async {
    final work = _work(id: workId);
    ((work['editions'] as List).first as Map<String, dynamic>)['cover_url'] = workCoverUrl;
    return work;
  }

  @override
  Future<Map<String, dynamic>> createWork(Map<String, dynamic> payload) async {
    lastCreatePayload = payload;
    return _work();
  }

  /// The edition patch the edit form sent, if any — page count, ISBN, format,
  /// publisher and series all live on the Edition, so `updateWork` ignoring
  /// them means the *patch* is the only place an edit to them can show up.
  Map<String, dynamic>? lastEditionPatch;

  @override
  Future<Map<String, dynamic>> updateEdition(String editionId, Map<String, dynamic> patch) async {
    lastEditionPatch = patch;
    final edition = Map<String, dynamic>.from((_work()['editions'] as List).first as Map);
    return {...edition, ...patch};
  }

  /// When false, mirrors the API queueing the edit for the contributor's
  /// approval instead of applying it live.
  bool updateApplies = true;
  int updateCalls = 0;

  @override
  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async {
    updateCalls++;
    return {
      'applied': updateApplies,
      'revision_id': updateApplies ? null : 'rev-1',
      'work': _work(id: workId),
    };
  }
}

Widget _wrap(Widget child, {ApiClient? apiClient, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      if (apiClient != null) apiClientProvider.overrideWithValue(apiClient),
      ...overrides,
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
    await tester.pump(const Duration(milliseconds: 350)); // remote debounce
    await tester.pumpAndSettle();

    // Title/author appear twice — once on the typeset cover, once as tile text.
    expect(find.text('Chemmeen'), findsWidgets);
    expect(find.text('Thakazhi Sivasankara Pillai'), findsWidgets);
  });

  testWidgets('fast typing debounces to a single catalog request', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const CatalogSearchScreen(), apiClient: fake));

    // Six keystrokes in quick succession — under the 300ms debounce window.
    for (final partial in ['c', 'ch', 'che', 'chem', 'chemme', 'chemmeen']) {
      await tester.enterText(find.byType(TextField), partial);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 350)); // settle the debounce
    await tester.pumpAndSettle();

    expect(fake.searchAllCalls, 1); // one request, not six
    expect(find.text('Chemmeen'), findsWidgets);
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
    // A tall viewport so the whole form (and its Save button) fits without
    // scrolling — the ListView lazily builds off-screen children, so a
    // scroll-then-find approach is brittle.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(fake.lastCreatePayload, isNull);
  });

  testWidgets('add form submits a new work to the catalog', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Oru Deshathinte Katha');
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload?['title'], 'Oru Deshathinte Katha');
    // Create mode lands on the confirmation popup with the created book's
    // metadata (the fake API returns Chemmeen) and the three actions.
    expect(find.text('ADDED TO THE CATALOG'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
    expect(find.text('Add to library'), findsOneWidget);
    expect(find.text('Create another'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('popup "Add to library" walks Adding → Added and writes to Drift', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // runAsync surfaces google_fonts' async font-miss — cosmetic, filter it
    // (same setup as review_flow_test.dart).
    GoogleFonts.config.allowRuntimeFetching = false;
    final reportOriginal = reportTestException;
    reportTestException = (details, testDescription) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, testDescription);
    };

    // Real drift + real repositories; never closed (fake-async/close deadlock).
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(
      const AddEditBookScreen(),
      apiClient: fake,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Oru Deshathinte Katha');
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add to library'));
    await settle();

    expect(find.text('Added ✓'), findsOneWidget);
    final entry = await tester.runAsync(
      () => db.libraryEntriesDao.getByEditionId('44444444-4444-4444-4444-444444444444'),
    );
    expect(entry, isNotNull);
    final cached = await tester.runAsync(
      () => db.cachedBooksDao.getByEditionId('44444444-4444-4444-4444-444444444444'),
    );
    expect(cached?.title, 'Chemmeen');

    // Flush drift's stream-close timers before the pending-timer check, and
    // restore the exception reporter inside the body (the binding verifies it
    // before teardowns run).
    await tester.pumpWidget(const SizedBox());
    await settle();
    reportTestException = reportOriginal;
  });

  testWidgets('popup "Create another" clears the form for the next book', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Oru Deshathinte Katha');
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create another'));
    await tester.pumpAndSettle();

    // Popup gone, same screen, blank title field.
    expect(find.text('ADDED TO THE CATALOG'), findsNothing);
    expect(find.text('Save to catalog'), findsOneWidget);
    final titleField = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(titleField.controller?.text, isEmpty);
  });

  testWidgets('description expands into a full-screen editor and carries text back',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The grouped fields moved into the collapsed "More details" section.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit full screen'));
    await tester.pumpAndSettle();

    expect(find.text('Done'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'A long back-cover blurb that deserves room to breathe.',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The shared controller carried the text back into the form field.
    expect(
      find.text('A long back-cover blurb that deserves room to breathe.'),
      findsOneWidget,
    );
  });

  testWidgets('format field opens a themed picker sheet and applies the choice', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The grouped fields moved into the collapsed "More details" section.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();

    // Default format shows in the select box (no Material dropdown).
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Paperback'), findsOneWidget);

    // Tapping opens the bottom-sheet picker with all options.
    await tester.tap(find.text('Paperback'));
    await tester.pumpAndSettle();
    expect(find.text('Choose format'), findsOneWidget);
    expect(find.text('Hardcover'), findsOneWidget);

    await tester.tap(find.text('Hardcover'));
    await tester.pumpAndSettle();
    // The pick sticks and the sheet is gone.
    expect(find.text('Hardcover'), findsOneWidget);
    expect(find.text('Paperback'), findsNothing);
  });

  testWidgets('series toggle reveals the grouped series fields', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The grouped fields moved into the collapsed "More details" section.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();

    // Hidden by default (standalone book).
    expect(find.text('SERIES NAME'), findsNothing);
    expect(find.text('WHICH BOOK?'), findsNothing);

    await tester.tap(find.text('Part of a series'));
    await tester.pumpAndSettle();

    expect(find.text('SERIES NAME'), findsOneWidget);
    expect(find.text('WHICH BOOK?'), findsOneWidget);
  });

  testWidgets('a scanned-but-unmatched ISBN carries into the blank form', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(
      _wrap(const AddEditBookScreen(initialIsbn: '9788126415419'), apiClient: fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('9788126415419'), findsOneWidget);
  });

  testWidgets('fill-from-photos prefills only the empty fields', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient()
      ..workCoverUrl = 'https://proj.supabase.co/storage/v1/object/public/covers/x.jpg'
      ..extractResult = {
        'title': 'Wrong Title Must Not Overwrite',
        'authors': ['Ignored Author'],
        'publisher': null,
        'description': 'A love story on the Kerala coast.',
        'series_name': null,
        'series_number': null,
        'language': null,
        'isbn': '9789386906366', // empty ISBN field → should fill
      };
    // Edit mode: title/author/publisher already filled, description empty.
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fill in from photos'));
    await tester.pumpAndSettle();

    // The uploaded-bucket URL was what got sent for reading.
    expect(fake.lastExtractFront, contains('/covers/x.jpg'));
    // Empty description filled; existing title/author/ISBN all left untouched
    // (this edition already has an ISBN, so the extracted one must not win).
    expect(find.text('A love story on the Kerala coast.'), findsOneWidget);
    expect(find.text('9789386906366'), findsNothing);
    expect(find.text('9788126415419'), findsOneWidget);
    expect(find.text('Wrong Title Must Not Overwrite'), findsNothing);
    expect(find.text('Ignored Author'), findsNothing);
    expect(find.text('Chemmeen'), findsWidgets);
  });

  testWidgets('extraction fills the ISBN into a blank field', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient()
      ..workCoverUrl = 'https://proj.supabase.co/storage/v1/object/public/covers/x.jpg'
      ..extractResult = {'isbn': '9789386906366'};
    // New book: every field starts empty, but we need an uploaded cover to show
    // the button — the work loader injects one via workCoverUrl on getWork, so
    // edit an existing work whose ISBN we first clear.
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    // Clear the pre-filled ISBN so the field is empty for the fill.
    final isbnField = find.widgetWithText(TextFormField, '9788126415419');
    await tester.enterText(isbnField, '');
    await tester.tap(find.text('Fill in from photos'));
    await tester.pumpAndSettle();

    expect(find.text('9789386906366'), findsOneWidget);
  });

  testWidgets('typing a near-duplicate title quietly suggests the existing book', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient()
      ..similarResult = [
        {
          'id': _workId,
          'title': 'Chemmeen',
          'first_publish_year': 1956,
          'aggregate_rating': null,
          'authors': [
            {'id': _authorId, 'name': 'Thakazhi Sivasankara Pillai'},
          ],
          'edition': {'id': 'e-1', 'cover_url': null},
        },
      ];
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // Type a typo'd title; the lookup is debounced 450ms.
    await tester.enterText(find.byType(TextFormField).first, 'Chemeen');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(fake.lastSimilarQuery, 'Chemeen');
    expect(find.text('Already in the catalog?'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);

    // Dismiss → panel gone, and further typing doesn't bring it back.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Already in the catalog?'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Chemeen again');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Already in the catalog?'), findsNothing);
  });

  testWidgets('duplicate suggestions never appear in edit mode', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient()
      ..similarResult = [
        {
          'id': _workId,
          'title': 'Chemmeen',
          'first_publish_year': null,
          'aggregate_rating': null,
          'authors': const <Map<String, dynamic>>[],
          'edition': null,
        },
      ];
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Chemeen');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // Edit mode: no listener, no lookup, no panel.
    expect(fake.lastSimilarQuery, isNull);
    expect(find.text('Already in the catalog?'), findsNothing);
  });

  testWidgets('a reading-your-cover overlay shows while extraction is in flight', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final gate = Completer<void>();
    final fake = _FakeApiClient()
      ..workCoverUrl = 'https://proj.supabase.co/storage/v1/object/public/covers/x.jpg'
      ..extractGate = gate
      ..extractResult = {'title': 'കയർ'};
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fill in from photos'));
    await tester.pump(); // start the extraction future (still gated)

    // The overlay is up while the call is in flight.
    expect(find.text('Reading your cover…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    // Overlay gone once extraction resolves.
    expect(find.text('Reading your cover…'), findsNothing);
  });

  testWidgets('author picker searches and surfaces an existing author', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AuthorPickerScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Kam');
    await tester.pump(const Duration(milliseconds: 300)); // clear the debounce
    await tester.pumpAndSettle();

    // The catalog author appears as a selectable result tile.
    expect(find.text('Kamala Das'), findsOneWidget);
    // …and the "add a new author" affordance is offered alongside.
    expect(find.text('Add a new author'), findsOneWidget);
  });

  testWidgets('browse screen lists catalog books on the Books tab', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const BrowseScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The three tabs and the first page of books render.
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Authors'), findsOneWidget);
    expect(find.text('Publishers'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
  });

  testWidgets('edit form pre-fills from the existing work', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    expect(find.text('Edit book'), findsOneWidget);
    expect(find.text('Chemmeen'), findsWidgets);
  });

  testWidgets("editing someone else's book reports pending approval", (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient()..updateApplies = false;
    // A real router host: the save flow pops the screen, which needs GoRouter
    // (exactly like the app) — popping without one corrupts the flow mid-save.
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/edit', builder: (_, _) => AddEditBookScreen(workId: _workId)),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'ചെമ്മീൻ (revised)');
    await tester.tap(find.text('Save to catalog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.updateCalls, 1);
    expect(
      find.text('Edit sent — the reader who added this book will review it.'),
      findsOneWidget,
    );
  });
  testWidgets('fresh create form: capture strip leads, details fold, save is sticky',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The two capture paths lead, full-width, before any field.
    expect(find.text('Scan the barcode'), findsOneWidget);
    expect(find.text('Photograph the covers'), findsOneWidget);

    // The grouped fields are folded behind one summarized disclosure row.
    expect(find.text('More details'), findsOneWidget);
    expect(find.text('Series · publisher · ISBN · pages · format · description'),
        findsOneWidget);
    expect(find.text('Part of a series'), findsNothing); // inside the fold

    // Type and genre are primary — every option a visible one-tap chip.
    expect(find.text('TYPE · PICK ONE'), findsOneWidget);
    expect(find.text('Novel'), findsOneWidget);
    expect(find.text('GENRE · TAP ALL THAT FIT'), findsOneWidget);
    expect(find.text('Fiction'), findsOneWidget);

    // Save is sticky — hit-testable without any scrolling.
    expect(find.text('Save to catalog').hitTestable(), findsOneWidget);
  });

  testWidgets('type and genre chips ride the create payload', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Khasakkinte Itihasam');
    await tester.tap(find.text('Novel'));
    await tester.tap(find.text('Fiction'));
    await tester.pump();
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload?['form'], 'Novel');
    expect(fake.lastCreatePayload?['genre_names'], contains('Fiction'));
  });

  testWidgets('tapping the selected type chip again clears it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Some Book');
    await tester.tap(find.text('Novel'));
    await tester.pump();
    await tester.tap(find.text('Novel')); // deselect
    await tester.pump();
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    expect(fake.lastCreatePayload?['form'], isNull);
  });
  testWidgets('the catalog browse screen filters by Type and genre server-side',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const BrowseScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // Both facets start unset — the list is the whole catalog.
    expect(find.text('All types'), findsOneWidget);
    expect(find.text('All genres'), findsOneWidget);
    expect(fake.lastBrowseForm, isNull);
    expect(fake.lastBrowseGenre, isNull);

    // The dropdowns offer only what the catalog actually has.
    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    expect(find.text('Poetry').hitTestable(), findsWidgets);
    await tester.tap(find.text('Novel').last);
    await tester.pumpAndSettle();

    // Picking one re-queries the server rather than filtering the fetched page
    // (which would hide matches further into the pagination).
    expect(fake.lastBrowseForm, 'Novel');

    await tester.tap(find.text('All genres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Historical').last);
    await tester.pumpAndSettle();

    // Facets compose — the Type filter survives picking a genre.
    expect(fake.lastBrowseGenre, 'Historical');
    expect(fake.lastBrowseForm, 'Novel');
  });
  testWidgets('a type outside the suggested list can be typed in and saved', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'A Novella');
    await tester.tap(find.text('＋ Other').first); // Type's — Genre has one too now
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Novella');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // It shows as its own selected chip, and rides the payload.
    expect(find.widgetWithText(FilterChip, 'Novella'), findsOneWidget);
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();
    expect(fake.lastCreatePayload?['form'], 'Novella');
  });

  testWidgets('a custom type that is really a known one folds onto it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Case folded');
    await tester.tap(find.text('＋ Other').first); // Type's
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  novel ');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    // Mirrors the server's fold, so the facet can't split into novel/Novel.
    expect(fake.lastCreatePayload?['form'], 'Novel');
  });
  testWidgets('genre gets the same "＋ Other" chip as type, and adds custom genres',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // One on each row — the two "add" affordances now look and work alike
    // (they used to be a chip vs. a free-text field).
    expect(find.text('＋ Other'), findsNWidgets(2));
    // The old free-text field is gone.
    expect(find.text('＋ ADD ANOTHER GENRE'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Custom genre book');
    await tester.tap(find.text('＋ Other').last); // Genre's
    await tester.pumpAndSettle();
    // One dialog can add several, as the comma-separated field used to.
    await tester.enterText(find.byType(TextField).last, 'Sufi, Devotional');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // Each arrives as its own selected chip, beside the suggestions.
    expect(find.widgetWithText(FilterChip, 'Sufi'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Devotional'), findsOneWidget);

    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();
    final sent = (fake.lastCreatePayload?['genre_names'] as List).cast<String>();
    expect(sent, containsAll(<String>['Sufi', 'Devotional']));
  });

  testWidgets('a custom genre that is really a suggested one folds onto it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Folded genre');
    await tester.tap(find.text('＋ Other').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'fiction');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    // Selects the existing Fiction chip instead of adding a near-duplicate.
    expect(find.widgetWithText(FilterChip, 'Fiction'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'fiction'), findsNothing);
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();
    expect((fake.lastCreatePayload?['genre_names'] as List), contains('Fiction'));
  });
  testWidgets('editing sends changed edition fields — a page count actually saves',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    // Correct the page count (edit mode opens "More details" already).
    final pagesField = find.descendant(
      of: find.ancestor(of: find.text('PAGES'), matching: find.byType(Column)).first,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(pagesField, '250'); // was 184
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    // The Work payload can't carry it (the API ignores edition fields there),
    // so it has to ride the edition patch — this is the bug the owner hit:
    // the form said "saved" and the page count never moved.
    expect(fake.lastEditionPatch, isNotNull,
        reason: 'an edition-level edit must be PATCHed to the edition');
    expect(fake.lastEditionPatch?['page_count'], 250);
    // Untouched edition fields must not ride along and rewrite themselves.
    expect(fake.lastEditionPatch?.containsKey('isbn'), isFalse);
  });

  testWidgets('editing without touching the edition sends no edition patch', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(AddEditBookScreen(workId: _workId), apiClient: fake));
    await tester.pumpAndSettle();

    // Change only a Work field.
    await tester.enterText(find.byType(TextFormField).first, 'Chemmeen (revised)');
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();

    // Nothing on the edition changed, so it must not be patched — a save must
    // not rewrite fields the reader never touched.
    expect(fake.lastEditionPatch, isNull);
  });
}
