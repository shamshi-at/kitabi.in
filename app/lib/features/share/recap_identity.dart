import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';
import '../profile/providers/profile_providers.dart';

/// What the share sheet needs to know before it can print a recap link: the
/// reader's handle, and whether they have published their recaps.
class RecapIdentity {
  const RecapIdentity({this.username, this.recapsVisible = false});

  final String? username;
  final bool recapsVisible;

  /// A link can only be printed for a reader who has both.
  bool get canLink => (username?.isNotEmpty ?? false) && recapsVisible;

  /// No handle yet — the sheet offers to claim one rather than a dead URL.
  bool get needsUsername => !(username?.isNotEmpty ?? false);
}

const _usernameKey = 'recap_username';
const _visibleKey = 'recap_recaps_visible';
const _offsetKey = 'recap_utc_offset_sent';

/// The reader's handle and recap visibility, **readable offline**.
///
/// `meProvider` is a live `/me` fetch with no local fallback, so on a phone
/// with no signal it is an error and everything chained off it throws. The
/// share sheet is exactly the surface that must not care: a card composes from
/// Drift and shares through the OS, and none of that needs a network. So the
/// answer is mirrored into `key_values` on every successful fetch and read back
/// from there whenever the fetch hasn't landed — the same shape as the
/// bootstrap gate's `bootstrapped_user_id` (15 Aug 2026: when a check exists to
/// prove a fact, record the proof, so being offline later can't unprove it).
final recapIdentityProvider = FutureProvider.autoDispose<RecapIdentity>((ref) async {
  final db = ref.read(appDatabaseProvider);
  final me = ref.watch(meProvider);
  final fresh = me.valueOrNull;
  if (fresh != null && fresh.isNotEmpty) {
    final username = fresh['username'] as String?;
    final visible = fresh['recaps_visible'] == true;
    await db.keyValuesDao.setValue(_usernameKey, username ?? '');
    await db.keyValuesDao.setValue(_visibleKey, visible ? '1' : '0');
    return RecapIdentity(username: username, recapsVisible: visible);
  }
  final cachedName = await db.keyValuesDao.getValue(_usernameKey);
  final cachedVisible = await db.keyValuesDao.getValue(_visibleKey);
  return RecapIdentity(
    username: (cachedName ?? '').isEmpty ? null : cachedName,
    recapsVisible: cachedVisible == '1',
  );
});

/// Turn shared recaps on, and remember it locally so the sheet doesn't need a
/// second round trip to believe it.
///
/// Sends the device's UTC offset in the same call. The server cuts a window on
/// the reader's calendar days, not UTC's, and without the offset a sitting
/// logged late at night lands on a different day on the page than on the card
/// that linked to it — so the one moment a recap link starts existing is the
/// right moment to make sure the server knows which clock to use.
Future<void> publishRecaps(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final offset = DateTime.now().timeZoneOffset.inMinutes;
  await ref.read(apiClientProvider).updateMe({
    'recaps_visible': true,
    'utc_offset_minutes': offset,
  });
  await db.keyValuesDao.setValue(_visibleKey, '1');
  await db.keyValuesDao.setValue(_offsetKey, '$offset');
  ref.invalidate(meProvider);
}

/// Keep the server's idea of the reader's clock current, at most one call per
/// change. A reader who moves timezone would otherwise keep cutting windows on
/// the clock they had when they first published a recap.
Future<void> syncUtcOffsetIfChanged(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  final offset = '${DateTime.now().timeZoneOffset.inMinutes}';
  if (await db.keyValuesDao.getValue(_offsetKey) == offset) return;
  try {
    await ref.read(apiClientProvider).updateMe({'utc_offset_minutes': int.parse(offset)});
    await db.keyValuesDao.setValue(_offsetKey, offset);
  } catch (_) {
    // Best effort, and genuinely optional: an offset that hasn't reached the
    // server yet costs an hour at a window edge, never a broken share.
  }
}
