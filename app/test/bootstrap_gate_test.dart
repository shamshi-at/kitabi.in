import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/auth/auth_providers.dart';
import 'package:kitabi/core/router/app_router.dart';
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
/// These pin the rule the router follows — `holdsOnSplash`, imported from the
/// router rather than copied here (a copy passed while the real gate flashed
/// readers to the splash, 6 Sep 2026) — in isolation from the auth/onboarding
/// gates: **never walk past a bootstrap that has never succeeded — but never
/// yank an established session back either.**
bool _bootstrapHolds(AsyncValue<void> bootstrap, {bool atGate = true}) =>
    holdsOnSplash(bootstrap, atGate: atGate, holdOnUnprovenError: true);

void main() {
  group('the splash gate', () {
    test('holds while the bootstrap is still resolving', () {
      expect(_bootstrapHolds(const AsyncLoading<void>()), isTrue);
      expect(_bootstrapHolds(const AsyncLoading<void>(), atGate: false), isTrue,
          reason: 'no value ever means a cold start, wherever the URL says we are');
    });

    test('holds when the bootstrap failed and never succeeded', () {
      expect(
        _bootstrapHolds(AsyncError<void>(Exception('network'), StackTrace.empty)),
        isTrue,
        reason: 'walking past this is what produced an inescapable 404',
      );
    });

    test('lets a successful bootstrap through', () {
      expect(_bootstrapHolds(const AsyncData<void>(null)), isFalse);
    });

    test('a background re-run holds only while the reader is still at a gate', () {
      // Every auth event — a token refresh included — re-runs the boot
      // providers, which then read as loading *with* their previous value.
      final rerun = const AsyncLoading<void>().copyWithPrevious(const AsyncData<void>(null));
      expect(_bootstrapHolds(rerun, atGate: true), isTrue,
          reason: 'the sign-in hand-off: the previous value is the signed-out run');
      expect(_bootstrapHolds(rerun, atGate: false), isFalse,
          reason: 'an established reader mid-app must not be flashed to the splash');
      // The profile gate: same shape, and never holds on an error at all.
      final meRerun = const AsyncLoading<Map<String, dynamic>>()
          .copyWithPrevious(const AsyncData<Map<String, dynamic>>({'preferred_languages': ['ml']}));
      expect(holdsOnSplash(meRerun, atGate: false), isFalse);
      expect(holdsOnSplash(meRerun, atGate: true), isTrue);
      expect(
        holdsOnSplash(AsyncError<Map<String, dynamic>>(Exception('x'), StackTrace.empty),
            atGate: true),
        isFalse,
      );
    });

    test('the gate locations are the four boot screens and nothing else', () {
      for (final loc in [Routes.splash, Routes.signIn, Routes.welcome, Routes.languages]) {
        expect(isBootGateLocation(loc), isTrue, reason: loc);
      }
      expect(isBootGateLocation(Routes.home), isFalse);
      expect(isBootGateLocation(Routes.bookDetailPath('w', 'e')), isFalse);
    });

    test('does NOT yank an established session back to the splash', () {
      // A background re-run that errors *after* a good bootstrap — a token
      // refresh in a tunnel. The reader keeps using the app.
      final refreshFailed = AsyncError<void>(Exception('tunnel'), StackTrace.empty)
          .copyWithPrevious(const AsyncData<void>(null));
      expect(_bootstrapHolds(refreshFailed), isFalse);
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
                body: _bootstrapHolds(bootstrap) && bootstrap.hasError
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
