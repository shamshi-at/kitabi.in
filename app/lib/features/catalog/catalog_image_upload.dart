import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/image_crop.dart';

/// Reuses the existing public `covers` bucket (see cover_upload.dart / STATUS.md)
/// for author portraits and publisher logos too — the Storage policy is
/// bucket-scoped (`bucket_id = 'covers'`), so a `authors/…` or `publishers/…`
/// prefix inside it needs no extra owner setup.
const _bucket = 'covers';
const _uuid = Uuid();

/// Capture/pick a photo from [source], crop it to [ratio], upload it to Storage
/// under `<folder>/<uuid>.jpg`, and return its public URL. The generic building
/// block behind every "new catalog image" flow (author portraits, publisher
/// logos, and covers created on the add-book form, which have no edition id yet
/// to key a stable path on). Returns null if the user cancels the capture or the
/// crop; throws on upload failure (caller shows a message).
Future<String?> pickCropUploadImage({
  required ImageSource source,
  required String folder,
  required CropRatio ratio,
}) async {
  final bytes = await pickAndCropImage(source: source, ratio: ratio);
  if (bytes == null) return null;
  return _uploadJpeg(bytes, folder);
}

/// Author portraits / publisher logos — square crop.
Future<String?> pickAndUploadCatalogImage({
  required String folder,
  required ImageSource source,
}) =>
    pickCropUploadImage(source: source, folder: folder, ratio: CropRatio.square);

Future<String> _uploadJpeg(Uint8List bytes, String folder) async {
  final objectPath = '$folder/${_uuid.v4()}.jpg';
  final storage = Supabase.instance.client.storage.from(_bucket);
  await storage.uploadBinary(
    objectPath,
    bytes,
    fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
  );
  return storage.getPublicUrl(objectPath);
}
