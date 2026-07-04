import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_providers.dart';

/// Triggers an immediate drain on regaining connectivity, on top of the
/// 15-minute workmanager cadence — watched once from the app root.
final connectivitySyncProvider = Provider<void>((ref) {
  final sub = Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      ref.read(syncTriggerProvider)();
    }
  });
  ref.onDispose(sub.cancel);
});
