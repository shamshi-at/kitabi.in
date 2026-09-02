import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Ask whether to take a new photo or choose an existing one, before any image
/// pick in the app (covers, author portraits, publisher logos). Returns the
/// chosen [ImageSource], or null if dismissed. A visible Cancel row makes
/// backing out obvious (you can also swipe down / tap the scrim).
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGrip(),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: AppColors.oxblood),
            title: Text(l10n.imageSourceCamera),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: AppColors.oxblood),
            title: Text(l10n.imageSourceGallery),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          _CancelRow(onTap: () => Navigator.of(context).pop()),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// What the user chose from the cover-options sheet on the add-book form. The
/// sheet adapts: an empty slot offers only capture; a slot that already holds a
/// photo also offers adjust (re-crop) and remove.
enum CoverAction { camera, gallery, adjust, rotate, remove }

/// The richer sheet behind a cover thumbnail on the add-book form. When
/// [hasImage] is false it's just "take a photo / choose from gallery"; when a
/// cover is already set it adds "adjust — crop, rotate, reframe" and "remove".
/// Always has a visible Cancel so a mis-tap on the cover is a no-op, not a
/// forced camera launch. Returns null if dismissed.
Future<CoverAction?> showCoverActionSheet(
  BuildContext context, {
  required bool hasImage,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<CoverAction>(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGrip(),
          if (hasImage) ...[
            ListTile(
              leading: Icon(Icons.crop_rotate, color: AppColors.oxblood),
              title: Text(l10n.coverActionAdjust),
              onTap: () => Navigator.of(context).pop(CoverAction.adjust),
            ),
            // Free-angle rotation is its own step: the native cropper only
            // offers 90° buttons, so a photo taken slightly askew had no way
            // to be straightened (owner request, 21 Jul 2026).
            ListTile(
              leading: Icon(Icons.rotate_90_degrees_ccw, color: AppColors.oxblood),
              title: Text(l10n.coverRotate),
              onTap: () => Navigator.of(context).pop(CoverAction.rotate),
            ),
          ],
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: AppColors.oxblood),
            title: Text(hasImage ? l10n.coverActionReplaceCamera : l10n.imageSourceCamera),
            onTap: () => Navigator.of(context).pop(CoverAction.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: AppColors.oxblood),
            title: Text(hasImage ? l10n.coverActionReplaceGallery : l10n.imageSourceGallery),
            onTap: () => Navigator.of(context).pop(CoverAction.gallery),
          ),
          if (hasImage)
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.oxblood),
              title: Text(l10n.coverActionRemove),
              onTap: () => Navigator.of(context).pop(CoverAction.remove),
            ),
          _CancelRow(onTap: () => Navigator.of(context).pop()),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// What the reader chose from the "scan the back cover" sheet on the add-book
/// form: read the back-cover photo the form already holds, or point the camera
/// at the book. Shown only when an uploaded back cover exists — with nothing
/// to re-read, the flow goes straight to the camera instead (owner request,
/// 2 Sep 2026: re-photographing what the form already has is the camera as a
/// punishment).
enum ScanBackChoice { uploaded, capture }

Future<ScanBackChoice?> showScanBackSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<ScanBackChoice>(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGrip(),
          ListTile(
            leading: Icon(Icons.image_outlined, color: AppColors.oxblood),
            title: Text(l10n.scanBackSheetUploaded),
            onTap: () => Navigator.of(context).pop(ScanBackChoice.uploaded),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: AppColors.oxblood),
            title: Text(l10n.scanBackSheetCapture),
            onTap: () => Navigator.of(context).pop(ScanBackChoice.capture),
          ),
          _CancelRow(onTap: () => Navigator.of(context).pop()),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// The step between two chained cover captures. When a camera capture has just
/// filled one side of a coverless book and the other side is still empty, this
/// asks — right in the capture flow, before returning to the screen — whether
/// to keep the camera going for the other side. Returns true to capture the
/// side named by [nextIsBack] now; false (also on dismiss) to stop with what's
/// there. Without this, adding both covers meant: tap front, capture, come all
/// the way back, tap back, capture again (owner request, 9 Aug 2026).
Future<bool> showChainedCoverSheet(
  BuildContext context, {
  required bool nextIsBack,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final capture = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetGrip(),
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: AppColors.oxblood),
            title: Text(
              nextIsBack ? l10n.coverChainFrontAdded : l10n.coverChainBackAdded,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: AppColors.oxblood),
            title: Text(
              nextIsBack ? l10n.coverChainCaptureBack : l10n.coverChainCaptureFront,
            ),
            onTap: () => Navigator.of(context).pop(true),
          ),
          ListTile(
            leading: Icon(Icons.close, color: AppColors.inkSoft),
            title: Text(
              l10n.coverChainSkip,
              style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
            ),
            onTap: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  return capture ?? false;
}

class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _CancelRow extends StatelessWidget {
  const _CancelRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: Icon(Icons.close, color: AppColors.inkSoft),
      title: Text(
        l10n.imageSourceCancel,
        style: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
