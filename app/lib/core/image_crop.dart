import 'dart:typed_data';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'theme/app_theme.dart';

/// The fixed crop grids the app's image pickers offer, so every uploaded image
/// lands in the shape it's rendered in — book covers as 2:3 portraits, author
/// portraits and publisher logos as 1:1 squares. Locked aspect ratio, so the
/// user only chooses framing, never a wrong shape.
enum CropRatio {
  cover(2, 3, 'Crop cover'),
  square(1, 1, 'Crop photo');

  const CropRatio(this.x, this.y, this.title);

  final double x;
  final double y;
  final String title;
}

/// Take a photo (or pick from the gallery) and crop it to [ratio] in one step,
/// returning the JPEG bytes ready to upload. Null if the user cancels the
/// capture, or cancels the crop.
///
/// Resilience: if the cropper itself *fails to run* (image_cropper has
/// device-specific iOS runtime failures under Swift Package Manager that don't
/// reproduce in CI), we do NOT discard the capture — the original photo is
/// returned uncropped so the upload still happens and the photo isn't lost. The
/// user can re-crop later via "Adjust". Only a genuine user-cancel (crop UI
/// shown, then dismissed) returns null.
Future<Uint8List?> pickAndCropImage({
  required ImageSource source,
  required CropRatio ratio,
}) async {
  // Cap the capture at the source — an uncapped camera photo is 12MP+ and
  // multi-MB, which (a) made messaging apps silently drop the og:image link
  // preview for books with user-photographed covers (WhatsApp rejects large
  // preview images), (b) let the share card rasterise before the huge JPEG
  // decoded, and (c) burns Supabase free-tier storage. 1600px on the long
  // side comfortably out-resolves every surface that renders a cover
  // (full-screen viewer included) while keeping a 2:3 crop at ~200–400KB.
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  if (picked == null) return null; // capture/pick cancelled
  // iOS race, root-caused live on-device (8 Jul 2026): presenting the cropper
  // while the camera's "Use Photo" sheet is still animating its dismissal
  // makes the native call HANG — no throw, no return, so no fallback can
  // fire. 400ms was not enough for the camera sheet (it was for the gallery
  // picker); 1.5s was verified to present reliably on a real iPhone (iOS 26).
  // Don't shorten this without re-testing on a physical device.
  await Future<void>.delayed(
    source == ImageSource.camera
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 400),
  );
  try {
    return await cropPickedImage(picked.path, ratio);
  } catch (_) {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      return await cropPickedImage(picked.path, ratio);
    } catch (_) {
      // Cropper still couldn't present — keep the photo, upload as-is.
      return picked.readAsBytes();
    }
  }
}

/// Open the cropper on a just-picked image and return the cropped JPEG bytes
/// ready to upload. [ratio] is the *starting* frame ([ratio.x]:[ratio.y]) — but
/// the user is free to resize, move, reshape (pick another aspect), rotate, and
/// zoom; the crop rectangle is no longer locked (owner feedback 8 Jul 2026: the
/// locked box read as "can't trim/resize/move"). The app renders every cover in
/// a 2:3 frame with BoxFit.cover, so an off-ratio crop still displays cleanly.
/// Returns null if the user backs out of the crop. Themed to the Reading Room
/// palette on both platforms.
Future<Uint8List?> cropPickedImage(String sourcePath, CropRatio ratio) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    aspectRatio: CropAspectRatio(ratioX: ratio.x, ratioY: ratio.y),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: ratio.title,
        toolbarColor: AppColors.oxblood,
        toolbarWidgetColor: AppColors.paper,
        activeControlsWidgetColor: AppColors.oxblood,
        backgroundColor: AppColors.night,
        // Free-form: resize/move the crop box, plus rotate/scale.
        lockAspectRatio: false,
        hideBottomControls: false,
        showCropGrid: true,
      ),
      IOSUiSettings(
        title: ratio.title,
        // Unlocked so the crop rectangle can be dragged/resized; the aspect
        // picker and reset are available for framing.
        aspectRatioLockEnabled: false,
        resetAspectRatioEnabled: true,
        aspectRatioPickerButtonHidden: false,
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
      ),
    ],
  );
  if (cropped == null) return null;
  return cropped.readAsBytes();
}
