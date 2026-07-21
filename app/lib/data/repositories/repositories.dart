import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Shared UUID generator for client-side ids (rule 4: the client assigns ids
/// for offline-created rows).
const _uuid = Uuid();

/// Who's making this edit — `userId` scopes ownership, `deviceId` is the
/// same-user-multiple-devices conflict signal (see sync_op.py).
class SessionContext {
  const SessionContext({required this.userId, required this.deviceId});
  final String userId;
  final String deviceId;
}

abstract class Repo {
  Repo(this.db, this.session, {this.onMutation});

  final AppDatabase db;
  final SessionContext session;

  /// Fired after every enqueued op so the sync engine drains immediately —
  /// without it a mutation (e.g. marking a loan returned) sits in the queue
  /// until the next periodic/lifecycle trigger, up to 15 minutes away, and the
  /// counterparty sees stale state. Wired to [syncTriggerProvider].
  final void Function()? onMutation;

  /// Every mutation calls this — snake_case keys, matching what the API
  /// expects on `POST /sync/push`.
  Future<void> enqueue({
    required String entity,
    required String entityId,
    required String opType,
    required Map<String, dynamic> data,
  }) async {
    await db.syncQueueDao.enqueue(
      SyncQueueCompanion.insert(
        opId: _uuid.v4(),
        userId: Value(session.userId),
        deviceId: session.deviceId,
        entity: entity,
        entityId: entityId,
        opType: opType,
        payload: jsonEncode(data),
      ),
    );
    onMutation?.call();
  }
}

class LibraryRepository extends Repo {
  LibraryRepository(super.db, super.session, {super.onMutation});

  Stream<List<LibraryEntry>> watchActive() => db.libraryEntriesDao.watchActive();

  Future<LibraryEntry?> getByEditionId(String editionId) =>
      db.libraryEntriesDao.getByEditionId(editionId);

  Stream<LibraryEntry?> watchByEditionId(String editionId) =>
      db.libraryEntriesDao.watchByEditionId(editionId);

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
  /// [ownership] is 'owned' (default) or 'borrowed' — a borrowed entry is
  /// normally created via [LendingRepository.logBorrowed] instead of calling
  /// this directly, so its LendingRecord gets linked in the same breath.
  Future<String> add({
    required String editionId,
    String status = 'pending',
    String ownership = 'owned',
  }) async {
    // One active entry per edition — a double-tap on "Add to library" (each
    // tap awaits the catalog cache write first, plenty of time for a second
    // tap) must not create a duplicate row; reuse the existing entry instead.
    final existing = await getByEditionId(editionId);
    if (existing != null) return existing.id;
    final id = _uuid.v4();
    await db.libraryEntriesDao.insertOne(
      LibraryEntriesCompanion.insert(
        id: id,
        userId: session.userId,
        editionId: editionId,
        status: Value(status),
        ownership: Value(ownership),
      ),
    );
    await enqueue(
      entity: 'library_entries',
      entityId: id,
      opType: 'create',
      data: {'edition_id': editionId, 'status': status, 'ownership': ownership},
    );
    return id;
  }

  /// The "I bought this" transition (owner request, 15 Jul 2026) — a reader
  /// who bought their own copy of a book they'd borrowed flips this same
  /// entry from 'borrowed' to 'owned' (same id, so reading status/progress/
  /// notes/favorite carry over untouched). The linked LendingRecord — the
  /// permanent log of the loan — is never touched by this.
  Future<void> markAsOwned(String id) async {
    await db.libraryEntriesDao.patch(
      id,
      LibraryEntriesCompanion(
        ownership: Value('owned'),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(
      entity: 'library_entries',
      entityId: id,
      opType: 'update',
      data: {'ownership': 'owned'},
    );
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
    // Plain `date` columns on the server — a full timestamp is rejected as
    // invalid_payload (Pydantic only accepts zero-time datetimes for a date).
    if (startDate != null) {
      changes['start_date'] = startDate.toUtc().toIso8601String().split('T').first;
    }
    if (finishDate != null) {
      changes['finish_date'] = finishDate.toUtc().toIso8601String().split('T').first;
    }
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
  RatingsRepository(super.db, super.session, {super.onMutation});

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

/// Private per-book notes (rule 13). Offline-first like every Layer-2 repo:
/// write to Drift, enqueue the op, let the sync engine carry it to the
/// reader's other devices.
class ReadingNotesRepository extends Repo {
  ReadingNotesRepository(super.db, super.session, {super.onMutation});

  Stream<List<ReadingNote>> watchForEntry(String libraryEntryId) =>
      db.readingNotesDao.watchForEntry(libraryEntryId);

  Stream<List<ReadingNote>> watchForSession(String sessionId) =>
      db.readingNotesDao.watchForSession(sessionId);

  /// [sessionId] is null for a note that belongs to the book rather than to a
  /// stretch of reading. [pageEnd] is null for a note about a single page.
  Future<String> add({
    required String libraryEntryId,
    required String body,
    String? sessionId,
    int? pageStart,
    int? pageEnd,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await db.readingNotesDao.insertOne(
      ReadingNotesCompanion.insert(
        id: id,
        userId: session.userId,
        libraryEntryId: libraryEntryId,
        body: body,
        sessionId: Value(sessionId),
        pageStart: Value(pageStart),
        pageEnd: Value(pageEnd),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'reading_notes',
      entityId: id,
      opType: 'create',
      data: {
        'library_entry_id': libraryEntryId,
        'body': body,
        'session_id': ?sessionId,
        'page_start': ?pageStart,
        'page_end': ?pageEnd,
      },
    );
    return id;
  }

  /// Editing the words never re-dates the note or moves it off its sitting —
  /// the journal is a record of when you thought something, not a draft.
  /// Passing null for a page clears it, so a note can be unpinned.
  Future<void> edit(
    String id, {
    required String body,
    int? pageStart,
    int? pageEnd,
  }) async {
    await db.readingNotesDao.patch(
      id,
      ReadingNotesCompanion(
        body: Value(body),
        pageStart: Value(pageStart),
        pageEnd: Value(pageEnd),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'reading_notes',
      entityId: id,
      opType: 'update',
      data: {'body': body, 'page_start': pageStart, 'page_end': pageEnd},
    );
  }

  /// Soft delete (rule 3) — the tombstone is what tells the reader's other
  /// devices to drop it.
  Future<void> remove(String id) async {
    await db.readingNotesDao.patch(
      id,
      ReadingNotesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'reading_notes',
      entityId: id,
      opType: 'delete',
      data: const {},
    );
  }
}

class ReadingSessionsRepository extends Repo {
  ReadingSessionsRepository(super.db, super.session, {super.onMutation});

  Stream<List<ReadingSession>> watchForEntry(String libraryEntryId) =>
      db.readingSessionsDao.watchForEntry(libraryEntryId);

  /// Every session with any minute in [since]..now — Home/Insights bucket
  /// these by day themselves rather than pushing GROUP BY into SQL for what's
  /// already a small, fully-loaded row set.
  Future<List<ReadingSession>> sessionsSince(DateTime since) =>
      db.readingSessionsDao.allSince(since);

  Future<int> totalSecondsSince(DateTime since) async {
    final sessions = await sessionsSince(since);
    return sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
  }

  /// Only ever called once a session has actually stopped — the live "timer
  /// running" state is device-local (see `activeSessionProvider`), never a
  /// row here until this is called. Returns the new session's id, so the
  /// wax-seal confirmation can attach a page number moments later without
  /// re-deriving which row it meant.
  /// [id] lets the caller mint the session's UUID up front (rule 4). The timer
  /// does: notes written mid-session need a real session to point at, and the
  /// row doesn't exist until the sitting stops.
  Future<String> logSession({
    required String libraryEntryId,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationSeconds,
    int? pageStart,
    int? pageEnd,
    String? id,
  }) async {
    id ??= _uuid.v4();
    await db.readingSessionsDao.insertOne(
      ReadingSessionsCompanion.insert(
        id: id,
        userId: session.userId,
        libraryEntryId: libraryEntryId,
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        pageStart: Value(pageStart),
        pageEnd: Value(pageEnd),
      ),
    );
    await enqueue(
      entity: 'reading_sessions',
      entityId: id,
      opType: 'create',
      data: {
        'library_entry_id': libraryEntryId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'page_start': ?pageStart,
        'page_end': ?pageEnd,
      },
    );
    return id;
  }

  /// The wax-seal screen's optional "read up to page ___" field — a
  /// same-device edit moments after the session was logged, not a separate
  /// user action worth its own confirmation.
  Future<void> updateSessionPageEnd(String sessionId, int pageEnd) async {
    await db.readingSessionsDao.patch(
      sessionId,
      ReadingSessionsCompanion(
        pageEnd: Value(pageEnd),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(
      entity: 'reading_sessions',
      entityId: sessionId,
      opType: 'update',
      data: {'page_end': pageEnd},
    );
  }

  /// Remove a stray session from the reading log (soft delete — the reader
  /// deleting a mistimed 5-second sitting, from the reading-log sheet).
  Future<void> deleteSession(String sessionId) async {
    await db.readingSessionsDao.patch(
      sessionId,
      ReadingSessionsCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(entity: 'reading_sessions', entityId: sessionId, opType: 'delete', data: {});
  }
}

class ReviewsRepository extends Repo {
  ReviewsRepository(super.db, super.session, {super.onMutation});

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
  TagsRepository(super.db, super.session, {super.onMutation});

  Stream<List<PersonalTag>> watchAll() => db.tagsDao.watchAll();

  Stream<List<LibraryEntryTag>> watchForEntry(String libraryEntryId) =>
      db.tagsDao.watchForEntry(libraryEntryId);

  /// Every active shelf assignment — feeds the library's shelves view.
  Stream<List<LibraryEntryTag>> watchAssignments() => db.tagsDao.watchAllAssignments();

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

  /// One book, one shelf (owner rule, 19 Jul 2026): put this entry on [tagId]
  /// and take it off every other shelf. A no-op if it's already only there.
  /// Each add/remove enqueues its own op, so the move syncs like any edit.
  Future<void> shelveExclusive(String libraryEntryId, String tagId) async {
    final current = await db.tagsDao.watchForEntry(libraryEntryId).first;
    for (final a in current) {
      if (a.tagId != tagId) await unassign(a.id);
    }
    if (!current.any((a) => a.tagId == tagId)) await assign(libraryEntryId, tagId);
  }
}

class LendingRepository extends Repo {
  LendingRepository(super.db, super.session, {super.onMutation});

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

  /// Log a borrowed book (S8c) — the other direction. Creates a real
  /// LibraryEntry (`ownership: 'borrowed'`) linked via `libraryEntryId`, so
  /// the borrowed book gets full reading status/progress/notes just like an
  /// owned one (owner request, 15 Jul 2026) — it stays on the shelf after
  /// it's returned (that's derived from this record's `returnedDate`, never
  /// stored on the entry) and flips to owned in place if the reader later
  /// buys their own copy ([LibraryRepository.markAsOwned]). `editionId`
  /// stays populated too, for continuity with pre-15-Jul rows that only ever
  /// had that. `lenderName` is who I borrowed it from.
  ///
  /// Reuses an existing entry for this edition if there is one — already
  /// owned, or borrowed-and-returned before — rather than creating a second
  /// row for the same book (the app assumes one active entry per edition;
  /// re-borrowing a book you'd previously borrowed just continues the same
  /// reading record instead of forking it).
  Future<String> logBorrowed({
    required String editionId,
    required String lenderName,
    required DateTime borrowedDate,
    DateTime? dueDate,
    String? note,
    String? borrowerUserId,
  }) async {
    final libraryRepo = LibraryRepository(db, session, onMutation: onMutation);
    final existing = await libraryRepo.getByEditionId(editionId);
    final libraryEntryId =
        existing?.id ?? await libraryRepo.add(editionId: editionId, ownership: 'borrowed');

    final id = _uuid.v4();
    final trimmedNote = note?.trim();
    await db.lendingRecordsDao.insertOne(
      LendingRecordsCompanion.insert(
        id: id,
        userId: session.userId,
        direction: Value('borrowed'),
        libraryEntryId: Value(libraryEntryId),
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
        'library_entry_id': libraryEntryId,
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
