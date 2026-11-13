import 'dart:typed_data';

/// One decoded video frame, upright, as row-major RGB bytes.
///
/// Carries only primitives so it can be sent to a background isolate. The
/// video frame extractor (DIS-016) produces these; the fish finder and crop
/// classifier consume them. Sizes are the real video pixel sizes, because the
/// `MIN_FISH_PX` rule is measured in video pixels.
class DecodedFrame {
  const DecodedFrame({
    required this.width,
    required this.height,
    required this.rgb,
    required this.timeMs,
  });

  final int width;
  final int height;

  /// Red, green, blue per pixel, row by row. Length is `width * height * 3`.
  final Uint8List rgb;

  /// Position of this frame in the video, in milliseconds.
  final int timeMs;
}
