import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/net_image.dart';

/// Rasterise the widget behind [cardKey] (a `RepaintBoundary`) to a PNG and
/// hand it to the OS share sheet **together with [text]** — the caption on a
/// period card, the link on a book/entity one — so the message arrives the way
/// Apple Books' reading card does: a picture with words under it, nothing for
/// the reader to paste.
///
/// It used to share the image alone and put the caption on the clipboard, on
/// the conclusion that WhatsApp drops one when handed both (26 Aug 2026 —
/// "just the text is getting shared"). That conclusion was wrong, and the
/// evidence was in the same file: the readiness check was
/// `RenderObject.debugNeedsPaint`, whose value is assigned only inside an
/// `assert`, so a **release** build threw `LateInitializationError` on every
/// call and every share on every reader's phone went down the text-only
/// *fallback* below. WhatsApp was never choosing; the capture was throwing.
/// That was fixed on 6 Sep 2026 — after a second report in the same words —
/// but the workaround written against the misdiagnosis outlived it, and the
/// owner reported the clipboard step itself as the defect (8 Sep 2026).
///
/// The clipboard copy stays as belt-and-braces (a recipient app that ignores
/// the text still leaves it one paste away) but is silent now: the snackbar
/// announced a workaround that no longer describes what happens.
///
/// Falls back to sharing [text] alone if the capture fails — and *says so*.
/// A silent fallback is what hid the bug above for two release cycles.
/// Shared by all three card sheets (period / book / entity) so the behaviour
/// stays identical.
Future<void> captureAndShareCard({
  required BuildContext context,
  required GlobalKey cardKey,
  required String text,
  double targetWidthPx = 1080,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final origin = _originRect(context);
  try {
    final png = await captureCardPng(cardKey, targetWidthPx: targetWidthPx);
    final file = XFile.fromData(png, name: 'kitabi.png', mimeType: 'image/png');
    // Clipboard first, share second — copying after the share sheet opens is
    // exactly when iOS may suspend us. Best-effort: a clipboard hiccup must
    // not cost the reader the share itself.
    if (text.trim().isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: text));
      } catch (_) {}
    }
    await Share.shareXFiles([file], text: text, sharePositionOrigin: origin);
  } catch (err, stack) {
    // If the image capture/share fails for any reason, still share the text —
    // but never quietly: a fallback nobody can see is a bug nobody reports.
    FlutterError.reportError(FlutterErrorDetails(
      exception: err,
      stack: stack,
      library: 'kitabi share',
      context: ErrorDescription('capturing a share card'),
    ));
    messenger.showSnackBar(SnackBar(content: Text(l10n.shareCardFallback)));
    try {
      await Share.share(text, sharePositionOrigin: origin);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    }
  }
}

/// Rasterise the `RepaintBoundary` behind [cardKey] to PNG bytes, at least
/// [targetWidthPx] wide. Throws when the boundary isn't in the tree or the
/// image can't be encoded. Split from the share so a test can prove the
/// capture itself — the half that broke — without a share plugin.
///
/// Deliberately reads **no `debug*` getter**: in a release build
/// `debugNeedsPaint` throws rather than answering (see [captureAndShareCard]),
/// and every other `debug*` on `RenderObject` is a debug-mode-only contract
/// too. Readiness is `endOfFrame` plus an attached, laid-out boundary.
Future<Uint8List> captureCardPng(GlobalKey cardKey, {double targetWidthPx = 1080}) async {
  // Let the current frame finish painting before we rasterise — capturing
  // mid-paint is the usual cause of a blank/failed card grab on device.
  await WidgetsBinding.instance.endOfFrame;
  final boundary = cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null || !boundary.attached || !boundary.hasSize) {
    throw StateError('share card not ready');
  }
  // Scale the capture off the preview's *logical* size so the output is at
  // least [targetWidthPx] wide — the Story preview is ~168 logical px, and
  // a fixed 3x ratio shipped a 504px image to a 1080×1920 Instagram story
  // (ux-review 2026-07-28). Floor of 3x so small previews never regress.
  final logicalWidth = boundary.size.width;
  final pixelRatio = logicalWidth > 0 ? math.max(3.0, targetWidthPx / logicalWidth) : 3.0;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('could not encode card');
    return bytes.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Wait (bounded) until [url] is decoded into the image cache, so a card
/// capture that follows paints the real photo — tapping Share moments after
/// opening the sheet used to rasterise before a slow/large cover resolved,
/// shipping a card with the typeset fallback instead of the photo. A timeout
/// or a failed load just returns: the card falls back gracefully.
Future<void> ensureImageLoaded(BuildContext context, String? url) async {
  if (url == null) return;
  try {
    await precacheImage(netImageProvider(url), context)
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    // Timeout / dead URL — capture proceeds with the fallback rendering.
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
