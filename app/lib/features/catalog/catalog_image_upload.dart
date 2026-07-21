import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/image_crop.dart';
import '../../core/photo_rotate.dart';

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

/// Re-open the cropper on an image that's *already* uploaded (its public [url]),
/// letting the user re-crop/rotate/reframe it, then upload the result as a new
/// object and return its URL. Used by "Adjust" on the add-book cover slots, so a
/// captured cover can be reframed without retaking the photo. Downloads to a
/// temp file (the cropper needs a local path), crops, uploads. Returns null if
/// the crop is cancelled; throws if the image can't be fetched or uploaded.
Future<String?> recropUploadImage({
  required String url,
  required String folder,
  required CropRatio ratio,
}) async {
  final response = await Dio().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final data = response.data;
  if (data == null) throw Exception('empty image response');

  final tmp = File('${Directory.systemTemp.path}/recrop_${_uuid.v4()}.jpg');
  await tmp.writeAsBytes(data, flush: true);
  try {
    final bytes = await cropPickedImage(tmp.path, ratio);
    if (bytes == null) return null;
    return _uploadJpeg(bytes, folder);
  } finally {
    if (await tmp.exists()) await tmp.delete();
  }
}

/// Fetch an already-uploaded cover, let the reader twist it to any angle
/// (the native cropper only does 90° steps), then re-crop and re-upload.
/// Returns null if they back out at either step — the existing cover stands.
Future<String?> rotateUploadImage({
  required BuildContext context,
  required String url,
  required String folder,
  required CropRatio ratio,
}) async {
  final response = await Dio().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final data = response.data;
  if (data == null) throw Exception('empty image response');

  if (!context.mounted) return null;
  final rotated = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => RotatePhotoScreen(bytes: Uint8List.fromList(data)),
    ),
  );
  if (rotated == null) return null;

  // Straightening usually wants a re-frame, so hand the rotated bytes straight
  // to the cropper rather than making it a second errand.
  final tmp = File('${Directory.systemTemp.path}/rotate_${_uuid.v4()}.png');
  await tmp.writeAsBytes(rotated, flush: true);
  try {
    final cropped = await cropPickedImage(tmp.path, ratio);
    return _uploadJpeg(cropped ?? rotated, folder);
  } finally {
    if (await tmp.exists()) await tmp.delete();
  }
}

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
