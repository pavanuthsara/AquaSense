import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/decoded_frame.dart';
import '../domain/video_check_settings.dart';

/// Prepares a frame for the fish finder, exactly as `FishFinder.__call__` does
/// in `check_video.py`:
///
/// 1. Scale the frame so its longer side is 512, keeping its shape
///    (`s = 512 / max(H, W)`, linear resize).
/// 2. Paste it, centred with FLOOR division, onto a 512x512 grey (114) square.
/// 3. Write RGB, divided by 255, CHANNELS FIRST (NCHW): the value for channel
///    `c`, row `y`, column `x` goes at `c*512*512 + y*512 + x`.
///
/// Returns a `Float32List` of length `3 * 512 * 512`. Top-level so it can run
/// in a background isolate via `compute`.
Float32List prepareDetectorInput(DecodedFrame frame) {
  const size = fishFinderInputSize;
  final source = img.Image.fromBytes(
    width: frame.width,
    height: frame.height,
    bytes: frame.rgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );

  final s = size / (frame.width > frame.height ? frame.width : frame.height);
  final nw = (frame.width * s).round();
  final nh = (frame.height * s).round();
  final left = (size - nw) ~/ 2;
  final top = (size - nh) ~/ 2;

  final resized = img.copyResize(
    source,
    width: nw,
    height: nh,
    interpolation: img.Interpolation.linear,
  );
  final square = img.Image(width: size, height: size, numChannels: 3);
  img.fill(
    square,
    color: img.ColorRgb8(
      fishFinderPadValue,
      fishFinderPadValue,
      fishFinderPadValue,
    ),
  );
  img.compositeImage(square, resized, dstX: left, dstY: top);

  final hwc = square.getBytes(order: img.ChannelOrder.rgb);
  final plane = size * size;
  final out = Float32List(3 * plane);
  var src = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = y * size + x;
      out[pixel] = hwc[src] / 255.0; // R plane
      out[plane + pixel] = hwc[src + 1] / 255.0; // G plane
      out[2 * plane + pixel] = hwc[src + 2] / 255.0; // B plane
      src += 3;
    }
  }
  return out;
}
