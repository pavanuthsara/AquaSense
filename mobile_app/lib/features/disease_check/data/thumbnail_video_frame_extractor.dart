import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/decoded_frame.dart';
import '../domain/picked_video.dart';
import '../domain/video_check_settings.dart';
import '../domain/video_frame_extractor.dart';
import 'video_frame_grabber.dart';

/// Pulls frames with a [FrameGrabber] at [videoFramesPerSecond], decodes each to
/// RGB, and stops at [videoMaxDuration].
class ThumbnailVideoFrameExtractor implements VideoFrameExtractor {
  const ThumbnailVideoFrameExtractor({
    this.grabber = const PluginFrameGrabber(),
  });

  final FrameGrabber grabber;

  @override
  Stream<DecodedFrame> frames(
    PickedVideo video, {
    double fps = videoFramesPerSecond,
  }) async* {
    final durationMs = await grabber.durationMs(video.path);
    final capMs = math.min(durationMs, videoMaxDuration.inMilliseconds);
    final stepMs = (1000 / fps).round();
    for (var t = 0; t < capMs; t += stepMs) {
      final bytes = await grabber.frameBytesAt(video.path, t);
      if (bytes == null) continue;
      final frame = decodeFrameBytes(bytes, t);
      if (frame != null) yield frame;
    }
  }

  @override
  Future<int> frameCount(
    PickedVideo video, {
    double fps = videoFramesPerSecond,
  }) async {
    final durationMs = await grabber.durationMs(video.path);
    final capMs = math.min(durationMs, videoMaxDuration.inMilliseconds);
    final stepMs = (1000 / fps).round();
    return capMs <= 0 ? 0 : ((capMs - 1) ~/ stepMs) + 1;
  }
}

/// Decodes encoded frame [bytes] (PNG/JPEG) to a [DecodedFrame]. Top-level so
/// it can be reused and tested. Returns null if the bytes cannot be decoded.
DecodedFrame? decodeFrameBytes(Uint8List bytes, int timeMs) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return DecodedFrame(
    width: image.width,
    height: image.height,
    rgb: Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb)),
    timeMs: timeMs,
  );
}
