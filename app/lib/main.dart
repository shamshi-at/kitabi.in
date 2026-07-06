import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'core/auth/supabase_auth_service.dart';
import 'core/deep_links.dart';
import 'core/notifications/push_service.dart';
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
  // Firebase (FCM push). Guarded: if the native config is somehow absent the app
  // still boots — push just stays inactive.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {
      // No Firebase config → run without push.
    }
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
    ref.watch(deepLinkListenerProvider); // routes kitabi.in share links into the app
    ref.watch(pushLifecycleProvider); // registers FCM token on sign-in, clears on sign-out
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
