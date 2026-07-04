import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

const _uuid = Uuid();

/// Who's making this edit — `userId` scopes ownership, `deviceId` is the
/// same-user-multiple-devices conflict signal (see sync_op.py).
class SessionContext {
  const SessionContext({required this.userId, required this.deviceId});
  final String userId;
  final String deviceId;
}

abstract class Repo {
  Repo(this.db, this.session);

  final AppDatabase db;
  final SessionContext session;

  /// Every mutation calls this — snake_case keys, matching what the API
  /// expects on `POST /sync/push`.
  Future<void> enqueue({
    required String entity,
    required String entityId,
    required String opType,
    required Map<String, dynamic> data,
  }) =>
      db.syncQueueDao.enqueue(
        SyncQueueCompanion.insert(
          opId: _uuid.v4(),
          deviceId: session.deviceId,
          entity: entity,
          entityId: entityId,
          opType: opType,
          payload: jsonEncode(data),
        ),
      );
}

class LibraryRepository extends Repo {
  LibraryRepository(super.db, super.session);

  Stream<List<LibraryEntry>> watchActive() => db.libraryEntriesDao.watchActive();

  Future<LibraryEntry?> getByEditionId(String editionId) =>
      db.libraryEntriesDao.getByEditionId(editionId);

  /// Add a book to the library (S6's implicit "own this" action).
  Future<String> add({required String editionId, String status = 'pending'}) async {
    final id = _uuid.v4();
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(
        id: id,
        userId: session.userId,
        editionId: editionId,
        status: Value(status),
      ),
    );
    await enqueue(
      entity: 'library_entries',
      entityId: id,
      opType: 'create',
      data: {'edition_id': editionId, 'status': status},
    );
    return id;
  }

  Future<void> updateStatus(String id, String status) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'library_entries',
      entityId: id,
      opType: 'update',
      data: {'status': status},
    );
  }

  Future<void> updateProgress(
    String id, {
    int? currentPage,
    DateTime? startDate,
    DateTime? finishDate,
  }) async {
    final changes = <String, dynamic>{};
    if (currentPage != null) changes['current_page'] = currentPage;
    if (startDate != null) changes['start_date'] = startDate.toUtc().toIso8601String();
    if (finishDate != null) changes['finish_date'] = finishDate.toUtc().toIso8601String();
    if (changes.isEmpty) return;

    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(
        currentPage: currentPage != null ? Value(currentPage) : const Value.absent(),
        startDate: startDate != null ? Value(startDate) : const Value.absent(),
        finishDate: finishDate != null ? Value(finishDate) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(entity: 'library_entries', entityId: id, opType: 'update', data: changes);
  }

  Future<void> setFavorite(String id, bool isFavorite) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'library_entries',
      entityId: id,
      opType: 'update',
      data: {'is_favorite': isFavorite},
    );
  }

  Future<void> updateNotes(String id, String notes) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(entity: 'library_entries', entityId: id, opType: 'update', data: {'notes': notes});
  }

  Future<void> remove(String id) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(deletedAt: Value(DateTime.now()), syncStatus: const Value('pending')),
    );
    await enqueue(entity: 'library_entries', entityId: id, opType: 'delete', data: {});
  }
}

class RatingsRepository extends Repo {
  RatingsRepository(super.db, super.session);

  Stream<Rating?> watchForWork(String workId) => db.ratingsDao.watchForWork(workId);

  /// One rating per work — updates the existing row if there is one.
  Future<void> setRating(String workId, int value) async {
    final existing = await db.ratingsDao.watchForWork(workId).first;
    if (existing != null) {
      await db.ratingsDao.patch(
        existing.id,
        RatingsCompanion(
          value: Value(value),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );
      await enqueue(
        entity: 'ratings',
        entityId: existing.id,
        opType: 'update',
        data: {'value': value},
      );
      return;
    }

    final id = _uuid.v4();
    await db.ratingsDao.insertOne(
      RatingsCompanion.insert(id: id, userId: session.userId, workId: workId, value: value),
    );
    await enqueue(
      entity: 'ratings',
      entityId: id,
      opType: 'create',
      data: {'work_id': workId, 'value': value},
    );
  }
}

class ReviewsRepository extends Repo {
  ReviewsRepository(super.db, super.session);

  Stream<Review?> watchForWork(String workId) => db.reviewsDao.watchForWork(workId);

  Future<void> upsert(String workId, {required String body, required bool visible}) async {
    final existing = await db.reviewsDao.watchForWork(workId).first;
    if (existing != null) {
      await db.reviewsDao.patch(
        existing.id,
        ReviewsCompanion(
          body: Value(body),
          visible: Value(visible),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value('pending'),
        ),
      );
      await enqueue(
        entity: 'reviews',
        entityId: existing.id,
        opType: 'update',
        data: {'body': body, 'visible': visible},
      );
      return;
    }

    final id = _uuid.v4();
    await db.reviewsDao.insertOne(
      ReviewsCompanion.insert(
        id: id,
        userId: session.userId,
        workId: workId,
        body: body,
        visible: Value(visible),
      ),
    );
    await enqueue(
      entity: 'reviews',
      entityId: id,
      opType: 'create',
      data: {'work_id': workId, 'body': body, 'visible': visible},
    );
  }
}

class TagsRepository extends Repo {
  TagsRepository(super.db, super.session);

  Stream<List<PersonalTag>> watchAll() => db.tagsDao.watchAll();

  Stream<List<LibraryEntryTag>> watchForEntry(String libraryEntryId) =>
      db.tagsDao.watchForEntry(libraryEntryId);

  Future<String> createTag(String name) async {
    final id = _uuid.v4();
    await db.tagsDao.insertTag(
      PersonalTagsCompanion.insert(id: id, userId: session.userId, name: name),
    );
    await enqueue(entity: 'personal_tags', entityId: id, opType: 'create', data: {'name': name});
    return id;
  }

  Future<void> assign(String libraryEntryId, String tagId) async {
    final id = _uuid.v4();
    await db.tagsDao.insertAssignment(
      LibraryEntryTagsCompanion.insert(
        id: id,
        userId: session.userId,
        libraryEntryId: libraryEntryId,
        tagId: tagId,
      ),
    );
    await enqueue(
      entity: 'library_entry_tags',
      entityId: id,
      opType: 'create',
      data: {'library_entry_id': libraryEntryId, 'tag_id': tagId},
    );
  }

  Future<void> unassign(String assignmentId) async {
    await db.tagsDao.patchAssignment(
      assignmentId,
      LibraryEntryTagsCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'library_entry_tags',
      entityId: assignmentId,
      opType: 'delete',
      data: {},
    );
  }
}

class LendingRepository extends Repo {
  LendingRepository(super.db, super.session);

  Stream<List<LendingRecord>> watchForEntry(String libraryEntryId) =>
      db.lendingRecordsDao.watchForEntry(libraryEntryId);

  /// The whole ledger (S8) — every active lending record joined to its book.
  Stream<List<LendingWithBook>> watchAll() => db.lendingRecordsDao.watchAllActive();

  Future<String> lendOut(
    String libraryEntryId, {
    required String borrowerName,
    required DateTime lentDate,
    DateTime? dueDate,
  }) async {
    final id = _uuid.v4();
    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: id,
        userId: session.userId,
        libraryEntryId: libraryEntryId,
        borrowerName: borrowerName,
        lentDate: lentDate,
        dueDate: Value(dueDate),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'create',
      data: {
        'library_entry_id': libraryEntryId,
        'borrower_name': borrowerName,
        'lent_date': lentDate.toUtc().toIso8601String().split('T').first,
        if (dueDate != null) 'due_date': dueDate.toUtc().toIso8601String().split('T').first,
      },
    );
    return id;
  }

  Future<void> markReturned(String id, DateTime returnedDate) async {
    await db.lendingRecordsDao.patch(
      id,
      LendingRecordsCompanion(
        returnedDate: Value(returnedDate),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'update',
      data: {'returned_date': returnedDate.toUtc().toIso8601String().split('T').first},
    );
  }
}
