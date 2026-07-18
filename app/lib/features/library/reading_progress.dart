import '../../data/api/api_client.dart';
import '../../data/db/database.dart';

/// Save a book's total page count, supplied by a reader while logging progress
/// on a book the catalog had no page count for. The total belongs to the shared
/// Edition, so it goes two places: the device-local mirror (so progress becomes
/// a percentage immediately, and keeps working offline) and the catalog itself
/// (so it syncs to the cloud and to the reader's other devices). The network
/// call is best-effort — the mirror is what the shelf reads.
///
/// One home for this so every entry point that asks for the total (the reading
/// timer, the quick-stop dialog, the manual-log sheet, the progress editor)
/// writes it the same way — they used to each roll their own, and some dropped
/// it (owner report, 19 Jul 2026: a total typed while logging never reached the
/// book or the cloud).
Future<void> saveBookTotalPages(
  AppDatabase db,
  ApiClient api,
  String editionId,
  int total,
) async {
  if (total <= 0) return;
  await db.cachedBooksDao.updatePageCount(editionId, total);
  try {
    await api.updateEdition(editionId, {'page_count': total});
  } catch (_) {
    // Offline or rejected — the local mirror still has it, and the reader can
    // set it again from the book page to push it to the catalog.
  }
}
