import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/auth/supabase_auth_service.dart';
import '../../core/notifications/reading_timer_notifications.dart';
import '../../features/library/providers/reading_timer_providers.dart';
import '../api/api_client.dart';
import '../db/database.dart';
import 'sync_engine.dart';

/// workmanager task identifiers for the periodic background sync drain.
const _kTaskName = 'kitabi.backgroundSync';
const _kTaskTag = 'sync';

/// Prefix of the per-entry one-off task names registered by
/// `armReadingTimerSafetyNet` (`readingEnforcementTaskName`) — a reading
/// timer left running past its check-in's grace period gets silently
/// auto-stopped here. Workmanager only supports one registered dispatcher,
/// so this branches on task name alongside the periodic sync drain.
const _kReadingAutoStopPrefix = 'kitabi.readingTimerAutoStop.';

/// Runs in a background isolate — re-inits what it needs, never crashes the
/// OS-scheduled task (ported from rupee-diary's callbackDispatcher).
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == _kTaskName) {
        await _runPeriodicSync();
      } else if (taskName.startsWith(_kReadingAutoStopPrefix)) {
        await _runReadingTimerEnforcement(inputData);
      }
    } catch (_) {
      // Never let a background task crash the OS scheduler.
    }
    return true;
  });
}

Future<void> _runPeriodicSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!supabaseConfigured) return;
  await initSupabase();

  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) return; // signed out — nothing to sync

  final db = AppDatabase();
  final api = ApiClient();
  final engine = SyncEngine(db, api);
  await engine.syncNow(session.user.id);
}

/// Auto-stop enforcement: fires 90 minutes after a session started (60min
/// check-in + 30min grace) unless re-armed by a "Yes, still reading" tap or
/// cancelled by the session stopping some other way in the meantime — in
/// which case [entryId] here no longer matches the active session and this
/// is a no-op.
Future<void> _runReadingTimerEnforcement(Map<String, dynamic>? inputData) async {
  final entryId = inputData?['libraryEntryId'] as String?;
  if (entryId == null) return;

  WidgetsFlutterBinding.ensureInitialized();
  if (!supabaseConfigured) return;
  await initSupabase();
  final userId = Supabase.instance.client.auth.currentSession?.user.id;
  if (userId == null) return;

  final db = AppDatabase();
  final currentEntryId = await db.keyValuesDao.getValue(activeSessionEntryKey);
  if (currentEntryId != entryId) return;

  await stopReadingSessionAndNotify(db: db, userId: userId, libraryEntryId: entryId);
}

/// 15-minute periodic drain, network-connected only — same cadence as
/// rupee-diary.
void registerBackgroundSync() {
  Workmanager().registerPeriodicTask(
    _kTaskTag,
    _kTaskName,
    frequency: Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
