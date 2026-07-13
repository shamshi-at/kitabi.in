import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repositories.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import 'library_providers.dart';

// Public (not file-private) because the background notification-action
// handler and the workmanager enforcement task (`reading_timer_notifications.dart`,
// `background_sync.dart`) need to read/write the exact same KeyValues rows
// from a separate isolate with no access to this file's Riverpod state.
const activeSessionEntryKey = 'active_session_entry_id';
const activeSessionStartedKey = 'active_session_started_at';
const activeSessionPageStartKey = 'active_session_page_start';

/// A session left running this long gets a "still reading?" check-in.
const readingCheckInDelay = Duration(minutes: 60);

/// If the check-in goes unanswered this much longer, the session is
/// auto-stopped — 90 minutes total from the original start.
const readingCheckInGrace = Duration(minutes: 30);

const readingCheckInYesActionId = 'reading_checkin_yes';
const readingCheckInNoActionId = 'reading_checkin_no';
const readingCheckInCategoryId = 'reading_checkin';

/// Deterministic per-entry ids/names so a later call (cancel, reschedule,
/// dedupe) always finds the same notification/task — same hashing trick as
/// `reminderIdForRecord` (lending), salted so the two families can never
/// collide even if a library entry id and a lending record id happened to
/// hash the same.
int readingCheckInNotificationId(String libraryEntryId) =>
    ('reading_checkin_$libraryEntryId').hashCode & 0x7fffffff;
int readingAutoStoppedNotificationId(String libraryEntryId) =>
    ('reading_autostopped_$libraryEntryId').hashCode & 0x7fffffff;
String readingEnforcementTaskName(String libraryEntryId) =>
    'kitabi.readingTimerAutoStop.$libraryEntryId';

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
/// later via [ReadingSessionsRepository.updateSessionPageEnd]. [pageStart] lets
/// the wax-seal screen compute pages-read live as the reader types an end page.
class LoggedSession {
  const LoggedSession({
    required this.sessionId,
    required this.libraryEntryId,
    required this.durationSeconds,
    this.pageStart,
  });

  final String sessionId;
  final String libraryEntryId;
  final int durationSeconds;
  final int? pageStart;
}

/// Stops whatever session is in [db]'s KeyValues (if any), logs it, and
/// clears local state — the single source of truth for "stop and log",
/// callable with no `ref`/Riverpod so the exact same logic runs from three
/// places: the foreground [ActiveSessionController.stop], the notification
/// "No, stop it" action, and the workmanager auto-stop enforcement task (both
/// in background isolates — see `reading_timer_notifications.dart` and
/// `background_sync.dart`). Reads straight from KeyValues rather than taking
/// an [ActiveSession] parameter so it's correct even when called from an
/// isolate that never hydrated any in-memory state.
Future<LoggedSession?> stopAndLogActiveSession(
  AppDatabase db,
  SessionContext session, {
  void Function()? onMutation,
}) async {
  final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
  final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
  if (entryId == null || startedRaw == null) return null;
  final startedAt = DateTime.tryParse(startedRaw);
  if (startedAt == null) return null;
  final pageStartRaw = await db.keyValuesDao.getValue(activeSessionPageStartKey);
  final pageStart = int.tryParse(pageStartRaw ?? '');

  final endedAt = DateTime.now();
  final durationSeconds = endedAt.difference(startedAt).inSeconds;
  final repo = ReadingSessionsRepository(db, session, onMutation: onMutation);
  final sessionId = await repo.logSession(
    libraryEntryId: entryId,
    startedAt: startedAt,
    endedAt: endedAt,
    durationSeconds: durationSeconds,
    pageStart: pageStart,
  );

  await db.keyValuesDao.deleteValue(activeSessionEntryKey);
  await db.keyValuesDao.deleteValue(activeSessionStartedKey);
  await db.keyValuesDao.deleteValue(activeSessionPageStartKey);

  // Every stop path — manual, quick-stop, "No", or auto-stop — goes through
  // here, so this is the one place that needs to cancel the check-in
  // notification and the enforcement task, instead of every call site
  // remembering to. Best-effort: a plugin channel that isn't ready (a
  // notification-less platform, a widget test with no platform channels
  // mocked) must never stop the session from being logged correctly.
  try {
    final notifications = NotificationService(FlutterLocalNotificationsPlugin());
    await notifications.cancel(readingCheckInNotificationId(entryId));
    await Workmanager().cancelByUniqueName(readingEnforcementTaskName(entryId));
  } catch (_) {}

  return LoggedSession(
    sessionId: sessionId,
    libraryEntryId: entryId,
    durationSeconds: durationSeconds,
    pageStart: pageStart,
  );
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
    final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
    final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
    if (entryId == null || startedRaw == null) return;
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) return;
    final pageStartRaw = await db.keyValuesDao.getValue(activeSessionPageStartKey);
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
  ///
  /// Scheduling the "still reading?" check-in is the caller's job (it needs
  /// localized copy from a `BuildContext`, which a `Notifier` doesn't have —
  /// see `_ReadingSessionCard._open` for the only call site).
  Future<void> start(String libraryEntryId, {int? pageStart}) async {
    if (state?.libraryEntryId == libraryEntryId) return;
    if (state != null) await stop();

    final startedAt = DateTime.now();
    final db = ref.read(appDatabaseProvider);
    await db.keyValuesDao.setValue(activeSessionEntryKey, libraryEntryId);
    await db.keyValuesDao.setValue(activeSessionStartedKey, startedAt.toIso8601String());
    if (pageStart != null) {
      await db.keyValuesDao.setValue(activeSessionPageStartKey, '$pageStart');
    }
    state = ActiveSession(libraryEntryId: libraryEntryId, startedAt: startedAt, pageStart: pageStart);
  }

  /// Stops the running session (if any), logs it via the repository, and
  /// clears local state. Returns what got logged for the wax-seal screen —
  /// null if nothing was running.
  Future<LoggedSession?> stop() async {
    if (state == null) return null;
    final db = ref.read(appDatabaseProvider);
    final session = await ref.read(sessionContextProvider.future);
    final logged = await stopAndLogActiveSession(
      db,
      session,
      onMutation: ref.read(syncTriggerProvider),
    );
    state = null;
    return logged;
  }
}

final activeSessionProvider =
    NotifierProvider<ActiveSessionController, ActiveSession?>(ActiveSessionController.new);

/// The deterministic, cross-platform half of the forgot-to-stop safety net:
/// the check-in notification and workmanager enforcement task are
/// best-effort (especially on iOS), but any screen that already ticks once a
/// second while a session is live — the mini-bar, the watch face, the book
/// page's live clock — can call this on every tick and it guarantees a
/// session is never found running past 90 minutes, independent of whether
/// the OS actually delivered either background mechanism. Returns the
/// [LoggedSession] (so the caller can show feedback) only when it actually
/// had to intervene; null otherwise.
Future<LoggedSession?> checkReadingTimerSafetyNet(WidgetRef ref) async {
  final active = ref.read(activeSessionProvider);
  if (active == null) return null;
  final elapsed = DateTime.now().difference(active.startedAt);
  if (elapsed < readingCheckInDelay + readingCheckInGrace) return null;
  return ref.read(activeSessionProvider.notifier).stop();
}

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
