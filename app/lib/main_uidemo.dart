// Throwaway entry point for looking at sign-in-gated screens on a device
// without a Supabase session. Today's subject: the reading log's per-day
// tallies and the streak-aware finish estimate (owner report, 12 Aug 2026) —
// seeded from Drift with the report's own shape: a 454-page book at p. 291
// after a three-day binge, which the old six-week average called "2 weeks".
//
//   ./scripts/run_dev.sh -d emulator-5554 -t lib/main_uidemo.dart
//
// Not part of the app: no route registers it, and `flutter build` never sees
// it unless you pass -t. Delete freely.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'data/db/database.dart';
import 'data/repositories/repositories.dart';
import 'data/sync/sync_providers.dart';
import 'features/catalog/providers/catalog_providers.dart';
import 'features/library/presentation/book_detail_screen.dart';
import 'l10n/app_localizations.dart';

const _workId = '33333333-3333-3333-3333-333333333333';
const _editionId = '44444444-4444-4444-4444-444444444444';
const _entryId = '55555555-5555-5555-5555-555555555555';

Map<String, dynamic> _work() => {
      'id': _workId,
      'title': 'Aano - ആനോ',
      'subtitle': null,
      'description': 'A Kerala novel about an elephant.',
      'language': 'Malayalam',
      'first_publish_year': 2024,
      'aggregate_rating': null,
      'translation_group_id': null,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'ജി.ആർ.ഇന്ദുഗോപൻ'},
      ],
      'genres': [
        {'id': 'g1', 'name': 'Historical fiction'},
      ],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _editionId,
          'isbn': null,
          'language': 'Malayalam',
          'page_count': 454,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
          'buy_links': <Map<String, dynamic>>[],
        },
      ],
    };

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
    editionId: _editionId,
    workId: _workId,
    title: 'Aano - ആനോ',
    authorNames: 'ജി.ആർ.ഇന്ദുഗോപൻ',
    language: const Value('Malayalam'),
    pageCount: const Value(454),
  ));
  await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
    id: _entryId,
    userId: 'u1',
    editionId: _editionId,
    status: const Value('reading'),
    currentPage: const Value(291),
    startDate: Value(now.subtract(const Duration(days: 4))),
  ));

  // The owner's log, verbatim: 12 sittings, 5h40m, 224 pages, over 4 days.
  final sittings = <(int, int, int, int, int?, int?)>[
    // (days ago, hour, minute, minutes, pageStart, pageEnd)
    (1, 22, 34, 22, 269, 291),
    (1, 18, 11, 30, 244, 269),
    (1, 15, 16, 5, 239, 244),
    (1, 13, 0, 28, 213, 239),
    (1, 2, 20, 8, 206, 213),
    (1, 1, 42, 29, 180, 206),
    (1, 1, 16, 12, 172, 180),
    (2, 23, 57, 22, 158, 172),
    (3, 23, 23, 55, 112, 158),
    (3, 12, 51, 17, 99, 112),
    (3, 11, 55, 37, 67, 99),
    (3, 1, 0, 71, null, 67),
  ];
  for (final (i, s) in sittings.indexed) {
    final day = now.subtract(Duration(days: s.$1));
    final started = DateTime(day.year, day.month, day.day, s.$2, s.$3);
    await db.readingSessionsDao.insertOne(ReadingSessionsCompanion.insert(
      id: 'session-$i',
      userId: 'u1',
      libraryEntryId: _entryId,
      startedAt: started,
      endedAt: started.add(Duration(minutes: s.$4)),
      durationSeconds: s.$4 * 60,
      pageStart: Value(s.$5),
      pageEnd: Value(s.$6),
    ));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await _seed(db);

  final router = GoRouter(
    initialLocation: '/book/$_workId/$_editionId',
    routes: [
      GoRoute(
        path: '/book/:workId/:editionId',
        builder: (context, state) => BookDetailScreen(
          workId: state.pathParameters['workId']!,
          editionId: state.pathParameters['editionId']!,
        ),
      ),
    ],
  );

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        workProvider.overrideWith((ref, id) async => _work()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark: false),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}
