import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../data/api/api_client.dart';

/// Own profile, fetched once the post-sign-in bootstrap call has resolved
/// (so /me is guaranteed to exist). Re-fetched via `ref.invalidate(meProvider)`
/// after an update — simplest correct thing for a V1 shell; optimistic UI can
/// come later if the round-trip ever feels slow.
final meProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  return ref.watch(apiClientProvider).getMe();
});
