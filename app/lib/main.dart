import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/auth/supabase_auth_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/sync/background_sync.dart';
import 'data/sync/connectivity_sync.dart';
import 'features/settings/theme_mode_provider.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Boots fine without credentials (see supabaseConfigured) so the app is
  // never dead-in-the-water before a real Supabase project exists.
  if (supabaseConfigured) {
    await initSupabase();
  }
  // workmanager is mobile-only (iOS 14+/Android) — no-op elsewhere.
  if (!kIsWeb) {
    await Workmanager().initialize(syncCallbackDispatcher);
    registerBackgroundSync();
  }
  runApp(ProviderScope(child: KitabiApp()));
}

class KitabiApp extends ConsumerWidget {
  const KitabiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(connectivitySyncProvider); // activates the listener once
    final router = ref.watch(routerProvider);
    final dark = ref.watch(themeModeControllerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: buildAppTheme(dark: dark),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
