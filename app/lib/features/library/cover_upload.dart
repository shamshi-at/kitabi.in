import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/image_crop.dart';
import '../../core/photo_rotate.dart';
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
  return _uploadCoverBytes(ref, editionId: editionId, bytes: bytes, back: back);
}

/// Straighten a cover already on the book — the same free-angle step the
/// add form offers. Rotation lived only on the add/edit form at first, which
/// left the book page (where a reader actually notices a crooked cover)
/// unable to fix it: exactly the "one entry point, not all of them" trap
/// CLAUDE.md already records. Returns null if the reader backs out.
Future<String?> rotateAndUploadCover(
  WidgetRef ref,
  BuildContext context, {
  required String editionId,
  required String currentUrl,
  bool back = false,
}) async {
  final response = await Dio().get<List<int>>(
    currentUrl,
    options: Options(responseType: ResponseType.bytes),
  );
  final data = response.data;
  if (data == null || !context.mounted) return null;

  final rotated = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => RotatePhotoScreen(bytes: Uint8List.fromList(data)),
    ),
  );
  if (rotated == null) return null;

  // Straightening usually wants a re-frame, so go on to the cropper; if that's
  // cancelled the rotation alone still stands.
  final tmp = File('${Directory.systemTemp.path}/cover_rotate_$editionId.png');
  await tmp.writeAsBytes(rotated, flush: true);
  try {
    final cropped = await cropPickedImage(tmp.path, CropRatio.cover);
    return _uploadCoverBytes(
      ref,
      editionId: editionId,
      bytes: cropped ?? rotated,
      back: back,
    );
  } finally {
    if (await tmp.exists()) await tmp.delete();
  }
}

Future<String?> _uploadCoverBytes(
  WidgetRef ref, {
  required String editionId,
  required Uint8List bytes,
  required bool back,
}) async {

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
