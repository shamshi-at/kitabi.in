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
import 'package:kitabi/core/widgets/typeset_cover.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/features/catalog/presentation/author_browse_screen.dart';
import 'package:kitabi/features/catalog/presentation/author_picker_screen.dart';
import 'package:kitabi/features/catalog/presentation/browse_screen.dart';
import 'package:kitabi/features/catalog/presentation/catalog_search_screen.dart';
import 'package:kitabi/features/catalog/presentation/chip_picker_sheet.dart';
import 'package:kitabi/features/catalog/presentation/publisher_browse_screen.dart';
import 'package:kitabi/features/profile/providers/profile_providers.dart';
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
  String? lastBrowseLanguage;
  String? lastBrowseSort;

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
    lastBrowseLanguage = language;
    lastBrowseSort = sort;
    if (offset > 0) return []; // one page, then end
    return searchCatalog('chemmeen');
  }

  @override
  Future<List<String>> browseLanguages() async => ['Malayalam', 'Tamil'];

  @override
  Future<List<String>> browseForms() async => ['Novel', 'Poetry'];

  @override
  Future<List<Map<String, dynamic>>> browseGenres() async => [
        {'name': 'Science fiction', 'work_count': 128},
        {'name': 'Fiction', 'work_count': 54},
        {'name': 'Historical', 'work_count': 12},
      ];

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

/// The search page's idle state (S4h). The branch that matters is the one a
/// reader can't see the cause of: when `/me` is unreachable (an expired token
/// makes that routine) or no reading languages are set, the newest-arrivals
/// row must degrade to the catalogue-wide newest rather than silently vanish.
Widget _searchScreen(_FakeApiClient fake, {List<String>? languages}) {
  return _wrap(
    const CatalogSearchScreen(),
    apiClient: fake,
    overrides: [
      // Recent searches read the local db; keep it in memory and empty.
      appDatabaseProvider.overrideWithValue(AppDatabase.forTesting(NativeDatabase.memory())),
      meProvider.overrideWith((ref) async => {
            'id': 'u1',
            'full_name': 'A Reader',
            'preferred_languages': languages ?? const <String>[],
          }),
    ],
  );
}

void main() {
  testWidgets('idle search page filters newest arrivals to the reading language',
      (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_searchScreen(fake, languages: ['Malayalam', 'English']));
    await tester.pumpAndSettle();

    // Header names the language, and the query was actually filtered by it.
    expect(find.text('NEW IN MALAYALAM'), findsOneWidget);
    expect(fake.lastBrowseLanguage, 'Malayalam');
    expect(fake.lastBrowseSort, 'year_desc');
  });

  testWidgets('idle search page falls back to the whole catalogue with no language',
      (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_searchScreen(fake, languages: const []));
    await tester.pumpAndSettle();

    // The row survives — unfiltered — instead of disappearing, and its caption
    // stops claiming a filter that isn't applied.
    expect(find.text('NEW IN THE CATALOGUE'), findsOneWidget);
    expect(find.textContaining('from your profile languages'), findsNothing);
    expect(fake.lastBrowseLanguage, isNull);
    expect(fake.lastBrowseSort, 'year_desc');
  });

  testWidgets('idle search page ranks authors by works in the catalogue', (tester) async {
    final fake = _FakeApiClient();
    await tester.pumpWidget(_searchScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('MOST IN THE CATALOGUE'), findsOneWidget);
    expect(find.text('Thakazhi Sivasankara Pillai'), findsWidgets);
  });

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
  testWidgets('the catalogue filters by Type and genre from the floating control',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const BrowseScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // Nothing narrowed yet — the list is the whole catalog. The old inline
    // filter row is gone; the facets live behind the floating control now.
    expect(find.text('All types'), findsNothing);
    expect(fake.lastBrowseForm, isNull);
    expect(fake.lastBrowseGenre, isNull);

    // Fan the floating control open and reach the filter sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();

    expect(find.text('Filter & sort'), findsOneWidget);
    // The sheet offers only what the catalog actually has.
    expect(find.text('Poetry'), findsOneWidget);
    await tester.tap(find.text('Novel'));
    await tester.tap(find.text('Historical'));
    await tester.tap(find.text('Show books'));
    await tester.pumpAndSettle();

    // Applying re-queries the server (not the fetched page — that would hide
    // matches further into the pagination), and the facets compose.
    expect(fake.lastBrowseForm, 'Novel');
    expect(fake.lastBrowseGenre, 'Historical');
  });

  testWidgets('the catalogue Books tab is a wall of standing covers with quick-add',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const BrowseScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // The Apple-Books grid renders standing covers (TypesetCover) with a
    // quick-add badge, not the old row tiles.
    expect(find.byType(TypesetCover), findsWidgets);
    expect(find.byIcon(Icons.add), findsWidgets);
    // The collapsed floating control is the tune circle; open it and both
    // actions are there.
    expect(find.byIcon(Icons.tune), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
  });
  // ── Type & Genre rows and their picker sheet (M10/M11) ───────────────────
  // The row is a shortcut, not the vocabulary: it stays ~6 chips however big
  // the catalogue gets, and the sheet behind "All N" is where the rest lives
  // — and where duplicate pressure is applied.

  testWidgets('the genre row stays short and offers the whole catalogue behind All N',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    // Capped regardless of how many genres exist, so the form never becomes a
    // wall of chips — that's the whole point of the redesign.
    final genreChips = tester.widgetList<FilterChip>(find.byType(FilterChip)).length;
    expect(genreChips, lessThanOrEqualTo(12)); // 6 type + 6 genre
    expect(find.textContaining('All '), findsNWidgets(2)); // one door per row
  });

  testWidgets('the genre sheet shows book counts so the established spelling wins',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('All ').last); // Genre's door
    await tester.pumpAndSettle();

    // The count is the mechanism, not decoration: 128 books makes "Science
    // fiction" the obvious pick over typing "Sci-fi" beside it.
    expect(find.text('Science fiction'), findsOneWidget);
    expect(find.text('128 books'), findsOneWidget);
  });

  testWidgets('the genre sheet will not offer to create a genre that already exists',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('All ').last);
    await tester.pumpAndSettle();

    // Typing an existing genre in a different case must not invite the exact
    // duplicate the sheet exists to prevent — genres get no case-folding on
    // write, so a "Create" here would fork the shared facet permanently.
    await tester.enterText(find.byType(TextField).last, 'fiction');
    await tester.pumpAndSettle();
    expect(find.textContaining('Create'), findsNothing);
    // Scoped to the sheet: the row behind it carries the same labels.
    expect(
      find.descendant(of: find.byType(ChipPickerSheet), matching: find.text('Fiction')),
      findsOneWidget,
    );

    // A genuinely new one still can be created.
    await tester.enterText(find.byType(TextField).last, 'Sufi');
    await tester.pumpAndSettle();
    expect(find.textContaining('Create'), findsOneWidget);
  });

  testWidgets('a genre picked in the sheet rides the save payload', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Sheet genre book');
    await tester.tap(find.textContaining('All ').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Science fiction'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Done'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilterChip, 'Science fiction'), findsOneWidget);
    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();
    expect(
      (fake.lastCreatePayload?['genre_names'] as List).cast<String>(),
      contains('Science fiction'),
    );
  });

  testWidgets('a type outside the vocabulary can be created and folds onto a known one',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _FakeApiClient();
    await tester.pumpWidget(_wrap(const AddEditBookScreen(), apiClient: fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'A Novella');
    await tester.tap(find.textContaining('All ').first); // Type's door
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Novella');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Create'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.textContaining('All ').first);
    await tester.pumpAndSettle();
    // "  novel " is really Novel — the sheet suppresses Create for an exact
    // case-insensitive match, so the only way through is the existing row,
    // and the facet can't split into novel/Novel.
    await tester.enterText(find.byType(TextField).last, '  novel ');
    await tester.pumpAndSettle();
    expect(find.textContaining('Create'), findsNothing);
    await tester.tap(
      find.descendant(of: find.byType(ChipPickerSheet), matching: find.text('Novel')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to catalog'));
    await tester.pumpAndSettle();
    expect(fake.lastCreatePayload?['form'], 'Novel');
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
