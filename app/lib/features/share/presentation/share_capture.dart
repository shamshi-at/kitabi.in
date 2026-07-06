import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';

/// Rasterise the widget behind [cardKey] (a `RepaintBoundary`) to a PNG and hand
/// it to the OS share sheet together with [text] (which always carries the real
/// link, so a recipient who can't render the image still gets a tappable URL).
/// Falls back to sharing [text] alone if the capture fails, and surfaces
/// [onFailed] only if even that fails. Shared by the book and author/publisher
/// share sheets so the image-or-text-fallback behaviour stays identical.
Future<void> captureAndShareCard({
  required BuildContext context,
  required GlobalKey cardKey,
  required String text,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final origin = _originRect(context);
  try {
    // Let the current frame finish painting before we rasterise — capturing
    // mid-paint is the usual cause of a blank/failed card grab on device.
    await WidgetsBinding.instance.endOfFrame;
    final boundary = cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) {
      throw StateError('share card not ready');
    }
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('could not encode card');
    }
    final file = XFile.fromData(
      bytes.buffer.asUint8List(),
      name: 'kitabi.png',
      mimeType: 'image/png',
    );
    await Share.shareXFiles([file], text: text, sharePositionOrigin: origin);
  } catch (_) {
    // If the image capture/share fails for any reason, still share the link.
    try {
      await Share.share(text, sharePositionOrigin: origin);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    }
  }
}

/// iPad requires an anchor rect for the share popover — use the caller's own
/// bounds, falling back to a sane default if the box isn't laid out.
Rect _originRect(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return const Rect.fromLTWH(0, 0, 1, 1);
}
