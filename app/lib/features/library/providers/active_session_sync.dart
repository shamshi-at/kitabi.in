import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/sync/sync_providers.dart';
import 'reading_timer_providers.dart';

/// The running timer, shared across one reader's devices (owner request,
/// 14 Aug 2026: same account on two phones — start on one, see and stop it on
/// the other).
///
/// **The whole trick is that this writes the same local rows the timer already
/// uses.** A sitting lives in `key_values` (`active_session_*`), and every
/// surface — the mini-bar, the timer face, the stop-and-log path, the safety
/// net, the Live Activity — reads it from there. So a second device does not
/// need a parallel "remote session" concept: mirror the server's row into
/// those keys and the device simply *has* the sitting, with no new code paths
/// to keep in step. Stopping works for free, and writes the finished
/// `reading_sessions` row under the **same session id**, which is why the two
/// devices can never produce two rows for one sitting.
///
/// Everything here is best-effort. A timer that refused to start because
/// another phone was unreachable would be a far worse bug than a second device
/// that finds out a few seconds late — it re-reads on every foreground anyway.
class ActiveSessionSync {
  ActiveSessionSync(this._ref);

  final Ref _ref;

  Future<String?> _deviceId() async {
    try {
      return (await _ref.read(sessionContextProvider.future)).deviceId;
    } catch (_) {
      return null;
    }
  }

  /// Tell the account a sitting is running. Idempotent — also used to refresh
  /// `confirmed_at` after a "yes, still reading", so the other device computes
  /// the same deadline instead of stopping a live sitting out from under it.
  Future<void> publishStart(ActiveSession session, {DateTime? confirmedAt}) async {
    try {
      final entry = await _ref.read(appDatabaseProvider).libraryEntriesDao.getById(
            session.libraryEntryId,
          );
      if (entry == null) return;
      await _ref.read(apiClientProvider).putActiveSession({
        'session_id': session.id,
        'library_entry_id': session.libraryEntryId,
        'started_at': session.startedAt.toUtc().toIso8601String(),
        'page_start': session.pageStart,
        'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
        'device_id': await _deviceId(),
      });
      // The account has it now — so a later pull finding *nothing* running
      // means the other device stopped it, not that we never published. Only
      // recorded on success: an offline start must stay unpublished, because
      // that is precisely the sitting the pull must never throw away.
      await _ref
          .read(appDatabaseProvider)
          .keyValuesDao
          .setValue(activeSessionMirroredKey, session.id);
    } catch (_) {
      // Offline, or the server is having a moment. The sitting is already
      // running locally and the finished row still syncs the usual way.
    }
  }

  /// The sitting ended here. The other device takes its notification down.
  ///
  /// Clears the pending-stop note on success. Until it succeeds the note
  /// stands, and [pullAndApply] both refuses to re-adopt the finished sitting
  /// and tries this again — which is what makes a stop performed in airplane
  /// mode reach the account on landing instead of being undone by it.
  Future<void> publishStop() async {
    final db = _ref.read(appDatabaseProvider);
    try {
      await _ref.read(apiClientProvider).deleteActiveSession(deviceId: await _deviceId());
      await db.keyValuesDao.deleteValue(activeSessionPendingStopKey);
    } catch (_) {
      // Offline, or the server is having a moment. The note keeps the retry.
    }
  }

  /// Make this device agree with the account: adopt a sitting started
  /// elsewhere, or drop one that was stopped elsewhere.
  ///
  /// Returns true when something changed, so callers can refresh.
  Future<bool> pullAndApply() async {
    final db = _ref.read(appDatabaseProvider);
    // Read *before* the network call, not after. A stop fires its DELETE
    // unawaited and clears this note the moment it lands, so a GET issued
    // just before the DELETE and answered just after it would come back
    // holding the stopped sitting with no note left to recognise it by — and
    // the sitting was adopted straight back onto the device that had already
    // logged it, lock-screen clock and all. The note has to be as old as the
    // answer it is being compared against.
    final pendingStopId = await db.keyValuesDao.getValue(activeSessionPendingStopKey);

    final Map<String, dynamic>? remote;
    try {
      remote = await _ref.read(apiClientProvider).getActiveSession();
    } catch (_) {
      return false; // offline: leave local state alone, it is still the truth here
    }

    final localId = await db.keyValuesDao.getValue(activeSessionIdKey);

    // The server is still showing a sitting this device already stopped and
    // logged — the delete never landed (stopped offline, or auto-stopped by a
    // background isolate that had no way to make the call). Adopting it here
    // is how a finished sitting came back to life: the clock restarted from
    // the original start time, the lock-screen notification returned, and
    // stopping it a second time wrote a second row for one sitting. Finish the
    // job instead.
    if (pendingStopId != null) {
      if (remote != null && remote['session_id'] == pendingStopId) {
        await publishStop();
        return false;
      }
      // The account has moved on without us — the row is gone, or it belongs
      // to a newer sitting started somewhere else. Either way there is nothing
      // left to retract, and a note that outlived its subject would block that
      // newer sitting from ever being adopted.
      await db.keyValuesDao.deleteValue(activeSessionPendingStopKey);
    }

    if (remote == null) {
      // Nothing running on the account. Only clear a sitting this device is
      // *mirroring* — never one it started itself and hasn't published yet,
      // which would throw away the reader's own running timer.
      if (localId == null) return false;
      final mine = await db.keyValuesDao.getValue(activeSessionMirroredKey);
      if (mine != localId) {
        // Ours, and the account has never heard of it — the publish at `start`
        // was made with no network and quietly failed. Nothing retried it, so
        // the sitting stayed device-local for good: the reader's other device
        // saw the book turn to "reading" (that rides the sync queue, which
        // does retry) and no timer beside it (owner report, 15 Aug 2026).
        //
        // This is the moment we know the account is reachable *and* has
        // nothing running, so it is exactly the moment to say so. Best-effort
        // as ever; if it fails again the next pull tries again.
        final sitting = await readLocalActiveSession(db);
        if (sitting != null && sitting.id == localId) {
          final confirmedRaw = await db.keyValuesDao.getValue(activeSessionConfirmedKey);
          await publishStart(
            sitting,
            confirmedAt: confirmedRaw == null ? null : DateTime.tryParse(confirmedRaw),
          );
        }
        return false;
      }
      await clearLocalActiveSession(db);
      _ref.read(activeSessionProvider.notifier).clearStaleState();
      await _ref.read(activeSessionProvider.notifier).reconcile();
      return true;
    }

    if (remote['session_id'] == localId) return false; // already in step

    // Two sittings, one account — each device started its own (the reader began
    // on one phone while the other was offline, most likely). **The older start
    // wins** (owner decision, 15 Aug 2026): whichever sitting has been running
    // longer is the real one, and the rule is a pure comparison of start times,
    // so both devices reach the same answer without negotiating.
    //
    // Until now the remote row simply overwrote whatever was here, and a
    // sitting this device started was discarded unlogged — the reader's time
    // gone with it. So the loser is *logged* before it is let go: it is real
    // reading, and the only thing wrong with it is that a longer one exists.
    if (localId != null) {
      final startedRaw = await db.keyValuesDao.getValue(activeSessionStartedKey);
      final localStart = startedRaw == null ? null : DateTime.tryParse(startedRaw);
      final remoteStart = DateTime.tryParse(remote['started_at'] as String);
      final adopted = await db.keyValuesDao.getValue(activeSessionAdoptedKey);
      final startedHere = adopted != localId;

      if (startedHere && localStart != null && remoteStart != null) {
        if (localStart.isBefore(remoteStart)) {
          // Ours is older, so ours is the sitting. Put it back on the account,
          // over the younger one; that device will find it on its next pull,
          // log its own by this same rule, and fall in behind us.
          final sitting = await readLocalActiveSession(db);
          if (sitting != null) {
            final confirmedRaw = await db.keyValuesDao.getValue(activeSessionConfirmedKey);
            await publishStart(
              sitting,
              confirmedAt: confirmedRaw == null ? null : DateTime.tryParse(confirmedRaw),
            );
          }
          return false;
        }
        // Theirs is older. Log ours on the way out rather than dropping it.
        try {
          await stopAndLogActiveSession(
            db,
            await _ref.read(sessionContextProvider.future),
            onMutation: _ref.read(syncTriggerProvider),
          );
        } catch (_) {
          // Nowhere to file it (signed out mid-flight) — adopting still beats
          // leaving this device on a sitting the account has moved past.
        }
      }
    }

    await db.keyValuesDao.setValue(activeSessionEntryKey, remote['library_entry_id'] as String);
    await db.keyValuesDao.setValue(activeSessionIdKey, remote['session_id'] as String);
    await db.keyValuesDao.setValue(activeSessionStartedKey, remote['started_at'] as String);
    // Remember that this sitting arrived from elsewhere: it is what tells a
    // later pull whether a missing server row means "stopped over there" or
    // "we haven't published ours yet".
    await db.keyValuesDao.setValue(activeSessionMirroredKey, remote['session_id'] as String);
    // …and *whose* it is, which the key above can no longer say now that a
    // successful publish sets it too. Only an adopted sitting is another
    // device's to log.
    await db.keyValuesDao.setValue(activeSessionAdoptedKey, remote['session_id'] as String);
    final pageStart = remote['page_start'];
    if (pageStart == null) {
      await db.keyValuesDao.deleteValue(activeSessionPageStartKey);
    } else {
      await db.keyValuesDao.setValue(activeSessionPageStartKey, '$pageStart');
    }
    final confirmed = remote['confirmed_at'] as String?;
    if (confirmed == null) {
      await db.keyValuesDao.deleteValue(activeSessionConfirmedKey);
    } else {
      await db.keyValuesDao.setValue(activeSessionConfirmedKey, confirmed);
    }

    await _ref.read(activeSessionProvider.notifier).hydrate();
    return true;
  }
}

final activeSessionSyncProvider = Provider<ActiveSessionSync>(ActiveSessionSync.new);
