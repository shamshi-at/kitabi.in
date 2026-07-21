import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
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

/// The sitting's UUID, minted when it *starts* rather than when it's logged —
/// a note written mid-session has to reference a real session id, and the row
/// only appears on stop (rule 4: UUIDs are client-side anyway).
const activeSessionIdKey = 'active_session_id';

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
  const ActiveSession({
    required this.libraryEntryId,
    required this.startedAt,
    required this.id,
    this.pageStart,
  });

  final String libraryEntryId;
  final DateTime startedAt;

  /// Minted at start so mid-session notes can point at this sitting before
  /// its row exists.
  final String id;
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
    // Reuse the id notes were already written against, so they stay attached.
    id: await db.keyValuesDao.getValue(activeSessionIdKey),
  );

  await db.keyValuesDao.deleteValue(activeSessionEntryKey);
  await db.keyValuesDao.deleteValue(activeSessionStartedKey);
  await db.keyValuesDao.deleteValue(activeSessionPageStartKey);
  await db.keyValuesDao.deleteValue(activeSessionIdKey);

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
  // Guards checkReadingTimerSafetyNet's DB-divergence check against racing a
  // legitimate in-flight stop() (16 Jul 2026): stopAndLogActiveSession clears
  // KeyValues in several awaited steps before this Notifier's own `state`
  // finally goes null, so a concurrent per-second tick could catch that
  // transient window and read it as "stopped elsewhere," nulling state (and
  // popping the timer screen) before the button's own setState landed —
  // dropping the wax-seal page-count screen on what looked like most stops.
  bool _stopping = false;

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
    // A session restored from disk predating this key has no id; mint one now
    // so notes taken after the restore still have something to attach to.
    var sessionId = await db.keyValuesDao.getValue(activeSessionIdKey);
    if (sessionId == null || sessionId.isEmpty) {
      sessionId = const Uuid().v4();
      await db.keyValuesDao.setValue(activeSessionIdKey, sessionId);
    }
    state = ActiveSession(
      libraryEntryId: entryId,
      startedAt: startedAt,
      id: sessionId,
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
    final sessionId = const Uuid().v4();
    final db = ref.read(appDatabaseProvider);
    await db.keyValuesDao.setValue(activeSessionEntryKey, libraryEntryId);
    await db.keyValuesDao.setValue(activeSessionStartedKey, startedAt.toIso8601String());
    await db.keyValuesDao.setValue(activeSessionIdKey, sessionId);
    if (pageStart != null) {
      await db.keyValuesDao.setValue(activeSessionPageStartKey, '$pageStart');
    }
    state = ActiveSession(
      libraryEntryId: libraryEntryId,
      startedAt: startedAt,
      id: sessionId,
      pageStart: pageStart,
    );
  }

  /// Stops the running session (if any), logs it via the repository, and
  /// clears local state. Returns what got logged for the wax-seal screen —
  /// null if nothing was running.
  Future<LoggedSession?> stop() async {
    if (state == null) return null;
    _stopping = true;
    try {
      final db = ref.read(appDatabaseProvider);
      final session = await ref.read(sessionContextProvider.future);
      final logged = await stopAndLogActiveSession(
        db,
        session,
        onMutation: ref.read(syncTriggerProvider),
      );
      state = null;
      return logged;
    } finally {
      _stopping = false;
    }
  }

  /// Drops in-memory state without touching the DB or logging anything — for
  /// when a session was already stopped+logged elsewhere (a notification
  /// action, the enforcement task, both of which write through their own
  /// standalone `AppDatabase`, never this Notifier) and `state` just needs to
  /// catch up, not repeat the stop. See [checkReadingTimerSafetyNet].
  void clearStaleState() {
    state = null;
  }

  /// Whether this controller's own [stop] is mid-flight — see the [_stopping]
  /// field doc for why [checkReadingTimerSafetyNet] needs to know.
  bool get isStopping => _stopping;
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
///
/// Also piggybacks the same per-second tick to catch a *different* kind of
/// staleness: the check-in notification's "No, stop it" action and the
/// workmanager enforcement task both stop+log a session through their own
/// standalone `AppDatabase` (a background isolate has no access to this
/// app's live `ProviderContainer`), so that write never reaches this
/// Notifier's in-memory `state` — the mini-bar/timer screen kept ticking
/// even after the DB-side session was already closed (owner report, 16 Jul
/// 2026). If the DB's own active-session pointer no longer names this entry,
/// someone else already stopped it — just drop local state instead of
/// re-stopping (and double-logging) a session that's already gone.
///
/// Skips entirely while [ActiveSessionController.isStopping] — a legitimate
/// in-app `stop()` clears KeyValues in several awaited steps before its own
/// `state` finally goes null, and a concurrent tick landing in that window
/// misread it as "stopped elsewhere," racing ahead of the stop button's own
/// `setState` and popping the timer screen before the wax-seal page-count
/// step could show (bug introduced by this same safety-net check, caught
/// live on-device 16 Jul 2026).
Future<LoggedSession?> checkReadingTimerSafetyNet(WidgetRef ref) async {
  final active = ref.read(activeSessionProvider);
  if (active == null) return null;

  final notifier = ref.read(activeSessionProvider.notifier);
  if (notifier.isStopping) return null;

  final db = ref.read(appDatabaseProvider);
  final dbEntryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
  if (dbEntryId != active.libraryEntryId) {
    notifier.clearStaleState();
    return null;
  }

  final elapsed = DateTime.now().difference(active.startedAt);
  if (elapsed < readingCheckInDelay + readingCheckInGrace) return null;
  return notifier.stop();
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
