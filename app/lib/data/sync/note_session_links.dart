import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

const _uuid = Uuid();

/// Notes waiting to be told which sitting they belong to, as
/// `{noteId: sessionId}` in `key_values`.
///
/// A note written while the clock runs cannot name its sitting on the wire —
/// the `reading_sessions` row doesn't exist until the sitting stops, and the
/// server refuses a reference it can't resolve (see
/// `ReadingNotesRepository.add`). The link therefore has to be sent later, and
/// *something* has to remember to send it. This is that memory, and it is
/// deliberately kept outside the note row: the note's own `session_id` is
/// local knowledge the server doesn't share, so a pull can arrive carrying a
/// null for it at any moment.
const pendingNoteLinksKey = 'pending_note_session_links';

/// Record that [noteId] belongs to [sessionId], to be published once the
/// sitting is a row the server will accept.
Future<void> rememberNoteSessionLink(
  AppDatabase db, {
  required String noteId,
  required String sessionId,
}) async {
  final links = await _read(db);
  links[noteId] = sessionId;
  await db.keyValuesDao.setValue(pendingNoteLinksKey, jsonEncode(links));
}

/// Publish every remembered link whose sitting now exists locally, and forget
/// it. A cheap no-op when there is nothing waiting.
///
/// **Which device stops the sitting is not knowable in advance, and that is
/// the whole reason this exists.** The obvious place to link a sitting's notes
/// is the moment it is logged — but the reader's *other* device can be the one
/// that stops it (that is the point of the shared timer), and it runs the stop
/// against its own database, where the note arrived with no link at all. So
/// the note stayed attached on the phone that wrote it and detached
/// everywhere else, permanently (found with two emulators, 15 Aug 2026).
/// Linking belongs to the device that *wrote* the note, whenever the sitting
/// reaches it — which a pull guarantees it eventually will.
///
/// Runs after every sync pull, and directly after a sitting is logged so the
/// same-device case needs no round trip. Returns how many links were sent.
Future<int> publishPendingNoteLinks(
  AppDatabase db, {
  required String userId,
  required String deviceId,
}) async {
  final links = await _read(db);
  if (links.isEmpty) return 0;

  var sent = 0;
  final remaining = <String, String>{};
  for (final entry in links.entries) {
    final note = await db.readingNotesDao.getById(entry.key);
    if (note == null) continue; // gone — nothing to link, nothing to keep
    if (await db.readingSessionsDao.getById(entry.value) == null) {
      remaining[entry.key] = entry.value; // sitting hasn't reached us yet
      continue;
    }
    // The pull may have cleared the local link on its way past; the note is
    // this sitting's either way, so put it back as we publish it.
    if (note.sessionId != entry.value) {
      await db.readingNotesDao.patch(
        entry.key,
        ReadingNotesCompanion(sessionId: Value(entry.value)),
      );
    }
    await db.syncQueueDao.enqueue(
      SyncQueueCompanion.insert(
        opId: _uuid.v4(),
        userId: Value(userId),
        deviceId: deviceId,
        entity: 'reading_notes',
        entityId: entry.key,
        opType: 'update',
        payload: jsonEncode({'session_id': entry.value}),
      ),
    );
    sent++;
  }

  if (remaining.isEmpty) {
    await db.keyValuesDao.deleteValue(pendingNoteLinksKey);
  } else {
    await db.keyValuesDao.setValue(pendingNoteLinksKey, jsonEncode(remaining));
  }
  return sent;
}

Future<Map<String, String>> _read(AppDatabase db) async {
  final raw = await db.keyValuesDao.getValue(pendingNoteLinksKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    return (jsonDecode(raw) as Map).cast<String, String>();
  } catch (_) {
    return {}; // corrupt — better to lose a link than to wedge every sync
  }
}
