import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'sync_daos.g.dart';

/// DAOs backing the sync engine: the outbound [SyncQueue] of pending ops, the
/// [SyncState] pull cursor, and the [ConflictHistoryEntries] audit trail.
@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase> with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<void> enqueue(SyncQueueCompanion row) => into(syncQueue).insert(row);

  /// Pending ops to push. When [userId] is given, only that user's ops (plus
  /// legacy rows queued before the column existed) — never another account's.
  Future<List<SyncQueueData>> pending({required int limit, String? userId}) {
    final query = select(syncQueue)
      ..orderBy([(t) => OrderingTerm.asc(t.queuedAt)])
      ..limit(limit);
    if (userId != null) {
      query.where((t) => t.userId.equals(userId) | t.userId.equals(''));
    }
    return query.get();
  }

  Future<void> incrementAttempt(String opId) => customUpdate(
        'UPDATE sync_queue SET attempts = attempts + 1 WHERE op_id = ?',
        variables: [Variable.withString(opId)],
        updates: {syncQueue},
      );

  Future<void> remove(String opId) =>
      (delete(syncQueue)..where((t) => t.opId.equals(opId))).go();

  Future<void> resetAttempts() => customUpdate('UPDATE sync_queue SET attempts = 0');

  Stream<int> watchPendingCount() =>
      (selectOnly(syncQueue)..addColumns([syncQueue.opId.count()]))
          .map((row) => row.read(syncQueue.opId.count()) ?? 0)
          .watchSingle();

  /// Ops that have exhausted their retries (attempts >= 5) — surfaced in the UI
  /// as "some changes haven't synced" (CLAUDE.md: max 5 attempts, then error).
  Stream<int> watchErroredCount() {
    final count = syncQueue.opId.count();
    final query = selectOnly(syncQueue)
      ..addColumns([count])
      ..where(syncQueue.attempts.isBiggerOrEqualValue(5));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }
}

@DriftAccessor(tables: [SyncState])
class SyncStateDao extends DatabaseAccessor<AppDatabase> with _$SyncStateDaoMixin {
  SyncStateDao(super.db);

  Future<int> cursorFor(String userId) async {
    final row = await (select(
      syncState,
    )..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
    return row?.cursor ?? 0;
  }

  Future<void> saveCursor(String userId, int cursor) => into(syncState).insertOnConflictUpdate(
        SyncStateCompanion(
          userId: Value(userId),
          cursor: Value(cursor),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
}

@DriftAccessor(tables: [ConflictHistoryEntries])
class ConflictHistoryDao extends DatabaseAccessor<AppDatabase> with _$ConflictHistoryDaoMixin {
  ConflictHistoryDao(super.db);

  Stream<List<ConflictHistoryEntry>> watchAll() => (select(
        conflictHistoryEntries,
      )..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  Future<void> upsertAll(List<ConflictHistoryEntriesCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(conflictHistoryEntries, rows));
  }
}

@DriftAccessor(tables: [KeyValues])
class KeyValuesDao extends DatabaseAccessor<AppDatabase> with _$KeyValuesDaoMixin {
  KeyValuesDao(super.db);

  Future<String?> getValue(String key) async {
    final row = await (select(
      keyValues,
    )..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setValue(String key, String value) => into(keyValues).insertOnConflictUpdate(
        KeyValuesCompanion(key: Value(key), value: Value(value)),
      );
}
