import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/photo_rotate.dart';

/// Free-angle rotation is baked with dart:ui rather than an image package.
/// The parts worth pinning are the ones a reader would notice: a quarter turn
/// swaps the dimensions, a near-quarter turn snaps (nobody means 89.6°), and
/// no rotation is a no-op that doesn't re-encode the photo for nothing.
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF7E2A33),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<(int, int)> _size(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return (frame.image.width, frame.image.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no rotation returns the original bytes untouched', () async {
    final src = await _png(40, 60);
    expect(identical(await bakeRotation(src, 0), src), isTrue);
  });

  test('a quarter turn swaps width and height', () async {
    final src = await _png(40, 60);
    final out = await bakeRotation(src, math.pi / 2);
    expect(await _size(out), (60, 40));
  });

  test('a near-quarter turn snaps, so a hand-twist lands square', () async {
    // 89.6° — the reader meant 90; without snapping the cover sits skewed by
    // half a degree forever.
    final src = await _png(40, 60);
    final out = await bakeRotation(src, 89.6 * math.pi / 180);
    expect(await _size(out), (60, 40));
  });

  test('a genuinely oblique angle is kept, and grows the canvas', () async {
    final src = await _png(40, 60);
    final out = await bakeRotation(src, math.pi / 4); // 45°, nowhere near square
    final (w, h) = await _size(out);
    // Corners must not be clipped: a rotated rect needs a bigger box than
    // either original dimension.
    expect(w, greaterThan(60));
    expect(h, greaterThan(60));
  });

  test('a half turn keeps the dimensions', () async {
    final src = await _png(40, 60);
    expect(await _size(await bakeRotation(src, math.pi)), (40, 60));
  });
}
