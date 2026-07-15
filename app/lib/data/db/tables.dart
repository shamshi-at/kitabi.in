import 'package:drift/drift.dart';

/// Columns every syncable (Layer 2) table carries (CLAUDE.md rule 10),
/// ported from rupee-diary's `SyncColumns` — `userId` instead of
/// `budgetId`/`createdBy` since Kitabi has no cross-user sharing in V1.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  IntColumn get serverSeq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A user's copy of an Edition — ownership, reading status, progress,
/// favorite flag, and always-private notes (feature-map.md rule 13).
///
/// `ownership` (added 15 Jul 2026, owner request) is 'owned' or 'borrowed' —
/// a borrowed book gets a real row here (via the log-a-borrowed-book flow)
/// so status/progress/notes work on it exactly like an owned book. It's
/// never deleted on return: "returned" lives only on the linked
/// LendingRecord (`lendingRecords.libraryEntryId` points back at this row),
/// never duplicated here. Buying your own copy later just flips this to
/// 'owned' on the same row — history intact, the LendingRecord stays as the
/// permanent log of the loan.
class LibraryEntries extends Table with SyncColumns {
  TextColumn get editionId => text()();
  TextColumn get status => text().withDefault(Constant('pending'))();
  TextColumn get ownership => text().withDefault(Constant('owned'))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get finishDate => dateTime().nullable()();
  IntColumn get currentPage => integer().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(Constant(false))();
  TextColumn get notes => text().nullable()();
}

/// Star rating (1-5) — attaches to the Work (rule 17), shared across every
/// edition/printing; a translation is its own Work, so its own rating pool.
class Ratings extends Table with SyncColumns {
  TextColumn get workId => text()();
  IntColumn get value => integer()();
}

/// A timed start-to-stop reading session against a library entry (a specific
/// owned copy — progress already lives on LibraryEntries, this is the timed
/// log). Only ever enqueued for sync once stopped; the live "timer running"
/// state itself is device-local (KeyValues), never a row here until it ends.
class ReadingSessions extends Table with SyncColumns {
  TextColumn get libraryEntryId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  IntColumn get pageStart => integer().nullable()();
  IntColumn get pageEnd => integer().nullable()();
}

/// Text review — Work + user, own visibility flag (default private).
class Reviews extends Table with SyncColumns {
  TextColumn get workId => text()();
  TextColumn get body => text()();
  BoolColumn get visible => boolean().withDefault(Constant(false))();
}

/// A user's own shelf/tag — never conflated with the global Genre (rule 6).
class PersonalTags extends Table with SyncColumns {
  TextColumn get name => text()();
}

/// Tag-to-entry assignment as its own syncable row (not a bare join table)
/// so add/remove on separate devices gets the same conflict handling as
/// everything else.
class LibraryEntryTags extends Table with SyncColumns {
  TextColumn get libraryEntryId => text()();
  TextColumn get tagId => text()();
}

/// A record, not a flag (rule 14) — runs both ways. `direction` is 'lent' or
/// 'borrowed'; either way `libraryEntryId` points at my own LibraryEntry for
/// this loan — the owned copy that went out (lent) or the `ownership:
/// 'borrowed'` entry the log-a-borrowed-book flow creates (borrowed, added
/// 15 Jul 2026). `editionId` stays populated on borrowed rows too, so older
/// rows that predate `libraryEntryId` still resolve the book. `borrowerName`
/// is the counterparty either way. `linkedLoanId` is the dormant [WIRED]
/// cross-user correlation.
class LendingRecords extends Table with SyncColumns {
  TextColumn get direction => text().withDefault(Constant('lent'))();
  TextColumn get libraryEntryId => text().nullable()();
  TextColumn get editionId => text().nullable()();
  TextColumn get borrowerName => text()();
  TextColumn get borrowerUserId => text().nullable()();
  TextColumn get linkedLoanId => text().nullable()();
  DateTimeColumn get lentDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get returnedDate => dateTime().nullable()();
  TextColumn get note => text().nullable()();
}

/// [WIRED] — pulled from the server, never pushed; the server writes these
/// as a side effect of other mutations (rule 15: the future community feed).
class ActivityLogEntries extends Table with SyncColumns {
  TextColumn get eventType => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get payload => text().withDefault(Constant('{}'))(); // JSON
  DateTimeColumn get occurredAt => dateTime()();
}

/// Outbox for local mutations — the drain phase batches these to
/// `POST /sync/push`; `opId` is the idempotency key.
class SyncQueue extends Table {
  TextColumn get opId => text()();
  // Who enqueued this op — the drain only pushes the signed-in user's ops, so
  // an account switch racing a sync can never push one reader's edits under
  // another reader's JWT. '' on rows queued before this column existed.
  TextColumn get userId => text().withDefault(Constant(''))();
  // Captured at enqueue time (which device made this edit), not at push
  // time — the whole point is answering "which device did this," and a
  // queued op can sit offline for a while before it's actually pushed.
  TextColumn get deviceId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get opType => text()();
  TextColumn get payload => text()(); // JSON, snake_case keys (wire format)
  IntColumn get attempts => integer().withDefault(Constant(0))();
  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {opId};
}

/// The pull cursor — `server_seq`, never a timestamp. One row per signed-in
/// user (device-local; a fresh sign-in on this device starts from 0).
class SyncState extends Table {
  TextColumn get userId => text()();
  IntColumn get cursor => integer().withDefault(Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}

/// Local conflict log pulled from the server (CLAUDE.md rule 6) — mirrors
/// `conflict_history` server-side so a future "sync issues" view works
/// offline. No dedicated screen yet; the table exists so nothing is lost.
class ConflictHistoryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get rule => text()();
  TextColumn get winningPayload => text()();
  TextColumn get discardedPayload => text()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small persisted settings — device_id (generated once per install, used
/// as the sync conflict signal), and anything else that doesn't warrant
/// its own table.
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// A denormalized, read-only cache of catalog data (Layer 1) fetched from
/// the API — NOT synced (CLAUDE.md rule 2: fetched/cached for offline
/// reading, never client-authored). Flattened rather than mirroring the
/// full works/editions/authors schema, since this only needs to answer
/// "what does the library grid show for this edition" while offline.
class CachedBooks extends Table {
  TextColumn get editionId => text()();
  TextColumn get workId => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get authorNames => text()(); // comma-joined
  TextColumn get publisherName => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  IntColumn get seriesNumber => integer().nullable()();
  TextColumn get isbn => text().nullable()();
  TextColumn get language => text().nullable()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get format => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  IntColumn get firstPublishYear => integer().nullable()();
  TextColumn get genreNames => text().nullable()(); // comma-joined
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {editionId};
}
