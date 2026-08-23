import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../sync/note_session_links.dart';

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

  /// The reader's rating of a *series* — its own row, never the average of
  /// what they thought of the volumes.
  Stream<Rating?> watchForSeries(String seriesId) => db.ratingsDao.watchForSeries(seriesId);

  /// workId -> value, across every rated Work — the shape Insights' finished-
  /// books strip needs (one lookup per cover, not one stream per cover).
  /// Series ratings are not in here: the DAO filters them out, because that
  /// strip is about books on a shelf and a series has no cover to sit under.
  Stream<Map<String, int>> watchAllByWorkId() => db.ratingsDao
      .watchAll()
      .map((rows) => {for (final r in rows) if (r.workId != null) r.workId!: r.value});

  /// One rating per work — updates the existing row if there is one.
  Future<void> setRating(String workId, int value) async =>
      _set(await db.ratingsDao.watchForWork(workId).first, value, workId: workId);

  /// Rate the saga as a whole. A different claim from rating its volumes, so a
  /// different row — and the server keeps the two pools apart as well.
  Future<void> setSeriesRating(String seriesId, int value) async =>
      _set(await db.ratingsDao.watchForSeries(seriesId).first, value, seriesId: seriesId);

  /// Takes the rating back (soft delete, rule 3) — a second tap on the
  /// selected star means "no rating", not "rate it again".
  Future<void> clearRating(String workId) async =>
      _clear(await db.ratingsDao.watchForWork(workId).first);

  Future<void> clearSeriesRating(String seriesId) async =>
      _clear(await db.ratingsDao.watchForSeries(seriesId).first);

  /// The one write path, whichever subject it is about — so the book flow and
  /// the series flow can never drift into behaving differently.
  Future<void> _set(Rating? existing, int value, {String? workId, String? seriesId}) async {
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
      RatingsCompanion.insert(
        id: id,
        userId: session.userId,
        workId: Value(workId),
        seriesId: Value(seriesId),
        value: value,
      ),
    );
    await enqueue(
      entity: 'ratings',
      entityId: id,
      opType: 'create',
      // Exactly one subject key — the server rejects an op naming both or
      // neither, so sending only the one that applies is the contract.
      data: {'work_id': ?workId, 'series_id': ?seriesId, 'value': value},
    );
  }

  Future<void> _clear(Rating? existing) async {
    if (existing == null) return;
    await db.ratingsDao.patch(
      existing.id,
      RatingsCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
    );
    await enqueue(entity: 'ratings', entityId: existing.id, opType: 'delete', data: {});
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
    // The sitting a note was written during only becomes a *row* when the
    // sitting stops — before that it lives in key_values, device-local by
    // design. So a note jotted mid-sitting names a `reading_sessions` id the
    // server has never heard of, and the server (rightly) refuses to hang a
    // note off a session it can't prove belongs to this reader: rejected as
    // `invalid_reference`, dropped from the queue, marked errored. Every note
    // written while a timer ran — the ones the feature exists for — was
    // therefore local to that phone forever.
    //
    // So the link is withheld from the wire until there is something to link
    // to, and [ReadingSessionsRepository.logSession] sends it the moment the
    // sitting is logged. Locally the note is attached the whole time; this is
    // only about what a server can be told and when.
    final sessionExists =
        sessionId != null && await db.readingSessionsDao.getById(sessionId) != null;
    if (sessionId != null && !sessionExists) {
      await rememberNoteSessionLink(db, noteId: id, sessionId: sessionId);
    }
    await enqueue(
      entity: 'reading_notes',
      entityId: id,
      opType: 'create',
      data: {
        'library_entry_id': libraryEntryId,
        'body': body,
        if (sessionExists) 'session_id': sessionId,
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

  /// Reactive twin of [sessionsSince] — feeds the reading-pace figure, which
  /// must refresh the moment any of the four logging routes writes a sitting.
  Stream<List<ReadingSession>> watchSessionsSince(DateTime since) =>
      db.readingSessionsDao.watchAllSince(since);

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
    bool autoStopped = false,
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
        autoStopped: Value(autoStopped),
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
        'auto_stopped': autoStopped,
      },
    );
    // Now that the sitting is a row the server will accept, hand it the notes
    // that were written against it while it was only a running clock — see
    // the long note in [ReadingNotesRepository.add]. Enqueued *after* the
    // create above, so the queue's own order (oldest first) delivers the
    // session before anything that points at it.
    //
    // The same call runs after every pull, because the device that stops a
    // sitting need not be the one that wrote its notes.
    await publishPendingNoteLinks(db, userId: session.userId, deviceId: session.deviceId);
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

  /// Corrects a sitting's end time (and the duration derived from it) and
  /// optionally its end page — for a sitting the auto-stop safety net closed
  /// while the reader kept reading unnoticed, so the recorded end no longer
  /// matches when they actually put the book down (owner report, 23 Aug
  /// 2026). [startedAt] is passed rather than re-read so the duration
  /// recompute can't drift from what the editing screen already has on
  /// screen. Leaves `autoStopped` as-is — it's the historical fact that this
  /// sitting was closed by the safety net, not a review flag to clear.
  Future<void> correctSessionEnd(
    String sessionId, {
    required DateTime startedAt,
    required DateTime endedAt,
    int? pageEnd,
  }) async {
    final durationSeconds = endedAt.difference(startedAt).inSeconds;
    await db.readingSessionsDao.patch(
      sessionId,
      ReadingSessionsCompanion(
        endedAt: Value(endedAt),
        durationSeconds: Value(durationSeconds),
        pageEnd: pageEnd == null ? const Value.absent() : Value(pageEnd),
        updatedAt: Value(DateTime.now()),
        syncStatus: Value('pending'),
      ),
    );
    await enqueue(
      entity: 'reading_sessions',
      entityId: sessionId,
      opType: 'update',
      data: {
        'ended_at': endedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'page_end': ?pageEnd,
      },
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

  /// The reader's review *of the series* — separate from anything they wrote
  /// about its volumes.
  Stream<Review?> watchForSeries(String seriesId) => db.reviewsDao.watchForSeries(seriesId);

  Future<void> upsert(String workId, {required String body, required bool visible}) async =>
      _upsert(await db.reviewsDao.watchForWork(workId).first,
          body: body, visible: visible, workId: workId);

  /// Review the saga as a whole.
  Future<void> upsertForSeries(
    String seriesId, {
    required String body,
    required bool visible,
  }) async =>
      _upsert(await db.reviewsDao.watchForSeries(seriesId).first,
          body: body, visible: visible, seriesId: seriesId);

  Future<void> removeForSeries(String seriesId) async {
    final existing = await db.reviewsDao.watchForSeries(seriesId).first;
    if (existing == null) return;
    await db.reviewsDao.patch(
      existing.id,
      ReviewsCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
    );
    await enqueue(entity: 'reviews', entityId: existing.id, opType: 'delete', data: {});
  }

  /// One write path for both subjects, so the book flow and the series flow
  /// cannot drift apart.
  Future<void> _upsert(
    Review? existing, {
    required String body,
    required bool visible,
    String? workId,
    String? seriesId,
  }) async {
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
        workId: Value(workId),
        seriesId: Value(seriesId),
        body: body,
        visible: Value(visible),
      ),
    );
    await enqueue(
      entity: 'reviews',
      entityId: id,
      opType: 'create',
      // Exactly one subject key — the server rejects an op naming both.
      data: {
        'work_id': ?workId,
        'series_id': ?seriesId,
        'body': body,
        'visible': visible,
      },
    );
  }

  /// Deletes the reader's review of [workId] (soft delete, rule 3). An emptied
  /// body on the editor's Save means "take it back" — silently keeping the old
  /// text while toasting "saved" was the lie this exists to end.
  Future<void> removeForWork(String workId) async {
    final existing = await db.reviewsDao.watchForWork(workId).first;
    if (existing == null) return;
    await db.reviewsDao.patch(
      existing.id,
      ReviewsCompanion(deletedAt: Value(DateTime.now()), syncStatus: Value('pending')),
    );
    await enqueue(entity: 'reviews', entityId: existing.id, opType: 'delete', data: {});
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

  /// Undo a mark-returned (the ledger's SnackBar Undo) — clears the returned
  /// date so the loan reads as open again. Present-and-null clears it
  /// server-side too, same contract as [updateBorrower]'s borrower link.
  Future<void> reopenLoan(String id) async {
    await db.lendingRecordsDao.patch(
      id,
      LendingRecordsCompanion(
        returnedDate: const Value(null),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
    await enqueue(
      entity: 'lending_records',
      entityId: id,
      opType: 'update',
      data: {'returned_date': null},
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
