import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Storage key for this install's persisted device id (see below).
const _kDeviceIdKey = 'device_id';

/// Generated once per install — the conflict signal for Kitabi's
/// single-user-multiple-devices case (see sync_op.py's docstring on the
/// API side for why this replaces rupee-diary's cross-user check).
Future<String> getOrCreateDeviceId(AppDatabase db) async {
  final existing = await db.keyValuesDao.getValue(_kDeviceIdKey);
  if (existing != null) return existing;
  final id = Uuid().v4();
  await db.keyValuesDao.setValue(_kDeviceIdKey, id);
  return id;
}
