// Throwaway entry point for looking at sign-in-gated screens on a device
// without a Supabase session. Today's subject: the catalogue doors bar
// (9 Aug 2026) — rendered against the REAL production API signed out, which
// the public catalog reads accept, so the bar fills with the real genres.
//
//   flutter run -t lib/main_uidemo.dart -d emulator-5554 \
//     --dart-define=API_BASE_URL=https://api.kitabi.in
//
// Not part of the app: no route registers it, and `flutter build` never sees
// it unless you pass -t. Delete freely.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/api/api_client.dart';
import 'data/db/database.dart';
import 'data/repositories/repositories.dart';
import 'data/sync/sync_providers.dart';
import 'features/catalog/presentation/browse_screen.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.forTesting(NativeDatabase.memory());

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionContextProvider.overrideWith(
          (ref) async => const SessionContext(userId: 'u1', deviceId: 'd1'),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
        // No Supabase in this harness — requests go out unauthenticated.
        apiClientProvider.overrideWithValue(
          ApiClient(
            readToken: () => null,
            refreshSession: () async => null,
            onAuthLost: () async {},
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark: false),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BrowseScreen(),
      ),
    ),
  );
}
