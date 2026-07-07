import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';
import 'auth_service.dart';
import 'supabase_auth_service.dart';

const _activeUserKey = 'active_user_id';

final authServiceProvider = Provider<AuthService>((ref) {
  if (!supabaseConfigured) return UnconfiguredAuthService();
  return SupabaseAuthService(Supabase.instance.client);
});

/// Drives the router redirect (CLAUDE.md: "auth guard redirect" convention).
final authStateProvider = StreamProvider<KitabiAuthUser?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges;
});

/// Creates the profile row on first login; the router waits for this to
/// resolve before letting a signed-in user reach anywhere but the splash
/// screen, so /me is guaranteed to exist by the time Home renders.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return;
  // Account switch: if a *different* reader was last signed in on this device,
  // wipe their local library/loans/caches before this account syncs — otherwise
  // one account's data leaks into another's.
  final db = ref.read(appDatabaseProvider);
  final previous = await db.keyValuesDao.getValue(_activeUserKey);
  if (previous != null && previous != user.id) {
    await db.clearUserData();
  }
  await db.keyValuesDao.setValue(_activeUserKey, user.id);
  await ref.watch(apiClientProvider).bootstrap();
  // Pull this account's data promptly (wiping reset the cursor to 0).
  ref.read(syncTriggerProvider)();
});
