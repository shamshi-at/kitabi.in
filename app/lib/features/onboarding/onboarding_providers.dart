import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/sync_providers.dart';

const _seenKey = 'onboarding_seen';

/// Whether the first-run welcome has been shown. Device-local.
final onboardingSeenProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return (await db.keyValuesDao.getValue(_seenKey)) == 'true';
});

Future<void> markOnboardingSeen(WidgetRef ref) async {
  await ref.read(appDatabaseProvider).keyValuesDao.setValue(_seenKey, 'true');
  ref.invalidate(onboardingSeenProvider);
}
