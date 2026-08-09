// Throwaway entry point for looking at sign-in-gated screens on a device
// without a Supabase session. Today's subject: the branded Amazon buy button
// on the book page (9 Aug 2026) — rendered from a local Work fixture (the
// exact shape the API serves), so no network or session is needed.
//
//   ./scripts/run_dev.sh -d emulator-5554 -t lib/main_uidemo.dart
//
// Not part of the app: no route registers it, and `flutter build` never sees
// it unless you pass -t. Delete freely.

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

Map<String, dynamic> _work() => {
      'id': _workId,
      'title': 'Chemmeen',
      'subtitle': 'ചെമ്മീൻ',
      'description':
          'On the Kerala coast, Karuthamma loves Pareekutti across a line her community will not let her cross.',
      'language': 'Malayalam',
      'first_publish_year': 1956,
      'aggregate_rating': 4.4,
      'translation_group_id': null,
      'authors': [
        {'id': '11111111-1111-1111-1111-111111111111', 'name': 'Thakazhi Sivasankara Pillai'},
      ],
      'genres': [
        {'id': 'g1', 'name': 'Literary fiction'},
      ],
      'translations': <Map<String, dynamic>>[],
      'editions': [
        {
          'id': _editionId,
          'isbn': '9788126403455',
          'language': 'Malayalam',
          'page_count': 218,
          'pub_date': null,
          'format': 'Paperback',
          'cover_url': null,
          'series_number': null,
          'publisher': null,
          'series': null,
          'buy_links': [
            {
              'retailer': 'Amazon',
              'url': 'https://www.amazon.in/dp/8126403454?tag=kitabi0f-21',
              'affiliate': true,
            },
          ],
        },
      ],
    };

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());

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
