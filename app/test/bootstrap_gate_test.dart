import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/auth/auth_providers.dart';
import 'package:kitabi/core/auth/auth_service.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';

class _FakeApi extends ApiClient {
  @override
  Future<void> bootstrap() async {}
}

class _UnreachableApi extends ApiClient {
  @override
  Future<void> bootstrap() async => throw Exception('no network');
}

/// The gate that decides whether a signed-in reader may leave the splash.
///
/// A failed bootstrap used to be treated as "resolved, carry on": the reader
/// landed on the language picker with no profile row, its first save was a
/// PATCH /me that could only 404, and nothing ever called bootstrap again —
/// a one-way door into an error, restart or not (owner report, 13 Aug 2026).
///
/// These pin the rule the router now follows, in isolation from the real
/// router's auth/onboarding gates: **never walk past a bootstrap that has never
/// succeeded — but never yank an established session back either.**
bool holdsOnSplash(AsyncValue<void> bootstrap) =>
    bootstrap.isLoading || (bootstrap.hasError && !bootstrap.hasValue);

void main() {
  group('the splash gate', () {
    test('holds while the bootstrap is still resolving', () {
      expect(holdsOnSplash(const AsyncLoading<void>()), isTrue);
    });

    test('holds when the bootstrap failed and never succeeded', () {
      expect(
        holdsOnSplash(AsyncError<void>(Exception('network'), StackTrace.empty)),
        isTrue,
        reason: 'walking past this is what produced an inescapable 404',
      );
    });

    test('lets a successful bootstrap through', () {
      expect(holdsOnSplash(const AsyncData<void>(null)), isFalse);
    });

    test('does NOT yank an established session back to the splash', () {
      // A background re-run that errors *after* a good bootstrap — a token
      // refresh in a tunnel. The reader keeps using the app.
      final refreshFailed = AsyncError<void>(Exception('tunnel'), StackTrace.empty)
          .copyWithPrevious(const AsyncData<void>(null));
      expect(holdsOnSplash(refreshFailed), isFalse);
    });
  });

  /// …and the other half of the same door: the gate holds on an *unproven*
  /// account, so the bootstrap must stop failing once the account is proven.
  ///
  /// A phone in airplane mode can never complete this call. With the gate
  /// closed on it, a reader who opened Kitabi on a flight was held on the
  /// splash screen — locked out of a library that was sitting on the device
  /// the whole time, and the one place where offline-first is the entire
  /// promise. Nothing about the network says the profile row is missing.
  group('the bootstrap itself, offline', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer containerFor(ApiClient api) {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith(
          (ref) => Stream.value(KitabiAuthUser(id: 'u1', email: 'r@example.com')),
        ),
        syncTriggerProvider.overrideWithValue(() {}),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('an account that has bootstrapped here before is let through', () async {
      await db.keyValuesDao.setValue('bootstrapped_user_id', 'u1');

      await expectLater(
        containerFor(_UnreachableApi()).read(bootstrapProvider.future),
        completes,
      );
    });

    test('an account that has pulled here before is let through', () async {
      // Upgraders from a build that kept no such record — but a sync cursor
      // is proof enough that this account exists server-side.
      await db.syncStateDao.saveCursor('u1', 91);

      await expectLater(
        containerFor(_UnreachableApi()).read(bootstrapProvider.future),
        completes,
      );
    });

    test('an account never seen here still holds the door', () async {
      await expectLater(
        containerFor(_UnreachableApi()).read(bootstrapProvider.future),
        throwsA(anything),
        reason: 'a profile row we have never seen may genuinely not exist',
      );
    });

    test('a successful bootstrap records itself for next time', () async {
      await containerFor(_FakeApi()).read(bootstrapProvider.future);

      expect(await db.keyValuesDao.getValue('bootstrapped_user_id'), 'u1');
    });
  });

  testWidgets('a widget can render a retry affordance from the failed state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) => throw Exception('no network')),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final bootstrap = ref.watch(bootstrapProvider);
              return Scaffold(
                body: holdsOnSplash(bootstrap) && bootstrap.hasError
                    ? OutlinedButton(onPressed: () {}, child: const Text('Retry'))
                    : const Text('Home'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}
