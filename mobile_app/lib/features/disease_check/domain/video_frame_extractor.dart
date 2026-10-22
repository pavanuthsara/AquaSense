import 'decoded_frame.dart';
import 'picked_video.dart';
import 'video_check_settings.dart';

/// Pulls frames out of a video at a fixed rate, upright and full size.
abstract interface class VideoFrameExtractor {
  /// Emits frames at [fps] per second of video, from 0 ms upward, stopping at
  /// [videoMaxDuration]. Sizes are the real video pixel sizes.
  Stream<DecodedFrame> frames(
    PickedVideo video, {
    double fps = videoFramesPerSecond,
  });
}
