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
  final picked = await ImagePicker().pickImage(source: source);
  if (picked == null) return null; // capture/pick cancelled
  try {
    return await cropPickedImage(picked.path, ratio);
  } catch (_) {
    // Cropper couldn't present on this device — keep the photo, upload as-is.
    return picked.readAsBytes();
  }
}

/// Open the cropper on a just-picked image, locked to [ratio], and return the
/// cropped JPEG bytes ready to upload. Returns null if the user backs out of the
/// crop step (treated the same as cancelling the pick). Themed to the Reading
/// Room palette on both platforms.
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
        // Keep the shape locked (covers stay 2:3, portraits 1:1) but show the
        // rotate/scale controls so a hand-held photo can be straightened and
        // reframed — that's the "adjust" step, beyond just pan/zoom.
        lockAspectRatio: true,
        hideBottomControls: false,
        showCropGrid: true,
      ),
      IOSUiSettings(
        title: ratio.title,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        // Allow rotation so a tilted cover photo can be straightened; the aspect
        // stays locked to the render shape.
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
      ),
    ],
  );
  if (cropped == null) return null;
  return cropped.readAsBytes();
}
