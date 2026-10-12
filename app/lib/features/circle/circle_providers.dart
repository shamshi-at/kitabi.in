import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';
import '../profile/providers/profile_providers.dart';
import 'circle_models.dart';

/// What the reader shares with their circle, or null until `/me` has answered.
final circleSharingProvider = Provider<CircleSharing?>((ref) {
  final me = ref.watch(meProvider).valueOrNull;
  if (me == null || me.isEmpty) return null;
  return CircleSharing.fromMe(me);
});

/// Answers are kept for this long once fetched, so going back and forth
/// between search and a book page doesn't re-ask. Short on purpose: it is also
/// how long a connection who switches sharing off can linger on this screen
/// (seen on two emulators, 13 Oct 2026 — ten minutes was too long a goodbye).
/// A switch the reader flips themselves refreshes at once through
/// [circleSharingProvider], which everything below watches.
const _keepFor = Duration(minutes: 2);

void _keepAlive(Ref ref) {
  final link = ref.keepAlive();
  final timer = Timer(_keepFor, link.close);
  ref.onDispose(timer.cancel);
}

/// The circle is a garnish on screens that work without it: offline, a server
/// that predates `/circle`, or any other failure means "nothing to show",
/// never an error state on the page it decorates.
Future<T?> _quietly<T>(Future<T> Function() call) async {
  try {
    return await call();
  } catch (_) {
    return null;
  }
}

/// The book page's card. Null → show nothing.
final circleWorkProvider = FutureProvider.autoDispose
    .family<CircleWork?, String>((ref, workId) async {
      final sharing = ref.watch(circleSharingProvider);
      if (sharing == null) return null;
      final api = ref.watch(apiClientProvider);
      final body = await _quietly(() => api.circleWork(workId));
      if (body == null) return null;
      _keepAlive(ref);
      return CircleWork.fromJson(body);
    });

/// One line per search row, for a page of results in one request. Keyed by
/// the comma-joined work ids, so a new query is a new request and the same
/// query is free. Readers who share nothing get nothing here — Home is where
/// the invitation lives, not every search row.
final circleSignalsProvider = FutureProvider.autoDispose
    .family<Map<String, CircleSignal>, String>((ref, joinedIds) async {
      final sharing = ref.watch(circleSharingProvider);
      if (sharing == null || !sharing.any || joinedIds.isEmpty) return const {};
      final ids = joinedIds.split(',').take(50).toList();
      final api = ref.watch(apiClientProvider);
      final body = await _quietly(() => api.circleSignals(ids));
      if (body == null) return const {};
      _keepAlive(ref);
      return CircleSignal.parseAll(body);
    });

/// The key for [circleSignalsProvider] from a list of catalog works.
String circleSignalsKey(Iterable<Map<String, dynamic>> works) =>
    works.map((w) => w['id']).whereType<String>().take(50).join(',');

// ---------------------------------------------------------------- Home's card

const circlePickDismissedKey = 'circle_pick_dismissed';
const circleInviteDismissedKey = 'circle_invite_dismissed';

/// Books the reader said "not this one" to — the server skips them. Kept to
/// the most recent 100, which is more than a year of daily cards.
Future<List<String>> readDismissedPicks(Ref ref) async {
  final raw = await ref
      .read(appDatabaseProvider)
      .keyValuesDao
      .getValue(circlePickDismissedKey);
  if (raw == null) return const [];
  try {
    return [
      for (final v in jsonDecode(raw) as List)
        if (v is String) v,
    ];
  } catch (_) {
    return const [];
  }
}

final circlePickProvider = FutureProvider.autoDispose<CirclePickResponse?>((
  ref,
) async {
  final sharing = ref.watch(circleSharingProvider);
  if (sharing == null) return null;
  final dismissed = await readDismissedPicks(ref);
  final api = ref.watch(apiClientProvider);
  final body = await _quietly(() => api.circlePick(dismissed: dismissed));
  if (body == null) return null;
  _keepAlive(ref);
  return CirclePickResponse.fromJson(body);
});

/// "Not this one" on Home's card.
Future<void> dismissCirclePick(
  ProviderContainer container,
  String workId,
) async {
  final db = container.read(appDatabaseProvider);
  final raw = await db.keyValuesDao.getValue(circlePickDismissedKey);
  var ids = <String>[];
  try {
    if (raw != null) {
      ids = [
        for (final v in jsonDecode(raw) as List)
          if (v is String) v,
      ];
    }
  } catch (_) {}
  ids
    ..remove(workId)
    ..add(workId);
  if (ids.length > 100) ids = ids.sublist(ids.length - 100);
  await db.keyValuesDao.setValue(circlePickDismissedKey, jsonEncode(ids));
  container.invalidate(circlePickProvider);
}

/// The invitation (mockup 2c) shows at most once a week and is gone for good
/// after two ✕ — an invitation that keeps coming back is a nag.
class InviteDismissals {
  const InviteDismissals(this.count, this.last);

  static InviteDismissals parse(String? raw) {
    final parts = (raw ?? '').split('|');
    return InviteDismissals(
      int.tryParse(parts.first) ?? 0,
      parts.length > 1
          ? DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0)
          : null,
    );
  }

  final int count;
  final DateTime? last;

  bool allowsShowing(DateTime now) =>
      count < 2 &&
      (last == null || now.difference(last!) >= const Duration(days: 7));

  String bumped(DateTime now) => '${count + 1}|${now.millisecondsSinceEpoch}';
}

final circleInviteDismissalsProvider =
    FutureProvider.autoDispose<InviteDismissals>((ref) async {
      final raw = await ref
          .watch(appDatabaseProvider)
          .keyValuesDao
          .getValue(circleInviteDismissedKey);
      return InviteDismissals.parse(raw);
    });
