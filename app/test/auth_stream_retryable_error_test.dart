import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kitabi/core/auth/auth_providers.dart';
import 'package:kitabi/core/auth/auth_service.dart';
import 'package:kitabi/core/auth/supabase_auth_service.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';

/// GoTrue's own session-refresh (recovering an expired cached session at cold
/// start, or its periodic background auto-refresh) reports a network failure
/// by pushing it as an *error* on `onAuthStateChange` — never as a data
/// event; a real sign-out always arrives as a `signedOut` data event instead.
///
/// The router's `valueOrNull` check tolerates this fine for an already
/// signed-in reader. But every provider chained off
/// `await ref.watch(authStateProvider.future)` — sessionContextProvider,
/// bootstrapProvider, meProvider, and everything downstream, which is most of
/// Home — reads the *current* AsyncValue directly, and `.future` throws
/// whenever that AsyncValue is sitting in error, previous value or not. A
/// reader already happily on Home whose phone lost signal right as a
/// background token refresh ticked saw the library list on Home die into a
/// "connection error" card (owner report, 20 Aug 2026) — nothing about their
/// library actually needed the network; Drift had it the whole time.
///
/// [SupabaseAuthService.authStateChanges] now swallows exactly this class of
/// error (`isRetryableAuthError`) before it ever reaches `authStateProvider`.
/// These pin both halves: the classifier, and that a provider chain awaiting
/// `authStateProvider.future` survives a retryable error instead of throwing.
///
/// This is also the *cold-start* case, not just "already on Home": reading
/// `supabase_flutter`'s own `SupabaseAuth.initialize()` (awaited by
/// `Supabase.initialize()`) shows it always calls `setInitialSession` on the
/// persisted session first — synchronously restoring it from local storage,
/// no expiry check, no network — and only *after* that completes does it
/// (separately, un-awaited) kick off `recoverSession()`, which is what
/// actually checks expiry and attempts the network refresh. So a device that
/// has ever signed in gets its stale-but-real cached user as
/// `authStateProvider`'s first value unconditionally — offline or not — and
/// the network-dependent refresh's possible failure always lands *after*
/// that, as the second event. The "data first, retryable error second"
/// ordering below isn't an arbitrary test shape: it is the literal sequence a
/// real cold start produces, which is why closing the error-swallowing gap
/// closes the cold-start gap too, with no separate local-fallback code
/// needed.
void main() {
  group('isRetryableAuthError', () {
    test('is true for a retryable GoTrue fetch failure', () {
      expect(isRetryableAuthError(AuthRetryableFetchException(message: 'offline')), isTrue);
    });

    test('is true for a raw socket failure', () {
      expect(isRetryableAuthError(const SocketException('offline')), isTrue);
    });

    test('is false for a real auth rejection', () {
      expect(isRetryableAuthError(AuthApiException('invalid_grant', statusCode: '400')), isFalse);
    });
  });

  test(
    'mid-session: a retryable error on the auth stream (a background '
    'auto-refresh tick failing offline) does not break a downstream '
    '.future awaiter (sessionContextProvider) once it is filtered the way '
    'authStateChanges filters it',
    () async {
      final controller = StreamController<KitabiAuthUser?>();
      addTearDown(controller.close);
      final (container, db) = _containerFor(controller);
      addTearDown(container.dispose);
      addTearDown(db.close);

      controller.add(KitabiAuthUser(id: 'u1', email: 'r@example.com'));
      final firstCtx = await container.read(sessionContextProvider.future);
      expect(firstCtx.userId, 'u1');

      // The background auto-refresh tick fails offline.
      controller.addError(AuthRetryableFetchException(message: 'offline'));
      await Future<void>.delayed(Duration.zero);

      // A fresh read (the way an autoDispose provider like
      // libraryEntriesProvider re-subscribes on a tab switch) must still
      // resolve — not throw the raw offline error.
      container.invalidate(sessionContextProvider);
      final ctx = await container.read(sessionContextProvider.future);
      expect(ctx.userId, 'u1');
    },
  );

  test(
    'cold start: the persisted (possibly expired) session restores locally '
    'first — same as setInitialSession, no network — and the network-only '
    'recoverSession refresh that follows and fails offline must not undo it',
    () async {
      final controller = StreamController<KitabiAuthUser?>();
      addTearDown(controller.close);
      final (container, db) = _containerFor(controller);
      addTearDown(container.dispose);
      addTearDown(db.close);

      // setInitialSession: local-storage restore, unconditional, no network,
      // no expiry check — this always lands first and always succeeds if a
      // session was ever persisted, whether or not its token has expired.
      controller.add(KitabiAuthUser(id: 'u1', email: 'r@example.com'));

      // recoverSession: kicked off separately right after, checks expiry and
      // — because the token is stale and the phone is offline — fails.
      controller.addError(AuthRetryableFetchException(message: 'offline'));
      await Future<void>.delayed(Duration.zero);

      // Everything a cold start needs (bootstrap gate, library repo,
      // Home's book list) reads sessionContextProvider fresh right about
      // here. It must resolve using the locally-restored user, not throw.
      final ctx = await container.read(sessionContextProvider.future);
      expect(ctx.userId, 'u1');
    },
  );
}

/// A container wired the same way for both tests above: an in-memory DB and
/// `authStateProvider` fed from [controller] through the exact filter
/// `authStateChanges` applies to the real stream. Caller owns tearing down
/// both the container and the returned DB.
(ProviderContainer, AppDatabase) _containerFor(StreamController<KitabiAuthUser?> controller) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    authStateProvider.overrideWith(
      (ref) => controller.stream.handleError(
        (Object _, StackTrace _) {},
        test: isRetryableAuthError,
      ),
    ),
    syncTriggerProvider.overrideWithValue(() {}),
  ]);
  return (container, db);
}
