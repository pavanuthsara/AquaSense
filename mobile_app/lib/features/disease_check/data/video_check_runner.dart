import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/decoded_frame.dart';
import '../domain/fish_box.dart';
import '../domain/fish_crop_classifier.dart';
import '../domain/fish_detector.dart';
import '../domain/picked_video.dart';
import '../domain/video_check_analyzer.dart';
import '../domain/video_check_result.dart';
import '../domain/video_check_settings.dart';
import '../domain/video_frame_extractor.dart';
import 'crop_preprocessor.dart';

/// Lets the UI cancel a running video check between frames.
class VideoCheckCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Runs the two-stage video check over a clip, matching check_video.py:
/// detect fish, crop and score each, follow each fish across frames, vote.
class VideoCheckRunner {
  VideoCheckRunner({
    required this.detector,
    required this.classifier,
    required this.extractor,
  });

  final FishDetector detector;
  final FishCropClassifier classifier;
  final VideoFrameExtractor extractor;

  /// Processes [video] and returns the result. [onProgress] is called with the
  /// number of frames checked and the total. When [closeUp] is true the whole
  /// frame is treated as one fish and `not_fish` is not dropped.
  Future<VideoCheckResult> run(
    PickedVideo video, {
    bool closeUp = false,
    void Function(int done, int total)? onProgress,
    VideoCheckCancelToken? cancel,
  }) async {
    final total = await extractor.frameCount(video);
    final analyzer = VideoCheckAnalyzer();
    final stopwatch = Stopwatch()..start();
    var done = 0;

    await for (final frame in extractor.frames(video)) {
      if (cancel?.isCancelled ?? false) break;
      final boxes = closeUp
          ? [FishBox(x0: 0, y0: 0, x1: frame.width, y1: frame.height, score: 1)]
          : await detector.detect(frame);

      final checked = <CheckedBox>[];
      for (final box in boxes) {
        if (box.shorterSide < videoMinFishPixels) {
          checked.add(
            CheckedBox(box: box),
          ); // too small: joins a track, no score
          continue;
        }
        final cropBox = cropBoxWithMargin(box, frame.width, frame.height);
        final crop = cropRegion(frame, cropBox);
        final result = await classifier.classify(crop);
        if (result.isNotFish && !closeUp) continue; // drop non-fish
        checked.add(
          CheckedBox(
            box: box,
            score: result.whiteSpotScore,
            thumbnail: _thumbnail(crop),
          ),
        );
      }
      analyzer.addFrame(checked);
      done += 1;
      onProgress?.call(done, total);
    }

    stopwatch.stop();
    return analyzer.result(timeTaken: stopwatch.elapsed);
  }

  /// A small JPEG of a fish crop for display in the result list.
  Uint8List _thumbnail(DecodedFrame crop) {
    final image = img.Image.fromBytes(
      width: crop.width,
      height: crop.height,
      bytes: crop.rgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    final longer = crop.width > crop.height ? crop.width : crop.height;
    final shown = longer > 200
        ? img.copyResize(image, width: (crop.width * 200 / longer).round())
        : image;
    return Uint8List.fromList(img.encodeJpg(shown, quality: 80));
  }
}
