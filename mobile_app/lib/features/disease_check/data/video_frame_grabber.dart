import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Reads a video's length and single frames at given times. Isolates the native
/// plugins behind one small interface so the frame extractor can be tested with
/// a fake.
abstract interface class FrameGrabber {
  /// The video's length in milliseconds.
  Future<int> durationMs(String path);

  /// One frame at [timeMs] as encoded (PNG) bytes at full resolution, or null
  /// if the frame could not be read.
  Future<Uint8List?> frameBytesAt(String path, int timeMs);
}

/// The real [FrameGrabber]: `video_player` for the length, `video_thumbnail`
/// for full-size PNG frames at a given millisecond.
class PluginFrameGrabber implements FrameGrabber {
  const PluginFrameGrabber();

  @override
  Future<int> durationMs(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return controller.value.duration.inMilliseconds;
    } finally {
      await controller.dispose();
    }
  }

  @override
  Future<Uint8List?> frameBytesAt(String path, int timeMs) {
    return VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.PNG,
      timeMs: timeMs,
      maxWidth: 0, // 0 = original width (full resolution)
      maxHeight: 0,
      quality: 100,
    );
  }
}
