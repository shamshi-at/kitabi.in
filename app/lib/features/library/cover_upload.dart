import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/image_crop.dart';
import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';

/// The Supabase Storage bucket that holds user-uploaded covers. Must be created
/// (public read) with an insert policy for authenticated users — owner setup,
/// like the rest of the Supabase project (see STATUS.md open decisions).
const _coverBucket = 'covers';

/// Capture/pick a photo from [source], crop it to a 2:3 book-cover portrait,
/// upload it to Storage, point the edition's front (`cover_url`) or back
/// (`back_cover_url`) at it, and refresh the local cache. Returns the new URL,
/// or null if the capture or crop is cancelled. Throws on upload/patch failure
/// (caller shows a message).
Future<String?> pickAndUploadCover(
  WidgetRef ref, {
  required String editionId,
  required ImageSource source,
  bool back = false,
}) async {
  final bytes = await pickAndCropImage(source: source, ratio: CropRatio.cover);
  if (bytes == null) return null;

  // Stable per-edition path so a re-upload overwrites; `-back` keeps the two
  // sides distinct.
  final objectPath = '$editionId${back ? '-back' : ''}.jpg';
  final storage = Supabase.instance.client.storage.from(_coverBucket);
  await storage.uploadBinary(
    objectPath,
    bytes,
    fileOptions: FileOptions(upsert: true, contentType: 'image/jpeg'),
  );

  // Cache-bust so a re-upload of the same edition shows immediately.
  final base = storage.getPublicUrl(objectPath);
  final coverUrl = '$base?v=${bytes.length}';

  final field = back ? 'back_cover_url' : 'cover_url';
  await ref.read(apiClientProvider).updateEdition(editionId, {field: coverUrl});
  // Only the front cover feeds the offline grid cache; the back shows only on
  // the book page (fetched fresh), so there's nothing to cache for it.
  if (!back) {
    await ref.read(appDatabaseProvider).cachedBooksDao.updateCoverUrl(editionId, coverUrl);
  }
  return coverUrl;
}
