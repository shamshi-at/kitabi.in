import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Free-angle photo rotation, by finger (owner request, 21 Jul 2026).
///
/// The cropper can't do this: `image_cropper` wraps uCrop and
/// TOCropViewController, and neither exposes a rotation *gesture* through the
/// plugin — only 90° buttons. So rotation happens here, before the crop, and
/// the rotated bytes are what the cropper then receives.
///
/// Baked with `dart:ui` (decode → rotated canvas → re-encode) rather than by
/// adding an image-processing package: Flutter already ships everything this
/// needs, and rule 8 says the default answer to a new dependency is no.
Future<Uint8List> bakeRotation(Uint8List source, double radians) async {
  // A quarter-turn multiple within a hair's breadth is almost certainly what
  // the reader meant; snapping avoids a 0.4° skew nobody asked for.
  final snapped = _snap(radians);
  if (snapped == 0) return source;

  final codec = await ui.instantiateImageCodec(source);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final w = image.width.toDouble();
  final h = image.height.toDouble();

  // The rotated image needs a bigger canvas or the corners get clipped.
  final cos = math.cos(snapped).abs();
  final sin = math.sin(snapped).abs();
  final outW = w * cos + h * sin;
  final outH = w * sin + h * cos;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(outW / 2, outH / 2);
  canvas.rotate(snapped);
  canvas.drawImage(
    image,
    Offset(-w / 2, -h / 2),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final rotated = await picture.toImage(outW.round(), outH.round());
  final bytes = await rotated.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  rotated.dispose();
  picture.dispose();
  // Fall back to the original rather than losing the photo to an encode miss.
  return bytes?.buffer.asUint8List() ?? source;
}

double _snap(double radians) {
  const tolerance = 0.02; // ~1.1°
  for (var quarter = -4; quarter <= 4; quarter++) {
    final target = quarter * math.pi / 2;
    if ((radians - target).abs() < tolerance) return target % (2 * math.pi);
  }
  return radians;
}

/// The rotate step: the photo under two fingers, plus 90° nudges for the
/// common "it came in sideways" case. Returns the rotated bytes, or null if
/// the reader backs out — in which case the caller keeps the original.
class RotatePhotoScreen extends StatefulWidget {
  const RotatePhotoScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<RotatePhotoScreen> createState() => _RotatePhotoScreenState();
}

class _RotatePhotoScreenState extends State<RotatePhotoScreen> {
  double _angle = 0;
  double _gestureStart = 0;
  bool _working = false;

  double get _degrees {
    final d = _angle * 180 / math.pi % 360;
    return d < 0 ? d + 360 : d;
  }

  Future<void> _done() async {
    if (_working) return;
    setState(() => _working = true);
    final out = await bakeRotation(widget.bytes, _angle);
    Haptics.success();
    if (mounted) Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF17120C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Color(0xFF8C7C64)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.rotateTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEDE3D0),
                      ),
                    ),
                  ),
                  Text(
                    '${_degrees.round()}°',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFA9997F)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                // Two fingers twist the photo; one finger does nothing, so a
                // stray drag can't nudge it off true.
                onScaleStart: (_) => _gestureStart = _angle,
                onScaleUpdate: (d) {
                  if (d.pointerCount < 2) return;
                  setState(() => _angle = _gestureStart + d.rotation);
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Transform.rotate(
                      angle: _angle,
                      child: Image.memory(widget.bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.rotateHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Color(0xFFA9997F), height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(
                children: [
                  _Nudge(
                    icon: Icons.rotate_left,
                    onTap: () => setState(() => _angle -= math.pi / 2),
                  ),
                  const SizedBox(width: 10),
                  _Nudge(
                    icon: Icons.rotate_right,
                    onTap: () => setState(() => _angle += math.pi / 2),
                  ),
                  const SizedBox(width: 10),
                  if (_angle != 0)
                    _Nudge(
                      icon: Icons.restart_alt,
                      onTap: () => setState(() => _angle = 0),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _working ? null : _done,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE3B14C),
                      foregroundColor: const Color(0xFF17120C),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                    ),
                    child: Text(
                      l10n.rotateApply,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF221A11),
          border: Border.all(color: const Color(0xFF3A2F20)),
        ),
        child: Icon(icon, size: 19, color: AppColors.gold),
      ),
    );
  }
}
