import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db/catalog_cache.dart';
import '../db/database.dart';
import 'device_id.dart';
import 'library_dedupe.dart';

/// Outcome of one sync run — ops pushed and deltas pulled — surfaced to the UI.
class SyncReport {
  SyncReport({required this.pushedOps, required this.pulledChanges});
  final int pushedOps;
  final int pulledChanges;
}

/// Ported from rupee-diary's SyncEngine (CLAUDE.md: "reuse, don't
/// reinvent") — same push-then-pull loop, same idempotency-via-op-id, same
/// retry/backoff shape. The only structural difference is scoping by
/// `userId` alone (no `budgetId`/role checks — Kitabi has no sharing in V1).
class SyncEngine {
  SyncEngine(
    this.db,
    this.api, {
    this.maxAttempts = 5,
    this.pushBatchSize = 100,
    this.pullPageSize = 500,
  });

  final AppDatabase db;
  final ApiClient api;
  final int maxAttempts;
  final int pushBatchSize;
  final int pullPageSize;

  Future<SyncReport>? _inFlight;
  bool _runAgain = false;

  /// Never throws — a network failure just means "try again next time."
  ///
  /// Coalesces concurrent triggers: a call while a pass is already running
  /// doesn't start a second pass, but marks a follow-up so ops enqueued
  /// mid-sync (the old `??=` guard silently dropped these) are pushed as soon
  /// as the current pass finishes rather than waiting for the next trigger.
  Future<SyncReport> syncNow(String userId) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _runAgain = true;
      return inFlight;
    }
    return _inFlight = _syncLoop(userId).whenComplete(() => _inFlight = null);
  }

  Future<SyncReport> _syncLoop(String userId) async {
    var report = await _syncNow(userId);
    while (_runAgain) {
      _runAgain = false;
      final again = await _syncNow(userId);
      report = SyncReport(
        pushedOps: report.pushedOps + again.pushedOps,
        pulledChanges: report.pulledChanges + again.pulledChanges,
      );
    }
    return report;
  }

  Future<SyncReport> _syncNow(String userId) async {
    final pushed = await _drainQueue(userId);
    var pulled = 0;
    try {
      pulled = await _pull(userId);
    } catch (_) {
      // Network/parse failure on pull — next sync resumes from the same
      // saved cursor, so nothing is lost.
    }
    // A book lent to me arrives as a borrowed mirror record carrying only an
    // edition id (I never added it), so its catalog data isn't cached — fetch it
    // now, right after the pull, so the Borrowed shelf renders it without waiting
    // for a specific screen to trigger the hydration. No-op when nothing's new.
    try {
      await cacheBorrowedBooks(db, api);
    } catch (_) {
      // Offline / catalog fetch failed — the next sync (or the grid) retries.
    }
    // Same gap for OWNED books, and it was only healed by *visiting the library
    // tab* — so Home rendered "…" for every title on a fresh install until you
    // happened to go there (owner report, 23 Jul 2026). Hydration belongs to the
    // pull, not to one screen: every surface reads the same cache.
    try {
      await cacheMissingLibraryBooks(db, api);
    } catch (_) {
      // Offline / catalog fetch failed — the next sync (or the grid) retries.
    }
    // A pull can leave two active entries for one edition (an entry created on
    // another device/install upserts by id, next to the local one). Merge them
    // back into one; the merge enqueues ops, so mark a follow-up pass to push
    // them right away instead of waiting for the next trigger.
    try {
      final deviceId = await getOrCreateDeviceId(db);
      final healed = await healDuplicateLibraryEntries(db, userId: userId, deviceId: deviceId);
      if (healed > 0) _runAgain = true;
    } catch (_) {
      // Best-effort — the next pass retries; reads no longer crash on
      // duplicates either way (getByEditionId picks the original).
    }
    return SyncReport(pushedOps: pushed, pulledChanges: pulled);
  }

  Future<int> _drainQueue(String userId) async {
    var processed = 0;
    while (true) {
      // Scoped to the signed-in user: an account switch racing this drain must
      // never push the previous reader's ops under this reader's JWT.
      final all = await db.syncQueueDao.pending(limit: pushBatchSize, userId: userId);
      final ops = all.where((o) => o.attempts < maxAttempts).toList();
      if (ops.isEmpty) return processed;

      final payloads = [
        for (final o in ops)
          {
            'op_id': o.opId,
            'device_id': o.deviceId,
            'entity': o.entity,
            'entity_id': o.entityId,
            'op_type': o.opType,
            'payload': jsonDecode(o.payload) as Map<String, dynamic>,
          },
      ];

      List<Map<String, dynamic>> results;
      try {
        results = await api.syncPush(payloads);
      } catch (_) {
        for (final o in ops) {
          await db.syncQueueDao.incrementAttempt(o.opId);
          if (o.attempts + 1 >= maxAttempts) {
            await _setStatus(o.entity, o.entityId, 'error');
          }
        }
        return processed; // stop draining on network error; retry next sync
      }

      final byId = {for (final r in results) r['op_id'] as String: r};
      for (final o in ops) {
        final result = byId[o.opId];
        if (result == null) {
          // The server didn't answer this op (partial/malformed response).
          // Count it as a failed attempt — leaving it untouched would make
          // this while-loop re-fetch and re-push it forever in one drain.
          await db.syncQueueDao.incrementAttempt(o.opId);
          if (o.attempts + 1 >= maxAttempts) {
            await _setStatus(o.entity, o.entityId, 'error');
          }
          continue;
        }
        final status = result['status'] as String;
        if (status == 'applied' || status == 'duplicate') {
          await _setStatus(o.entity, o.entityId, 'synced', serverSeq: result['server_seq'] as int?);
          await db.syncQueueDao.remove(o.opId);
        } else {
          // rejected
          await db.syncQueueDao.remove(o.opId);
          if (result['code'] == 'deleted_wins') {
            // The server says this row was deleted (delete-wins). Apply that
            // locally now: the pull that carried the delete was skipped while
            // this op was pending (and the cursor moved past it), and a
            // rejected op bumps no server_seq — so no future pull will ever
            // bring the delete back. Without this the row stays alive on this
            // device forever.
            await _applyRemoteDelete(o.entity, o.entityId);
          } else {
            await _setStatus(o.entity, o.entityId, 'error');
          }
        }
        processed++;
      }
    }
  }

  Future<int> _pull(String userId) async {
    var cursor = await db.syncStateDao.cursorFor(userId);
    var applied = 0;
    while (true) {
      final page = await api.syncPull(cursor: cursor, limit: pullPageSize);
      final changes = (page['changes'] as List).cast<Map<String, dynamic>>();

      final pendingIds = {
        for (final o in await db.syncQueueDao.pending(limit: 10000, userId: userId)) o.entityId,
      };

      cursor = page['next_cursor'] as int;
      await db.transaction(() async {
        for (final change in changes) {
          final data = change['data'] as Map<String, dynamic>;
          if (pendingIds.contains(data['id'])) continue; // pushes first, pulls the answer later
          await _applyChange(change['entity'] as String, data);
          applied++;
        }
        await db.syncStateDao.saveCursor(userId, cursor);
      });

      if (page['has_more'] != true) return applied;
    }
  }

  /// Soft-delete a row the server rejected our op for with `deleted_wins` —
  /// the server-side deletion is the truth and no pull will re-deliver it.
  Future<void> _applyRemoteDelete(String entity, String entityId) async {
    final companion = (
      deletedAt: Value(DateTime.now()),
      syncStatus: Value('synced'),
      lastSyncedAt: Value(DateTime.now()),
    );
    switch (entity) {
      case 'library_entries':
        await db.libraryEntriesDao.patch(
          entityId,
          LibraryEntriesCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'ratings':
        await db.ratingsDao.patch(
          entityId,
          RatingsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'reviews':
        await db.reviewsDao.patch(
          entityId,
          ReviewsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'personal_tags':
        await (db.update(db.personalTags)..where((t) => t.id.equals(entityId))).write(
          PersonalTagsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'library_entry_tags':
        await db.tagsDao.patchAssignment(
          entityId,
          LibraryEntryTagsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'lending_records':
        await db.lendingRecordsDao.patch(
          entityId,
          LendingRecordsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'reading_sessions':
        await db.readingSessionsDao.patch(
          entityId,
          ReadingSessionsCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
      case 'reading_notes':
        await db.readingNotesDao.patch(
          entityId,
          ReadingNotesCompanion(
            deletedAt: companion.deletedAt,
            syncStatus: companion.syncStatus,
            lastSyncedAt: companion.lastSyncedAt,
          ),
        );
    }
  }

  Future<void> _setStatus(String entity, String entityId, String status, {int? serverSeq}) async {
    final common = (syncStatus: Value(status), lastSyncedAt: Value(DateTime.now()));
    switch (entity) {
      case 'library_entries':
        await db.libraryEntriesDao.patch(
          entityId,
          LibraryEntriesCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'ratings':
        await db.ratingsDao.patch(
          entityId,
          RatingsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'reviews':
        await db.reviewsDao.patch(
          entityId,
          ReviewsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'personal_tags':
        await (db.update(db.personalTags)..where((t) => t.id.equals(entityId))).write(
          PersonalTagsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'library_entry_tags':
        await db.tagsDao.patchAssignment(
          entityId,
          LibraryEntryTagsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'lending_records':
        await db.lendingRecordsDao.patch(
          entityId,
          LendingRecordsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'reading_sessions':
        await db.readingSessionsDao.patch(
          entityId,
          ReadingSessionsCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
      case 'reading_notes':
        await db.readingNotesDao.patch(
          entityId,
          ReadingNotesCompanion(
            syncStatus: common.syncStatus,
            lastSyncedAt: common.lastSyncedAt,
            serverSeq: serverSeq != null ? Value(serverSeq) : Value.absent(),
          ),
        );
    }
  }

  Future<void> _applyChange(String entity, Map<String, dynamic> d) async {
    DateTime? ts(String key) => d[key] == null ? null : DateTime.parse(d[key] as String);
    final synced = (
      syncStatus: Value('synced'),
      lastSyncedAt: Value(DateTime.now()),
      serverSeq: Value(d['server_seq'] as int?),
      deletedAt: Value(ts('deleted_at')),
    );

    switch (entity) {
      case 'library_entries':
        await db.into(db.libraryEntries).insertOnConflictUpdate(
              LibraryEntriesCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                editionId: Value(d['edition_id'] as String),
                status: Value(d['status'] as String),
                ownership: Value(d['ownership'] as String? ?? 'owned'),
                startDate: Value(ts('start_date')),
                finishDate: Value(ts('finish_date')),
                currentPage: Value(d['current_page'] as int?),
                isFavorite: Value(d['is_favorite'] as bool),
                notes: Value(d['notes'] as String?),
              ),
            );
      case 'ratings':
        await db.into(db.ratings).insertOnConflictUpdate(
              RatingsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                workId: Value(d['work_id'] as String),
                value: Value(d['value'] as int),
              ),
            );
      case 'reviews':
        await db.into(db.reviews).insertOnConflictUpdate(
              ReviewsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                workId: Value(d['work_id'] as String),
                body: Value(d['body'] as String),
                visible: Value(d['visible'] as bool),
              ),
            );
      case 'personal_tags':
        await db.into(db.personalTags).insertOnConflictUpdate(
              PersonalTagsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                name: Value(d['name'] as String),
              ),
            );
      case 'library_entry_tags':
        await db.into(db.libraryEntryTags).insertOnConflictUpdate(
              LibraryEntryTagsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                libraryEntryId: Value(d['library_entry_id'] as String),
                tagId: Value(d['tag_id'] as String),
              ),
            );
      case 'lending_records':
        // A borrowed *mirror* record (lent to me by a connected reader) carries a
        // null library_entry_id and its book via edition_id — so every nullable
        // field must be read as such (the old `library_entry_id as String` cast
        // threw on a mirror, failing the whole pull transaction), and direction/
        // edition_id/linked_loan_id/note must be applied or the Borrowed shelf
        // stays empty.
        await db.into(db.lendingRecords).insertOnConflictUpdate(
              LendingRecordsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                direction: Value(d['direction'] as String? ?? 'lent'),
                libraryEntryId: Value(d['library_entry_id'] as String?),
                editionId: Value(d['edition_id'] as String?),
                borrowerName: Value(d['borrower_name'] as String),
                borrowerUserId: Value(d['borrower_user_id'] as String?),
                linkedLoanId: Value(d['linked_loan_id'] as String?),
                lentDate: Value(ts('lent_date')!),
                dueDate: Value(ts('due_date')),
                returnedDate: Value(ts('returned_date')),
                note: Value(d['note'] as String?),
              ),
            );
      case 'reading_sessions':
        await db.into(db.readingSessions).insertOnConflictUpdate(
              ReadingSessionsCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                libraryEntryId: Value(d['library_entry_id'] as String),
                startedAt: Value(ts('started_at')!),
                endedAt: Value(ts('ended_at')!),
                durationSeconds: Value(d['duration_seconds'] as int),
                pageStart: Value(d['page_start'] as int?),
                pageEnd: Value(d['page_end'] as int?),
              ),
            );
      case 'reading_notes':
        await db.into(db.readingNotes).insertOnConflictUpdate(
              ReadingNotesCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                libraryEntryId: Value(d['library_entry_id'] as String),
                sessionId: Value(d['session_id'] as String?),
                body: Value(d['body'] as String),
                pageStart: Value(d['page_start'] as int?),
                pageEnd: Value(d['page_end'] as int?),
              ),
            );
      case 'activity_log_entries':
        await db.into(db.activityLogEntries).insertOnConflictUpdate(
              ActivityLogEntriesCompanion(
                id: Value(d['id'] as String),
                userId: Value(d['user_id'] as String),
                createdAt: Value(ts('created_at')!),
                updatedAt: Value(ts('updated_at')!),
                deletedAt: synced.deletedAt,
                syncStatus: synced.syncStatus,
                lastSyncedAt: synced.lastSyncedAt,
                serverSeq: synced.serverSeq,
                eventType: Value(d['event_type'] as String),
                entityType: Value(d['entity_type'] as String),
                entityId: Value(d['entity_id'] as String),
                payload: Value(jsonEncode(d['payload'])),
                occurredAt: Value(ts('occurred_at')!),
              ),
            );
    }
  }
}
