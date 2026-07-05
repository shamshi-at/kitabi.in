import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/auth/supabase_auth_service.dart';
import '../api/api_client.dart';
import '../db/database.dart';
import 'sync_engine.dart';

const _kTaskName = 'kitabi.backgroundSync';
const _kTaskTag = 'sync';

/// Runs in a background isolate — re-inits what it needs, never crashes the
/// OS-scheduled task (ported from rupee-diary's callbackDispatcher).
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    if (taskName != _kTaskName) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (!supabaseConfigured) return true;
      await initSupabase();

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return true; // signed out — nothing to sync

      final db = AppDatabase();
      final api = ApiClient();
      final engine = SyncEngine(db, api);
      await engine.syncNow(session.user.id);
    } catch (_) {
      // Never let a background task crash the OS scheduler.
    }
    return true;
  });
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
