// Throwaway entry point for looking at sign-in-gated screens on a device
// without a Supabase session or a running API. Seeds an in-memory database and
// renders Home directly, with the real widgets, real theme and real Drift
// streams — so paint-time failures and layout problems show up exactly as they
// would in the shipping app.
//
//   flutter run -t lib/main_uidemo.dart -d emulator-5554
//
// Not part of the app: no route registers it, and `flutter build` never sees
// it unless you pass -t. Delete freely.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/db/database.dart';
import 'data/repositories/repositories.dart';
import 'data/sync/sync_providers.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/library/providers/library_providers.dart';
import 'features/profile/providers/profile_providers.dart';
import 'features/recommendations/providers/recommendations_providers.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());

  await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
    editionId: 'e1',
    workId: 'w1',
    title: 'കീഴാളൻ',
    authorNames: 'പെരുമാൾ മുരുകൻ',
    pageCount: const Value(352),
  ));
  await db.cachedBooksDao.upsert(CachedBooksCompanion.insert(
    editionId: 'e2',
    workId: 'w2',
    title: 'Chemmeen',
    authorNames: 'Thakazhi Sivasankara Pillai',
  ));
  await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
    id: '1',
    userId: 'u1',
    editionId: 'e1',
    status: const Value('reading'),
    currentPage: const Value(86),
  ));
  await db.libraryEntriesDao.insertOne(LibraryEntriesCompanion.insert(
    id: '2',
    userId: 'u1',
    editionId: 'e2',
    status: const Value('read'),
  ));

  // One of each surface — the loudest Home can ever be.
  await db.promotionsDao.replaceAll([
    CachedPromotionsCompanion.insert(
      id: 'promo-banner',
      kind: 'banner',
      placement: 'home_top',
      headline: 'Trivandrum Book Fair — 5 to 9 August',
      ctaLabel: const Value("See what's on"),
      priority: const Value(7),
    ),
    CachedPromotionsCompanion.insert(
      id: 'promo-card',
      kind: 'card',
      cardStyle: const Value('text'),
      placement: 'home_stream',
      sponsor: const Value('DC Books'),
      language: const Value('Malayalam'),
      headline: 'ഓണം വായനക്കാലം',
      body: const Value('മലയാളം പുസ്തകങ്ങൾക്ക് 30% വരെ കിഴിവ് — ഓഗസ്റ്റ് 9 വരെ.'),
      ctaLabel: const Value('കാണുക'),
    ),
  ]);

  final entries = await db.libraryEntriesDao.watchActive().first;

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        libraryEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        allLendingProvider.overrideWith((ref) => Stream.value(const <LendingWithBook>[])),
        recsOptInProvider.overrideWith((ref) async => false),
        meProvider.overrideWith((ref) async => {'full_name': 'Shamshi K'}),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark: false),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    ),
  );
}
