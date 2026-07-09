import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import 'library_providers.dart';

const _entryKey = 'active_session_entry_id';
const _startedKey = 'active_session_started_at';
const _pageStartKey = 'active_session_page_start';

/// The one reading session currently running, if any — device-local
/// (KeyValues), never synced until it's stopped and logged as a
/// [ReadingSessionsRepository.logSession] row. Only one runs app-wide at a
/// time: you can't actually read two books in the same minute.
class ActiveSession {
  const ActiveSession({required this.libraryEntryId, required this.startedAt, this.pageStart});

  final String libraryEntryId;
  final DateTime startedAt;
  final int? pageStart;
}

/// The result of stopping a session — what the wax-seal confirmation screen
/// needs to show, and [sessionId] so it can attach a page number moments
/// later via [ReadingSessionsRepository.updateSessionPageEnd].
class LoggedSession {
  const LoggedSession({
    required this.sessionId,
    required this.libraryEntryId,
    required this.durationSeconds,
  });

  final String sessionId;
  final String libraryEntryId;
  final int durationSeconds;
}

/// Same load-on-build, write-through-on-change shape as
/// `ThemeModeController` — restores a session still running after an app
/// restart (kill+reopen mid-session shouldn't lose the clock).
class ActiveSessionController extends Notifier<ActiveSession?> {
  @override
  ActiveSession? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final db = ref.read(appDatabaseProvider);
    final entryId = await db.keyValuesDao.getValue(_entryKey);
    final startedRaw = await db.keyValuesDao.getValue(_startedKey);
    if (entryId == null || startedRaw == null) return;
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) return;
    final pageStartRaw = await db.keyValuesDao.getValue(_pageStartKey);
    state = ActiveSession(
      libraryEntryId: entryId,
      startedAt: startedAt,
      pageStart: int.tryParse(pageStartRaw ?? ''),
    );
  }

  /// Starts a session on [libraryEntryId] — auto-stopping (and logging)
  /// whatever else was running first, since overlapping sessions don't mean
  /// anything. A no-op if this same entry is already the one running.
  /// [pageStart] is normally the book's current page at the moment reading
  /// began, captured once here rather than re-read at stop time.
  Future<void> start(String libraryEntryId, {int? pageStart}) async {
    if (state?.libraryEntryId == libraryEntryId) return;
    if (state != null) await stop();

    final startedAt = DateTime.now();
    final db = ref.read(appDatabaseProvider);
    await db.keyValuesDao.setValue(_entryKey, libraryEntryId);
    await db.keyValuesDao.setValue(_startedKey, startedAt.toIso8601String());
    if (pageStart != null) {
      await db.keyValuesDao.setValue(_pageStartKey, '$pageStart');
    }
    state = ActiveSession(libraryEntryId: libraryEntryId, startedAt: startedAt, pageStart: pageStart);
  }

  /// Stops the running session (if any), logs it via the repository, and
  /// clears local state. Returns what got logged for the wax-seal screen —
  /// null if nothing was running.
  Future<LoggedSession?> stop() async {
    final current = state;
    if (current == null) return null;

    final endedAt = DateTime.now();
    final durationSeconds = endedAt.difference(current.startedAt).inSeconds;
    final repo = await ref.read(readingSessionsRepositoryProvider.future);
    final sessionId = await repo.logSession(
      libraryEntryId: current.libraryEntryId,
      startedAt: current.startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      pageStart: current.pageStart,
    );

    final db = ref.read(appDatabaseProvider);
    await db.keyValuesDao.deleteValue(_entryKey);
    await db.keyValuesDao.deleteValue(_startedKey);
    await db.keyValuesDao.deleteValue(_pageStartKey);
    state = null;
    return LoggedSession(
      sessionId: sessionId,
      libraryEntryId: current.libraryEntryId,
      durationSeconds: durationSeconds,
    );
  }
}

final activeSessionProvider =
    NotifierProvider<ActiveSessionController, ActiveSession?>(ActiveSessionController.new);

/// What the active session's book actually is — title/cover for the mini-bar,
/// which only has the raw `libraryEntryId` to go on. Reuses the
/// already-watched full-library stream rather than adding a new get-by-id
/// DAO method for what's a rare, single-row lookup.
class ActiveSessionBook {
  const ActiveSessionBook({required this.entry, this.book});

  final LibraryEntry entry;
  final CachedBook? book;
}

final activeSessionBookProvider = Provider.autoDispose<ActiveSessionBook?>((ref) {
  final active = ref.watch(activeSessionProvider);
  if (active == null) return null;
  final entries = ref.watch(libraryEntriesProvider).valueOrNull ?? const <LibraryEntry>[];
  LibraryEntry? entry;
  for (final e in entries) {
    if (e.id == active.libraryEntryId) {
      entry = e;
      break;
    }
  }
  if (entry == null) return null;
  final book = ref.watch(cachedBookProvider(entry.editionId)).valueOrNull;
  return ActiveSessionBook(entry: entry, book: book);
});

/// Total reading seconds since the start of this week (Monday 00:00, local
/// time) — the wax-seal screen's second stat, and Home/Insights' weekly
/// figure. Re-fetch via `ref.invalidate` after a session is logged.
final weeklyReadingSecondsProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(readingSessionsRepositoryProvider.future);
  final now = DateTime.now();
  final since = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  return repo.totalSecondsSince(since);
});
