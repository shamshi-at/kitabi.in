import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/api/api_client.dart';
import '../../data/db/database.dart';
import '../../data/sync/sync_providers.dart';
import 'auth_service.dart';
import 'supabase_auth_service.dart';

/// Riverpod wiring for auth: picks the real [SupabaseAuthService] when
/// credentials are configured (else an [UnconfiguredAuthService] stub), exposes
/// the current [KitabiAuthUser] stream, and resets local sync/DB state when the
/// active user changes so one install never bleeds data across accounts.
const _activeUserKey = 'active_user_id';
const _offlineRetryAmnestyKey = 'offline_retry_amnesty';
const _bootstrappedUserKey = 'bootstrapped_user_id';

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
  // `.future` waits out the stream's still-resolving first emission (session
  // restore from secure storage) instead of `valueOrNull`, which reads null
  // during that split-second window — indistinguishable from "signed out" and
  // fed straight into the router's language gate below.
  final user = await ref.watch(authStateProvider.future);
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
  // One-time amnesty for ops stranded by the old retry rule, which counted
  // "the phone had no network" as a failed attempt: five offline mutations
  // used up an op's five retries and marked it errored for good. The rule is
  // fixed (see SyncEngine._drainQueue), but a reader upgrading into the fix
  // still has whatever it stranded sitting in their queue, and nothing but a
  // tap on the sync bar would ever have pushed it again.
  if (await db.keyValuesDao.getValue(_offlineRetryAmnestyKey) == null) {
    await db.syncQueueDao.resetAttempts();
    await db.keyValuesDao.setValue(_offlineRetryAmnestyKey, 'done');
  }
  try {
    await ref.watch(apiClientProvider).bootstrap();
    await db.keyValuesDao.setValue(_bootstrappedUserKey, user.id);
  } catch (err) {
    // The router holds a reader on the splash while this is in error, because
    // a signed-in reader with no profile row can only 404 their way through
    // the app (13 Aug 2026). But that gate is about whether the row *exists*
    // — and on a phone in airplane mode this call can never succeed, so the
    // gate closed the whole app, library and all, for the one reader whose
    // data is already sitting on the device. If this account has bootstrapped
    // here before, the row exists and no answer from the server is needed to
    // know it.
    if (!await _hasBootstrappedBefore(db, user.id)) rethrow;
  }
  // Pull this account's data promptly (wiping reset the cursor to 0).
  ref.read(syncTriggerProvider)();
});

/// Whether this install has already proved [userId]'s profile row exists.
///
/// Two ways to know: we recorded a successful bootstrap, or this account has
/// pulled from the server at least once (a non-zero sync cursor) — the second
/// covers readers upgrading from a build that didn't keep the first.
Future<bool> _hasBootstrappedBefore(AppDatabase db, String userId) async {
  if (await db.keyValuesDao.getValue(_bootstrappedUserKey) == userId) return true;
  return await db.syncStateDao.cursorFor(userId) > 0;
}
