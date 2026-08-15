import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/library/providers/active_session_sync.dart';
import 'sync_providers.dart';

/// Triggers an immediate drain on regaining connectivity, on top of the
/// 15-minute workmanager cadence — watched once from the app root.
final connectivitySyncProvider = Provider<void>((ref) {
  final sub = Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      ref.read(syncTriggerProvider)();
      // The running sitting is not in the sync queue — it is a separate row on
      // the account, reconciled by its own call. So draining the queue alone
      // left a reader who started reading offline in a split state on coming
      // back: the book's status arrived on their other device, the timer never
      // did (owner report, 15 Aug 2026). Reconciling only on foreground-resume
      // and on push missed this entirely, because regaining signal with the app
      // already open is neither.
      unawaited(ref.read(activeSessionSyncProvider).pullAndApply());
    }
  });
  ref.onDispose(sub.cancel);
});
