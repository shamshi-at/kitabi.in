// Saving an add form that a barcode scan filled in.
//
// A scan resolves through the catalogue — an OpenLibrary hit is cached on the
// way past — so by the time "Use these details" hands the Work back, the book
// is in the catalogue without exception. `_applyScannedWork` says exactly that,
// and acts on it by removing the book from the duplicate-match panel. The save
// then posted a create anyway: the one warning that would have caught the
// duplicate was suppressed *because* the duplicate was certain. Seven identical
// Dharmapuranams in the production logs, each stopped only by the ISBN's unique
// index (owner report, 4 Sep 2026) — and a scanned printing with no ISBN would
// have gone through.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

const _workId = '62ab34ad-6957-4f3f-bd5b-a55bbdabab26';
const _firstEditionId = 'aaaaaaaa-0000-0000-0000-000000000001';
const _scannedEditionId = 'bbbbbbbb-0000-0000-0000-000000000002';

/// A Work with two printings, the scanned one second — so anything that reaches
/// for `editions.first` picks the wrong copy and the test can see it.
Map<String, dynamic> _scannedWork() => {
      'id': _workId,
      'title': 'Dharmapuranam',
      'subtitle': null,
      'description': null,
      'language': 'Malayalam',
      'form': null,
      'first_publish_year': 2008,
      'aggregate_rating': null,
      'translation_group_id': null,
      'scanned_edition_id': _scannedEditionId,
      'authors': <Map<String, dynamic>>[],
      'genres': <Map<String, dynamic>>[],
      'editions': <Map<String, dynamic>>[
        {
          'id': _firstEditionId,
          'isbn': '9788171300000',
          'language': 'Malayalam',
          'page_count': 55,
          'pub_date': null,
          'format': null,
          'cover_url': null,
          'back_cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
        {
          'id': _scannedEditionId,
          'isbn': '9788171300662',
          'language': 'Malayalam',
          'page_count': 255,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'back_cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
        },
      ],
    };

class _Fake extends ApiClient {
  int creates = 0;
  Map<String, dynamic> work = const {};
  String? lastEditionPatched;

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async => const [];

  @override
  Future<Map<String, dynamic>> getWork(String workId) async => work;

  @override
  Future<Map<String, dynamic>> createWork(Map<String, dynamic> payload) async {
    creates++;
    return {'id': 'new-work', 'title': payload['title'], 'editions': const []};
  }

  @override
  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async =>
      {'applied': true, 'work': work};

  @override
  Future<Map<String, dynamic>> updateEdition(String editionId, Map<String, dynamic> patch) async {
    lastEditionPatched = editionId;
    return patch;
  }
}

/// Three routes: the add form, a stand-in scanner that hands back the resolved
/// Work the way "Use these details" does, and the add/edit route the improve
/// fork replaces into — driving the real `Routes` so the `extra` contract is
/// the one production uses.
({Widget app, List<Object?> pushed}) _harness(_Fake fake, {Map<String, dynamic>? scanResult}) {
  final pushed = <Object?>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        // An ISBN carried in opens the grouped details section, which is where
        // the scan button lives; the scanner's not-found path does this too.
        builder: (context, state) => AddEditBookScreen(initialIsbn: '9788171300662'),
      ),
      GoRoute(
        path: Routes.catalogScanResult,
        builder: (context, state) => _PopsTheScan(result: scanResult),
      ),
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

class _PopsTheScan extends StatefulWidget {
  const _PopsTheScan({this.result});
  final Map<String, dynamic>? result;
  @override
  State<_PopsTheScan> createState() => _PopsTheScanState();
}

class _PopsTheScanState extends State<_PopsTheScan> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop(widget.result);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Explicit frames rather than `pumpAndSettle`: once the scan fills the form,
/// the live typeset-cover preview is running a repeating ticker animation, and
/// a tree that never goes idle makes `pumpAndSettle` time out rather than fail
/// on anything real.
Future<void> _frames(WidgetTester tester, {int count = 14}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scanIntoTheForm(WidgetTester tester) async {
  // By tooltip, not by icon: the cover block carries a scanner icon too.
  await tester.tap(find.byTooltip('Scan barcode'));
  await _frames(tester);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save to catalogue'));
  await _frames(tester);
}

void main() {
  setUp(() {});

  testWidgets('a scanned book is offered, not added a second time', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..work = _scannedWork();
    final harness = _harness(fake, scanResult: _scannedWork());
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await _scanIntoTheForm(tester);
    await _save(tester);

    expect(find.text('Already on the shelf'), findsOneWidget);
    expect(fake.creates, 0, reason: 'the book the scan resolved must not be added twice');
  });

  testWidgets('taking the offer improves the printing that was scanned', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..work = _scannedWork();
    final harness = _harness(fake, scanResult: _scannedWork());
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await _scanIntoTheForm(tester);
    await _save(tester);
    await tester.tap(find.text('Add my details to it'));
    await _frames(tester);

    expect(fake.creates, 0);
    final extra = harness.pushed.single as Map<String, dynamic>;
    expect(extra['workId'], _workId);
    // Not `editions.first` — that is the 55-page printing, and the reader is
    // holding the 255-page one (CLAUDE.md, 13 Aug 2026).
    expect(extra['editionId'], _scannedEditionId);
  });

  testWidgets('the reader can insist it is a different book, and is asked once', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..work = _scannedWork();
    final harness = _harness(fake, scanResult: _scannedWork());
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await _scanIntoTheForm(tester);
    await _save(tester);
    await tester.tap(find.text("No, mine's a different book"));
    await _frames(tester);

    // Believed: the create goes through, and the question is not asked again.
    expect(fake.creates, 1);
    expect(harness.pushed, isEmpty);
  });

  testWidgets('an unmatched scan still just fills the ISBN and saves', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The not-found path returns a bare ISBN, no title — nothing was resolved,
    // so there is nothing to offer and the add is a genuine add.
    final fake = _Fake()..work = _scannedWork();
    final harness = _harness(fake, scanResult: {'isbn': '9788171309999'});
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'A book nobody has catalogued');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await _scanIntoTheForm(tester);
    await _save(tester);

    expect(find.text('Already on the shelf'), findsNothing);
    expect(fake.creates, 1);
  });

  testWidgets('the edit form edits the printing it was given, not the first', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake()..work = _scannedWork();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => AddEditBookScreen(
          workId: _workId,
          editionId: _scannedEditionId,
          seed: const {'back_cover_url': 'https://x.test/back.jpg', 'author_names': <String>[]},
        ),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(fake.lastEditionPatched, _scannedEditionId);
  });
}
