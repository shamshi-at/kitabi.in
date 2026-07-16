import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

const _uuid = Uuid();

/// Merges duplicate active library entries for the same edition back into one.
///
/// The app assumes one active entry per edition, but duplicates are reachable
/// through sync: a pull delivers an entry created on another device (or a
/// previous install) for an edition this device already has a row for —
/// upserts are by id, so both stay active. Every `getSingleOrNull` lookup on
/// that edition then used to crash ("Bad state: Too many elements"), and the
/// grid shows the book twice.
///
/// Policy: the *original* entry wins the identity (earliest `createdAt` — the
/// row the server and any child records already reference); content is folded
/// in from the duplicates so nothing the reader did on either row is lost:
/// status from the most recently updated row, reading progress maximised
/// (furthest page, earliest start, latest finish), favorite OR-ed, notes kept
/// from the keeper else the first duplicate that has any. Child rows (reading
/// sessions, lending records, tag assignments) are re-pointed at the keeper,
/// then the duplicates are soft-deleted — every mutation enqueued, so the
/// server converges to the same single entry (CLAUDE.md rules 3, 6).
///
/// Runs after every sync pull (sync_engine.dart); cheap no-op when there are
/// no duplicates. Returns how many duplicate rows were merged away.
Future<int> healDuplicateLibraryEntries(
  AppDatabase db, {
  required String userId,
  required String deviceId,
}) async {
  final entries = await db.libraryEntriesDao.activeForUser(userId);
  final byEdition = <String, List<LibraryEntry>>{};
  for (final e in entries) {
    byEdition.putIfAbsent(e.editionId, () => []).add(e);
  }

  var merged = 0;
  for (final group in byEdition.values) {
    if (group.length < 2) continue;
    await db.transaction(() async {
      await _mergeGroup(db, group, userId: userId, deviceId: deviceId);
    });
    merged += group.length - 1;
  }
  return merged;
}

Future<void> _mergeGroup(
  AppDatabase db,
  List<LibraryEntry> group, {
  required String userId,
  required String deviceId,
}) async {
  // activeForUser orders by (createdAt, id), so the original comes first.
  final keeper = group.first;
  final losers = group.sublist(1);
  // Status comes from the most recently updated row that actually says
  // anything — a freshly added default row ('pending', no progress, no
  // notes) is an artifact of how the duplicate arose (e.g. re-adding a book
  // after a reinstall, before the pull delivered the original), and must not
  // outvote the entry carrying the reader's real state.
  final informative = group.where((e) => !_isBlank(e)).toList();
  final freshest = informative.isEmpty
      ? keeper
      : informative.reduce((a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a);

  // Fold content across the group.
  final status = freshest.status;
  final ownership = group.any((e) => e.ownership == 'owned') ? 'owned' : keeper.ownership;
  int? currentPage;
  DateTime? startDate;
  DateTime? finishDate;
  var isFavorite = false;
  String? notes = _nonEmpty(keeper.notes);
  for (final e in group) {
    if (e.currentPage != null && (currentPage == null || e.currentPage! > currentPage)) {
      currentPage = e.currentPage;
    }
    if (e.startDate != null && (startDate == null || e.startDate!.isBefore(startDate))) {
      startDate = e.startDate;
    }
    if (e.finishDate != null && (finishDate == null || e.finishDate!.isAfter(finishDate))) {
      finishDate = e.finishDate;
    }
    isFavorite = isFavorite || e.isFavorite;
    notes ??= _nonEmpty(e.notes);
  }

  // Patch the keeper with anything the fold changed, and push those fields.
  final changes = <String, dynamic>{
    if (status != keeper.status) 'status': status,
    if (ownership != keeper.ownership) 'ownership': ownership,
    if (currentPage != keeper.currentPage) 'current_page': currentPage,
    if (startDate != keeper.startDate && startDate != null) 'start_date': _dateOnly(startDate),
    if (finishDate != keeper.finishDate && finishDate != null) 'finish_date': _dateOnly(finishDate),
    if (isFavorite != keeper.isFavorite) 'is_favorite': isFavorite,
    if (notes != keeper.notes && notes != null) 'notes': notes,
  };
  if (changes.isNotEmpty) {
    await db.libraryEntriesDao.patch(
      keeper.id,
      LibraryEntriesCompanion(
        status: Value(status),
        ownership: Value(ownership),
        currentPage: Value(currentPage),
        startDate: Value(startDate),
        finishDate: Value(finishDate),
        isFavorite: Value(isFavorite),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await _enqueue(db,
        userId: userId,
        deviceId: deviceId,
        entity: 'library_entries',
        entityId: keeper.id,
        opType: 'update',
        data: changes);
  }

  for (final loser in losers) {
    await _repointChildren(db, from: loser.id, to: keeper.id, userId: userId, deviceId: deviceId);
    await db.libraryEntriesDao.patch(
      loser.id,
      LibraryEntriesCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
    );
    await _enqueue(db,
        userId: userId,
        deviceId: deviceId,
        entity: 'library_entries',
        entityId: loser.id,
        opType: 'delete',
        data: const {});
  }
}

/// Re-point every child record hanging off a duplicate entry at the keeper.
Future<void> _repointChildren(
  AppDatabase db, {
  required String from,
  required String to,
  required String userId,
  required String deviceId,
}) async {
  final sessions = await (db.select(db.readingSessions)
        ..where((t) => t.libraryEntryId.equals(from) & t.deletedAt.isNull()))
      .get();
  for (final s in sessions) {
    await db.readingSessionsDao.patch(
      s.id,
      ReadingSessionsCompanion(
        libraryEntryId: Value(to),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await _enqueue(db,
        userId: userId,
        deviceId: deviceId,
        entity: 'reading_sessions',
        entityId: s.id,
        opType: 'update',
        data: {'library_entry_id': to});
  }

  final loans = await (db.select(db.lendingRecords)
        ..where((t) => t.libraryEntryId.equals(from) & t.deletedAt.isNull()))
      .get();
  for (final r in loans) {
    await db.lendingRecordsDao.patch(
      r.id,
      LendingRecordsCompanion(
        libraryEntryId: Value(to),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await _enqueue(db,
        userId: userId,
        deviceId: deviceId,
        entity: 'lending_records',
        entityId: r.id,
        opType: 'update',
        data: {'library_entry_id': to});
  }

  // Tag assignments are create/delete-only on the wire, so a move is a new
  // assignment on the keeper plus a delete of the old one (skipping tags the
  // keeper already carries).
  final keeperTagIds = {
    for (final t in await (db.select(db.libraryEntryTags)
          ..where((t) => t.libraryEntryId.equals(to) & t.deletedAt.isNull()))
        .get())
      t.tagId,
  };
  final loserTags = await (db.select(db.libraryEntryTags)
        ..where((t) => t.libraryEntryId.equals(from) & t.deletedAt.isNull()))
      .get();
  for (final lt in loserTags) {
    if (!keeperTagIds.contains(lt.tagId)) {
      final newId = _uuid.v4();
      await db.tagsDao.insertAssignment(
        LibraryEntryTagsCompanion.insert(
          id: newId,
          userId: userId,
          libraryEntryId: to,
          tagId: lt.tagId,
        ),
      );
      await _enqueue(db,
          userId: userId,
          deviceId: deviceId,
          entity: 'library_entry_tags',
          entityId: newId,
          opType: 'create',
          data: {'library_entry_id': to, 'tag_id': lt.tagId});
      keeperTagIds.add(lt.tagId);
    }
    await db.tagsDao.patchAssignment(
      lt.id,
      LibraryEntryTagsCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
    );
    await _enqueue(db,
        userId: userId,
        deviceId: deviceId,
        entity: 'library_entry_tags',
        entityId: lt.id,
        opType: 'delete',
        data: const {});
  }
}

/// A row still in its just-added default state — it carries no reader intent.
bool _isBlank(LibraryEntry e) =>
    e.status == 'pending' &&
    e.currentPage == null &&
    e.startDate == null &&
    e.finishDate == null &&
    !e.isFavorite &&
    (e.notes == null || e.notes!.trim().isEmpty);

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s;

/// The server's start/finish/lent dates are plain `date` columns — send
/// date-only strings (a full timestamp is rejected as invalid_payload).
String _dateOnly(DateTime d) => d.toUtc().toIso8601String().split('T').first;

Future<void> _enqueue(
  AppDatabase db, {
  required String userId,
  required String deviceId,
  required String entity,
  required String entityId,
  required String opType,
  required Map<String, dynamic> data,
}) {
  return db.syncQueueDao.enqueue(
    SyncQueueCompanion.insert(
      opId: _uuid.v4(),
      userId: Value(userId),
      deviceId: deviceId,
      entity: entity,
      entityId: entityId,
      opType: opType,
      payload: jsonEncode(data),
    ),
  );
}
