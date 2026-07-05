import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../api/api_client.dart';
import '../db/database.dart';
import '../repositories/repositories.dart';
import 'device_id.dart';
import 'sync_engine.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final deviceIdProvider = FutureProvider<String>((ref) {
  return getOrCreateDeviceId(ref.watch(appDatabaseProvider));
});

/// Resolves once both the signed-in user and this device's id are known —
/// every repository provider depends on this, so nothing can enqueue a
/// mutation before both pieces of identity exist.
final sessionContextProvider = FutureProvider<SessionContext>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    throw StateError('sessionContextProvider read while signed out');
  }
  final deviceId = await ref.watch(deviceIdProvider.future);
  return SessionContext(userId: user.id, deviceId: deviceId);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(ref.watch(appDatabaseProvider), ref.watch(apiClientProvider));
});

/// Fire-and-forget trigger used after a local mutation and on connectivity
/// regain — errors are swallowed by SyncEngine.syncNow itself.
final syncTriggerProvider = Provider<void Function()>((ref) {
  return () {
    final session = ref.read(sessionContextProvider).valueOrNull;
    if (session == null) return;
    ref.read(syncEngineProvider).syncNow(session.userId);
  };
});

/// Count of queued (not-yet-synced) local mutations — drives the sync bar.
final unsyncedCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(appDatabaseProvider).syncQueueDao.watchPendingCount();
});

/// Count of ops that have exhausted their retries — a visible "sync failed".
final syncErrorCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(appDatabaseProvider).syncQueueDao.watchErroredCount();
});
