import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';

const _workId = 'w-1';

class _FakeApi extends ApiClient {
  bool online = true;
  Map<String, dynamic> work = const {'id': _workId, 'title': 'Original'};

  @override
  Future<Map<String, dynamic>> getWork(String workId) async {
    if (!online) throw Exception('offline');
    return work;
  }
}

/// The book-detail screen's sole data source used to be a raw, un-cached
/// `getWork` call — every other surface showing the same book (Home, the
/// mini-bar, the library grid) reads it from Drift, so tapping into any
/// already-viewed book while offline was the one action in the app
/// guaranteed to fail with "network error" (owner report, 19 Aug 2026, mid-
/// flight in airplane mode). `bookDetailWorkProvider` now mirrors the last
/// successful payload to Drift and falls back to it when the live call
/// fails — kept separate from the plain `workProvider` (used by the add/edit
/// form) so editing an existing catalog entry never pulls Drift into its
/// dependency graph.
void main() {
  test('bookDetailWorkProvider serves the last-cached payload when offline', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi();

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    // Viewed once while online — this is what caches it.
    final first = await container.read(bookDetailWorkProvider(_workId).future);
    expect(first['title'], 'Original');

    // Airplane mode. The book was never re-added, only re-opened — the same
    // path a tap from Home takes.
    api.online = false;
    container.invalidate(bookDetailWorkProvider(_workId));
    final offline = await container.read(bookDetailWorkProvider(_workId).future);

    expect(offline['title'], 'Original', reason: 'should render from the cache, not error');
  });

  test('bookDetailWorkProvider still surfaces the error for a book never viewed online',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi()..online = false;

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(bookDetailWorkProvider(_workId).future),
      throwsA(anything),
      reason: 'nothing was ever cached for this book — there is genuinely nothing to show',
    );
  });
}
