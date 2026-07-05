import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';

const _optInKey = 'recs_opt_in';

/// Whether the reader has opted into recommendations. Off by default (the
/// feature is a quiet, opt-in delight — feature-map.md). Device-local for now.
final recsOptInProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return (await db.keyValuesDao.getValue(_optInKey)) == 'true';
});

Future<void> setRecsOptIn(WidgetRef ref, {required bool enabled}) async {
  await ref.read(appDatabaseProvider).keyValuesDao.setValue(_optInKey, '$enabled');
  ref.invalidate(recsOptInProvider);
}

/// The reasoned picks from the server — `{enabled, picks}`.
final recommendationsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(apiClientProvider).getRecommendations();
});
