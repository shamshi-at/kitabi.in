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

  /// Global search (S4) over the personal library — offline, from Drift.
  Future<List<LibraryHit>> search(String query) => db.libraryEntriesDao.search(query);

  /// All entries joined to their books — for the insights/stats screen (S10).
  Future<List<LibraryHit>> allWithBooks() => db.libraryEntriesDao.allWithBooks();

  /// Reactive entries-with-books — the library grid (S5) filters on this.
  Stream<List<LibraryHit>> watchWithBooks() => db.libraryEntriesDao.watchAllWithBooks();

  /// Personal reading goal (books/year). Device-local for now (key_values);
  /// becomes syncable when a settings sync lands. Defaults to 30.
  Future<int> readingGoal() async {
    final raw = await db.keyValuesDao.getValue('reading_goal');
    return int.tryParse(raw ?? '') ?? 30;
  }

  Future<void> setReadingGoal(int goal) =>
      db.keyValuesDao.setValue('reading_goal', '$goal');

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
        syncStatus: Value('pending'),
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
        currentPage: currentPage != null ? Value(currentPage) : Value.absent(),
        startDate: startDate != null ? Value(startDate) : Value.absent(),
        finishDate: finishDate != null ? Value(finishDate) : Value.absent(),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
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
        syncStatus: Value('pending'),
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
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(entity: 'library_entries', entityId: id, opType: 'update', data: {'notes': notes});
  }

  Future<void> remove(String id) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
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
          syncStatus: Value('pending'),
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
          syncStatus: Value('pending'),
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
        syncStatus: Value('pending'),
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
    String? note,
    String? borrowerUserId,
  }) async {
    final id = _uuid.v4();
    final trimmedNote = note?.trim();
    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: id,
        userId: session.userId,
        libraryEntryId: Value(libraryEntryId),
        borrowerName: borrowerName,
        borrowerUserId: Value(borrowerUserId),
        lentDate: lentDate,
        dueDate: Value(dueDate),
        note: Value(trimmedNote),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'create',
      data: {
        'direction': 'lent',
        'library_entry_id': libraryEntryId,
        'borrower_name': borrowerName,
        // Set when the borrower is a Kitabi user (found by username); null for a
        // private contact typed by hand.
        'borrower_user_id': ?borrowerUserId,
        'lent_date': lentDate.toUtc().toIso8601String().split('T').first,
        if (dueDate != null) 'due_date': dueDate.toUtc().toIso8601String().split('T').first,
        if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
      },
    );
    return id;
  }

  /// Log a borrowed book (S8c) — the other direction. There's no owned library
  /// entry, so the book is carried by the catalog `editionId`. `lenderName` is
  /// who I borrowed it from.
  Future<String> logBorrowed({
    required String editionId,
    required String lenderName,
    required DateTime borrowedDate,
    DateTime? dueDate,
    String? note,
    String? borrowerUserId,
  }) async {
    final id = _uuid.v4();
    final trimmedNote = note?.trim();
    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: id,
        userId: session.userId,
        direction: Value('borrowed'),
        editionId: Value(editionId),
        borrowerName: lenderName,
        borrowerUserId: Value(borrowerUserId),
        lentDate: borrowedDate,
        dueDate: Value(dueDate),
        note: Value(trimmedNote),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'create',
      data: {
        'direction': 'borrowed',
        'edition_id': editionId,
        'borrower_name': lenderName,
        // The Kitabi user I borrowed from, when matched by username.
        'borrower_user_id': ?borrowerUserId,
        'lent_date': borrowedDate.toUtc().toIso8601String().split('T').first,
        if (dueDate != null) 'due_date': dueDate.toUtc().toIso8601String().split('T').first,
        if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
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
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'update',
      data: {'returned_date': returnedDate.toUtc().toIso8601String().split('T').first},
    );
  }

  /// Re-point who a loan is to. Used to "make private contact" — dropping the
  /// Kitabi user link (pass `borrowerUserId: null`) after they declined, keeping
  /// the loan as a plain free-text borrower. Explicit-null clears the link both
  /// locally and (via the sync op) server-side.
  Future<void> updateBorrower(
    String id, {
    required String borrowerName,
    String? borrowerUserId,
  }) async {
    await db.lendingRecordsDao.patch(
      id,
      LendingRecordsCompanion(
        borrowerName: Value(borrowerName),
        borrowerUserId: Value(borrowerUserId),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'update',
      data: {
        'borrower_name': borrowerName,
        // Present-and-null clears the link server-side (LendingRecordUpdate).
        'borrower_user_id': borrowerUserId,
      },
    );
  }
}
