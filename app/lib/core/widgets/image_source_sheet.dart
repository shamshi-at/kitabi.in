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
enum CoverAction { camera, gallery, adjust, remove }

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
          if (hasImage)
            ListTile(
              leading: Icon(Icons.crop_rotate, color: AppColors.oxblood),
              title: Text(l10n.coverActionAdjust),
              onTap: () => Navigator.of(context).pop(CoverAction.adjust),
            ),
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
