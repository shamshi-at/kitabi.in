import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';

/// S4h's recent searches: device-local history behind the search page's idle
/// state. The rules that matter are the ones a reader would notice — a repeat
/// search moves to the top instead of appearing twice, the list stays short,
/// and it does NOT survive an account switch (a search history is as personal
/// as the library it searched).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  // A closure, not a tear-off — `container.dispose` would be evaluated at
  // registration time, before setUp has assigned it.
  tearDown(() => container.dispose());

  RecentSearches notifier() => container.read(recentSearchesProvider.notifier);

  test('records newest first', () async {
    await notifier().record('malayalam classics');
    await notifier().record('K.R. Meera');

    expect(container.read(recentSearchesProvider), [
      'K.R. Meera',
      'malayalam classics',
    ]);
  });

  test('a repeated search moves to the top rather than duplicating', () async {
    await notifier().record('Basheer');
    await notifier().record('Vijayan');
    await notifier().record('basheer'); // different case, same search

    expect(container.read(recentSearchesProvider), ['basheer', 'Vijayan']);
  });

  test('blank queries are never recorded', () async {
    await notifier().record('   ');
    await notifier().record('');

    expect(container.read(recentSearchesProvider), isEmpty);
  });

  test('keeps at most 8, dropping the oldest', () async {
    for (var i = 1; i <= 10; i++) {
      await notifier().record('query $i');
    }

    final state = container.read(recentSearchesProvider);
    expect(state, hasLength(8));
    expect(state.first, 'query 10');
    expect(state.last, 'query 3');
    expect(state, isNot(contains('query 1')));
  });

  test('queries with spaces survive the round-trip through key_values', () async {
    await notifier().record('one hundred years of solitude');
    await notifier().record('K.R. Meera');

    // A fresh container reads the persisted value back, the way a relaunch does.
    final reopened = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(reopened.dispose);
    reopened.read(recentSearchesProvider);
    await Future<void>.delayed(Duration.zero);

    expect(reopened.read(recentSearchesProvider), [
      'K.R. Meera',
      'one hundred years of solitude',
    ]);
  });

  test('clear empties the list and the stored value', () async {
    await notifier().record('something private');
    await notifier().clear();

    expect(container.read(recentSearchesProvider), isEmpty);
    expect(await db.keyValuesDao.getValue('recent_searches'), '');
  });

  test('an account switch wipes the history', () async {
    await notifier().record('something private');
    expect(await db.keyValuesDao.getValue('recent_searches'), isNotEmpty);

    await db.clearUserData();

    expect(await db.keyValuesDao.getValue('recent_searches'), isNull);
  });

  test('an account switch keeps device settings that are not personal', () async {
    await db.keyValuesDao.setValue('device_id', 'device-1');
    await notifier().record('something private');

    await db.clearUserData();

    expect(await db.keyValuesDao.getValue('device_id'), 'device-1');
  });
}
