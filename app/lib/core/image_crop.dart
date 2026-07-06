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
/// returning the cropped JPEG bytes ready to upload. Null if the user cancels
/// either the capture or the crop.
Future<Uint8List?> pickAndCropImage({
  required ImageSource source,
  required CropRatio ratio,
}) async {
  final picked = await ImagePicker().pickImage(source: source);
  if (picked == null) return null;
  return cropPickedImage(picked.path, ratio);
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
        lockAspectRatio: true,
        hideBottomControls: true,
      ),
      IOSUiSettings(
        title: ratio.title,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        rotateButtonsHidden: true,
      ),
    ],
  );
  if (cropped == null) return null;
  return cropped.readAsBytes();
}
