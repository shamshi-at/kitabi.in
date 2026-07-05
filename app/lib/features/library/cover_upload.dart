import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/api/api_client.dart';
import '../../data/sync/sync_providers.dart';

/// The Supabase Storage bucket that holds user-uploaded covers. Must be created
/// (public read) with an insert policy for authenticated users — owner setup,
/// like the rest of the Supabase project (see STATUS.md open decisions).
const _coverBucket = 'covers';

/// Pick a photo, upload it to Storage, point the edition's `cover_url` at it,
/// and refresh the local cache. Returns the new URL, or null if cancelled.
/// Throws on upload/patch failure (caller shows a message).
Future<String?> pickAndUploadCover(WidgetRef ref, {required String editionId}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1200,
    imageQuality: 85,
  );
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final objectPath = '$editionId.jpg';
  final storage = Supabase.instance.client.storage.from(_coverBucket);
  await storage.uploadBinary(
    objectPath,
    bytes,
    fileOptions: FileOptions(upsert: true, contentType: 'image/jpeg'),
  );

  // Cache-bust so a re-upload of the same edition shows immediately.
  final base = storage.getPublicUrl(objectPath);
  final coverUrl = '$base?v=${bytes.length}';

  await ref.read(apiClientProvider).updateEdition(editionId, {'cover_url': coverUrl});
  await ref.read(appDatabaseProvider).cachedBooksDao.updateCoverUrl(editionId, coverUrl);
  return coverUrl;
}
