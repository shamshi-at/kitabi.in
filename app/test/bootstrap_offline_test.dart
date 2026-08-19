import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/auth/auth_providers.dart';
import 'package:kitabi/core/auth/auth_service.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';

class _FakeApi extends ApiClient {
  bool shouldFail = false;
  int calls = 0;

  @override
  Future<void> bootstrap() async {
    calls++;
    if (shouldFail) throw Exception('offline');
  }
}

/// `bootstrapProvider` gates every screen but the splash (see
/// bootstrap_gate_test.dart's `holdsOnSplash`). That gate is correct for a
/// bootstrap that has *never* succeeded — walking past it was how a reader
/// reached the language picker with no profile row (owner report, 13 Aug
/// 2026). But held unconditionally, the same gate also traps an already-
/// established reader behind "connection error" on every offline cold start,
/// even though their entire library already lives in Drift and needs no
/// network to show (owner report, 19 Aug 2026, mid-flight). These pin the
/// fix: once bootstrap has actually succeeded for a user on this device, a
/// later failure must not surface as an error the router's gate would hold
/// on — but a bootstrap that has never once succeeded still must.
void main() {
  test('a bootstrap that already succeeded once tolerates a later offline failure', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi();
    final user = KitabiAuthUser(id: 'u1');

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) => Stream.value(user)),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    // First run (online): bootstrap succeeds — the profile row now genuinely
    // exists server-side.
    await container.read(bootstrapProvider.future);
    expect(api.calls, 1);

    // The flight: a cold start's bootstrap call fails.
    api.shouldFail = true;
    container.invalidate(bootstrapProvider);
    await container.read(bootstrapProvider.future);

    expect(container.read(bootstrapProvider).hasError, isFalse,
        reason: 'an established session must reach its offline library, not the splash');
  });

  test('a bootstrap that has never succeeded still surfaces the error', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi()..shouldFail = true;
    final user = KitabiAuthUser(id: 'u1');

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) => Stream.value(user)),
      syncTriggerProvider.overrideWithValue(() {}),
    ]);
    addTearDown(container.dispose);

    await expectLater(container.read(bootstrapProvider.future), throwsA(anything));
    expect(container.read(bootstrapProvider).hasError, isTrue,
        reason: 'walking past this is what produced an inescapable 404 (13 Aug 2026)');
  });
}
