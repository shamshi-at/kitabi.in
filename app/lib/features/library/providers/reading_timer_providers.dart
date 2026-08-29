import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reading_live_activity.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repositories.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import 'active_session_sync.dart';
import 'library_providers.dart';

// Public (not file-private) because the background notification-action
// handler and the workmanager enforcement task (`reading_timer_notifications.dart`,
// `background_sync.dart`) need to read/write the exact same KeyValues rows
// from a separate isolate with no access to this file's Riverpod state.
const activeSessionEntryKey = 'active_session_entry_id';
const activeSessionStartedKey = 'active_session_started_at';
const activeSessionPageStartKey = 'active_session_page_start';

/// When the reader last answered "Yes, still reading" to a check-in.
///
/// Without this, answering Yes was *cosmetic*: it re-armed the notification and
/// the enforcement task, but every in-app surface still measured the sitting's
/// age from `startedAt`, so the deterministic safety net stopped the sitting at
/// start + 90 minutes anyway — the moment any ticking surface came on screen
/// (owner report, 26 Jul 2026: opened the timer from the Live Activity and was
/// told it had stopped). A confirmation has to move the deadline for *every*
/// mechanism, not just the two background ones.
const activeSessionConfirmedKey = 'active_session_confirmed_at';

/// The sitting's UUID, minted when it *starts* rather than when it's logged —
/// a note written mid-session has to reference a real session id, and the row
/// only appears on stop (rule 4: UUIDs are client-side anyway).
const activeSessionIdKey = 'active_session_id';

/// Set to the session id of a sitting **the account knows about** — one this
/// device adopted from the server, or one it started here and successfully
/// published (owner request, 14 Aug 2026: the same account on two devices
/// shares one running timer).
///
/// It exists to make one distinction the pull cannot make otherwise: when the
/// server says nothing is running, that means "stopped on the other device"
/// for a sitting the account has heard of, and "we simply haven't published
/// ours yet" for one this device started while offline. Without it, a pull
/// during a network hiccup would throw away the reader's own running timer.
///
/// It used to be set **only** on adopt, which quietly made the guard one-way:
/// the device that *started* a sitting never recorded that the account knew,
/// so when the other device stopped it, the empty server read as "not
/// published yet" and the starting device kept counting — clock running,
/// lock-screen notification up, over a sitting already logged and already
/// pulled back onto that very device (found with two emulators, 15 Aug 2026).
/// The key name is kept for continuity with installs that already have it.
const activeSessionMirroredKey = 'active_session_mirrored_id';

/// Set to the session id of a sitting that arrived from another device.
///
/// Distinct from [activeSessionMirroredKey], which reads as "the account knows
/// about this sitting" — it is set both by adopting one and by successfully
/// publishing our own, so it cannot answer *whose* sitting this is. That
/// question only started mattering when two sittings could collide and the
/// older one had to win: the loser is logged rather than dropped, and logging
/// a sitting that belongs to another device would write the duplicate row this
/// whole design exists to avoid — that device logs it itself.
const activeSessionAdoptedKey = 'active_session_adopted_id';

/// The id of a sitting this device has stopped and logged, but has not yet
/// managed to take off the account.
///
/// Stopping is a local fact the moment it happens; publishing it is a network
/// call that can simply fail — offline, or from a background isolate that
/// auto-stopped the sitting and never had an API client to hand. Until this
/// device says otherwise, the server still has the row, and the pull below
/// reads a row it doesn't recognise as "a sitting is running elsewhere" and
/// adopts it: a sitting the reader stopped came back to life on the next
/// foreground, clock running from the original start, lock-screen notification
/// and all — and stopping it again logged it twice. This key is the memory the
/// pull needs to tell "still running over there" from "already over here",
/// and the note-to-self that makes the delete retry until it lands.
const activeSessionPendingStopKey = 'active_session_pending_stop';

/// Drop the local sitting *without* logging it — the other device already did
/// (or is about to). Deliberately separate from [stopAndLogActiveSession]:
/// logging here is exactly the duplicate this feature has to avoid.
Future<void> clearLocalActiveSession(AppDatabase db) async {
  await db.keyValuesDao.deleteValue(activeSessionEntryKey);
  await db.keyValuesDao.deleteValue(activeSessionStartedKey);
  await db.keyValuesDao.deleteValue(activeSessionPageStartKey);
  await db.keyValuesDao.deleteValue(activeSessionIdKey);
  await db.keyValuesDao.deleteValue(activeSessionConfirmedKey);
  await db.keyValuesDao.deleteValue(activeSessionMirroredKey);
  await db.keyValuesDao.deleteValue(activeSessionAdoptedKey);
}

/// Default wait before a running sitting gets its "still reading?" check-in
/// (2 hours — raised from 60 minutes, owner decision 26 Aug 2026). Per-reader:
/// Profile's Reading check-in setting stores an override in key_values
/// ([readingCheckInDelayKey]), and every mechanism — the notification
/// scheduler, the in-app tick, the background enforcement task — reads it
/// through [readingCheckInDelayOf], so all three keep agreeing on one answer.
const defaultReadingCheckInDelay = Duration(minutes: 120);

/// The intervals the Profile sheet offers, in minutes. Deliberately no "off":
/// the check-in is what keeps a forgotten timer from logging a nine-hour
/// sitting, and a safety net you can switch off isn't one.
const readingCheckInDelayChoicesMinutes = [30, 60, 120, 180, 240];

/// Device-local, like the reading goal and theme — the running timer is
/// device-local by design (see ActiveSession), so its policy is too.
const readingCheckInDelayKey = 'reading_checkin_delay_minutes';

/// If the check-in goes unanswered this much longer, the session is
/// auto-stopped. Fixed, not a preference — it's the safety net's spring, and
/// the setting moves only the check-in.
const readingCheckInGrace = Duration(minutes: 30);

/// The reader's chosen check-in delay, defaulting when unset — and when the
/// stored value isn't one of the offered choices, because a corrupt or
/// future-version value silently becoming "never check in" is exactly the
/// failure the fallback exists to prevent.
Future<Duration> readingCheckInDelayOf(AppDatabase db) async {
  final raw = await db.keyValuesDao.getValue(readingCheckInDelayKey);
  final minutes = raw == null ? null : int.tryParse(raw);
  if (minutes == null || !readingCheckInDelayChoicesMinutes.contains(minutes)) {
    return defaultReadingCheckInDelay;
  }
  return Duration(minutes: minutes);
}

/// The Profile row's live value. Writers (the picker sheet) invalidate this
/// after setValue; nothing else mutates the key.
final readingCheckInDelayProvider = FutureProvider.autoDispose<Duration>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return readingCheckInDelayOf(db);
});

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

/// The instant a running sitting becomes overdue and may be auto-stopped:
/// [checkInDelay] + [readingCheckInGrace] after it started, or after the
/// reader last said they were still reading — whichever is later. Pure so
/// every mechanism (the in-app tick, the workmanager task) can agree on one
/// answer; [checkInDelay] is required so no caller can silently fall back to
/// a default the reader has changed — fetch it with [readingCheckInDelayOf].
DateTime readingSessionDeadline({
  required DateTime startedAt,
  DateTime? confirmedAt,
  required Duration checkInDelay,
}) {
  final base =
      (confirmedAt != null && confirmedAt.isAfter(startedAt)) ? confirmedAt : startedAt;
  return base.add(checkInDelay + readingCheckInGrace);
}

bool readingSessionOverdue({
  required DateTime startedAt,
  DateTime? confirmedAt,
  required DateTime now,
  required Duration checkInDelay,
}) =>
    !now.isBefore(readingSessionDeadline(
      startedAt: startedAt,
      confirmedAt: confirmedAt,
      checkInDelay: checkInDelay,
    ));

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
  bool autoStopped = false,
}) async {
  final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
  final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
  final startedAt = startedRaw == null ? null : DateTime.tryParse(startedRaw);
  if (entryId == null || startedAt == null) {
    // Nothing to log — but something may still be *showing*. Every one of
    // these early exits means "the sitting is already gone from storage", and
    // the surface that outlives it is precisely the lock-screen clock: a
    // second stop arriving after a background isolate already logged the
    // sitting used to return here in silence, leaving the notification
    // counting a sitting that had ended. Ending it is idempotent and cheap.
    await _endLiveSurface();
    return null;
  }
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
    autoStopped: autoStopped,
  );

  // The sitting is over here; the account doesn't know yet. Recorded before
  // anything that can fail so the note survives a stop that happens with no
  // network at all — see [activeSessionPendingStopKey].
  await db.keyValuesDao.setValue(activeSessionPendingStopKey, sessionId);
  await db.keyValuesDao.deleteValue(activeSessionEntryKey);
  await db.keyValuesDao.deleteValue(activeSessionStartedKey);
  await db.keyValuesDao.deleteValue(activeSessionPageStartKey);
  await db.keyValuesDao.deleteValue(activeSessionIdKey);
  await db.keyValuesDao.deleteValue(activeSessionConfirmedKey);
  // Cleared with the rest of them. Left behind, it told a later pull that a
  // *new* sitting from another device was one this one had already adopted.
  await db.keyValuesDao.deleteValue(activeSessionMirroredKey);
  await db.keyValuesDao.deleteValue(activeSessionAdoptedKey);

  // Every stop path — manual, quick-stop, "No", or auto-stop — goes through
  // here, so this is the one place that needs to cancel the check-in
  // notification and the enforcement task, instead of every call site
  // remembering to. Best-effort: a plugin channel that isn't ready (a
  // notification-less platform, a widget test with no platform channels
  // mocked) must never stop the session from being logged correctly.
  //
  // **Three separate try blocks, not one.** They were one, and "best-effort"
  // then meant "the first of these that throws cancels the other two" — with
  // the lock-screen clock last in the queue, so it was the one that stayed on
  // screen counting a sitting the reader had just stopped. Independent
  // cleanups get independent failures.
  try {
    await NotificationService(FlutterLocalNotificationsPlugin())
        .cancel(readingCheckInNotificationId(entryId));
  } catch (_) {}
  try {
    await Workmanager().cancelByUniqueName(readingEnforcementTaskName(entryId));
  } catch (_) {}
  await _endLiveSurface();

  return LoggedSession(
    sessionId: sessionId,
    libraryEntryId: entryId,
    durationSeconds: durationSeconds,
    pageStart: pageStart,
  );
}

/// The sitting currently running on this device, read straight from storage.
///
/// From `key_values`, never from [activeSessionProvider]: the callers that
/// need this are reconciling with the account, and may be running before any
/// Notifier has hydrated (or in a background isolate that has none at all).
/// The same reason [stopAndLogActiveSession] reads from here.
Future<ActiveSession?> readLocalActiveSession(AppDatabase db) async {
  final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
  final id = await db.keyValuesDao.getValue(activeSessionIdKey);
  final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
  final startedAt = startedRaw == null ? null : DateTime.tryParse(startedRaw);
  if (entryId == null || id == null || startedAt == null) return null;
  final pageStartRaw = await db.keyValuesDao.getValue(activeSessionPageStartKey);
  return ActiveSession(
    libraryEntryId: entryId,
    startedAt: startedAt,
    id: id,
    pageStart: int.tryParse(pageStartRaw ?? ''),
  );
}

/// Takes the lock-screen clock down: the iOS Live Activity, or the Android
/// ongoing notification. Idempotent and silent — safe to call when nothing is
/// showing, which is most of the time.
///
/// On iOS a background isolate has no method channel to reach ActivityKit
/// with, so this is a no-op there and `ActiveSessionController.reconcile`
/// clears the leftover activity the next time the app is foregrounded.
Future<void> _endLiveSurface() async {
  try {
    await ReadingLiveActivity().end();
  } catch (_) {}
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

  /// The in-flight (or already-completed) `_hydrate()` call from [build] —
  /// awaited at the top of [start] and [stop] so a tap that lands before a
  /// cold start's async KeyValues reads have landed doesn't read `state` as
  /// null and silently no-op. This is exactly the scenario a Live Activity
  /// tap forces (a fresh Notifier build on process relaunch): the tap that
  /// opens the timer screen and the tap on its Stop button can both arrive
  /// before three sequential `await`s finish, and without this the button
  /// simply did nothing — no error, nothing to retry (owner report, 19 Aug
  /// 2026, mid-flight).
  Future<void>? _hydration;

  /// Resolves once this controller has read storage and [state] means
  /// something. Before it completes, `state == null` is "we haven't looked
  /// yet", not "nothing is running" — a distinction any screen that acts on
  /// an empty session has to make, since a cold start into the timer route
  /// (tapping the lock-screen clock) builds this Notifier and the screen in
  /// the same frame.
  Future<void> get hydrated => _hydration ?? Future<void>.value();

  @override
  ActiveSession? build() {
    _hydration = _hydrate();
    return null;
  }

  /// Re-read the sitting from local storage. Public because adopting one from
  /// another device writes those rows and then needs this to catch up.
  ///
  /// Recorded as the current [hydrated] future too, so a caller waiting for
  /// "has storage answered yet" waits for the *latest* read rather than only
  /// the one `build()` started.
  Future<void> hydrate() => _hydration = _hydrate();

  Future<void> _hydrate() async {
    final db = ref.read(appDatabaseProvider);
    final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
    final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
    final startedAt = startedRaw == null ? null : DateTime.tryParse(startedRaw);
    if (entryId == null || startedAt == null) {
      // Nothing is running — and this is the only reconciliation a *cold
      // start* gets. [reconcile] is wired to `didChangeAppLifecycleState`,
      // which is never called for the state the app launches in, so on a cold
      // start nothing else ever takes down a lock-screen clock left behind by
      // a stop that couldn't reach the channel (an iOS background isolate's
      // auto-stop, a plugin hiccup, the app being killed mid-stop). It
      // survived every relaunch, and tapping it opened the timer on a sitting
      // that no longer existed — a sweeping hand over a clock frozen at 0:00
      // (owner report, 29 Aug 2026). Storage is the truth in both directions,
      // so read it that way here.
      state = null;
      await _endLiveSurface();
      return;
    }
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
    // A session restored after a kill+reopen still has its clock running, so
    // the lock-screen surface has to come back with it.
    await _showLive(entryId, startedAt);
  }

  /// Puts the running sitting back on the lock screen, or clears a stale one.
  ///
  /// Both halves matter. A sitting stopped from a background isolate (the
  /// check-in's "No, stop it", the workmanager auto-stop) writes straight to
  /// the database and never reaches the live-activity channel — without this,
  /// a finished sitting would keep counting on the lock screen until the
  /// reader started another one. Called on hydrate and on every foreground
  /// resume, both of which are cheap and idempotent.
  Future<void> reconcile() async {
    final db = ref.read(appDatabaseProvider);
    final entryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
    final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
    final startedAt = startedRaw == null ? null : DateTime.tryParse(startedRaw);
    if (entryId == null || startedAt == null) {
      await ReadingLiveActivity().end();
      return;
    }
    await _showLive(entryId, startedAt);
  }

  /// The book's title/author/pages come from a direct query rather than a
  /// stream provider: this runs at the moment a sitting starts, and an
  /// autoDispose stream that hasn't emitted yet would hand back nothing (the
  /// 19 Jul 2026 lesson — don't trust "there's usually a value there").
  Future<void> _showLive(String libraryEntryId, DateTime startedAt) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.libraryEntriesDao.getById(libraryEntryId);
      if (entry == null) return;
      final book = await db.cachedBooksDao.getByEditionId(entry.editionId);
      final confirmedRaw = await db.keyValuesDao.getValue(activeSessionConfirmedKey);
      await ReadingLiveActivity().start(
        libraryEntryId: libraryEntryId,
        title: book?.title ?? '',
        author: book?.authorNames,
        startedAt: startedAt,
        currentPage: entry.currentPage,
        pageCount: book?.pageCount,
        staleAt: readingSessionDeadline(
          startedAt: startedAt,
          confirmedAt: confirmedRaw == null ? null : DateTime.tryParse(confirmedRaw),
          checkInDelay: await readingCheckInDelayOf(db),
        ),
      );
    } catch (_) {
      // Decoration, never the sitting itself.
    }
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
    await _hydration;
    if (state?.libraryEntryId == libraryEntryId) return;
    if (state != null) await stop();

    final startedAt = DateTime.now();
    final sessionId = const Uuid().v4();
    final db = ref.read(appDatabaseProvider);
    await db.keyValuesDao.setValue(activeSessionEntryKey, libraryEntryId);
    await db.keyValuesDao.setValue(activeSessionStartedKey, startedAt.toIso8601String());
    await db.keyValuesDao.setValue(activeSessionIdKey, sessionId);
    await db.keyValuesDao.deleteValue(activeSessionConfirmedKey);
    // Ours by construction — and the previous sitting's flag must not linger.
    await db.keyValuesDao.deleteValue(activeSessionAdoptedKey);
    if (pageStart != null) {
      await db.keyValuesDao.setValue(activeSessionPageStartKey, '$pageStart');
    }
    state = ActiveSession(
      libraryEntryId: libraryEntryId,
      startedAt: startedAt,
      id: sessionId,
      pageStart: pageStart,
    );
    await _showLive(libraryEntryId, startedAt);
    // Let the reader's other devices in on it. Best-effort by construction —
    // see ActiveSessionSync.
    await ref.read(activeSessionSyncProvider).publishStart(state!);
  }

  /// Stops the running session (if any), logs it via the repository, and
  /// clears local state. Returns what got logged for the wax-seal screen —
  /// null if nothing was running. [autoStopped] marks a stop the safety net
  /// triggered rather than the reader tapping Stop — see
  /// [checkReadingTimerSafetyNet], the only caller that passes true.
  Future<LoggedSession?> stop({bool autoStopped = false}) async {
    await _hydration;
    if (state == null) return null;
    _stopping = true;
    // Cleared synchronously, before the first await. The clock stops when the
    // reader says it stops — everything after this is filing. Waiting until
    // the writes came back meant every surface that only exists while a
    // sitting is live (the mini-bar, Home's live card) stayed on screen for
    // the length of a database round trip *plus* whatever the plugin channels
    // took, and each new step added to the stop path pushed it out further.
    // Nothing below reads it: the sitting is read from key_values, which is
    // the point of storing it there.
    state = null;
    try {
      final db = ref.read(appDatabaseProvider);
      // Resolving identity can fail (signed out from under a running sitting),
      // and an exception here used to escape the Stop button: the sitting kept
      // running, and the lock-screen clock kept counting it. There is nowhere
      // correct to file a sitting for nobody, so drop it — but take the clock
      // down with it rather than leaving a surface with nothing behind it.
      final SessionContext session;
      try {
        session = await ref.read(sessionContextProvider.future);
      } catch (_) {
        await _endLiveSurface();
        return null;
      }
      final LoggedSession? logged;
      try {
        logged = await stopAndLogActiveSession(
          db,
          session,
          onMutation: ref.read(syncTriggerProvider),
          autoStopped: autoStopped,
        );
      } catch (_) {
        // The write failed, so the sitting is still running in storage — and
        // storage is the truth. Put in-memory state back in step with it
        // rather than leaving a live sitting no surface will show.
        await _hydrate();
        return null;
      }
      // Take the sitting off the account too, so the other device's ongoing
      // notification comes down instead of counting a sitting that ended.
      //
      // Deliberately *not* awaited. This is a network round trip on the path
      // between "the reader tapped Stop" and "the page question appears", and
      // on a network that has gone quiet without saying so it is measured in
      // tens of seconds. The stop is already complete and durable at this
      // point; publishing it is bookkeeping, it retries itself from the
      // pending-stop note, and nothing on screen is waiting for its answer.
      unawaited(ref.read(activeSessionSyncProvider).publishStop());
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

  final confirmedRaw = await db.keyValuesDao.getValue(activeSessionConfirmedKey);
  final overdue = readingSessionOverdue(
    startedAt: active.startedAt,
    confirmedAt: confirmedRaw == null ? null : DateTime.tryParse(confirmedRaw),
    now: DateTime.now(),
    checkInDelay: await readingCheckInDelayOf(db),
  );
  if (!overdue) return null;
  return notifier.stop(autoStopped: true);
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
