import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_app/features/disease_check/data/thumbnail_video_frame_extractor.dart';
import 'package:mobile_app/features/disease_check/domain/picked_video.dart';

import '../fakes/fake_frame_grabber.dart';

Uint8List _png(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  const video = PickedVideo(path: 'clip.mp4');

  test(
    'emits frames every 0.5 s at full size with correct timestamps',
    () async {
      final frame = _png(720, 1280);
      final grabber = FakeFrameGrabber(
        duration: 2000,
        framesByTime: {0: frame, 500: frame, 1000: frame, 1500: frame},
      );
      final extractor = ThumbnailVideoFrameExtractor(grabber: grabber);

      final frames = await extractor.frames(video).toList();

      expect(frames.map((f) => f.timeMs), [0, 500, 1000, 1500]);
      expect(frames.first.width, 720);
      expect(frames.first.height, 1280);
      expect(frames.first.rgb.length, 720 * 1280 * 3);
    },
  );

  test('stops at 30 s for a longer clip (60 frames)', () async {
    final frame = _png(64, 64);
    final grabber = FakeFrameGrabber(
      duration: 60000,
      framesByTime: {for (var t = 0; t < 60000; t += 500) t: frame},
    );
    final frames = await ThumbnailVideoFrameExtractor(
      grabber: grabber,
    ).frames(video).toList();

    expect(frames.length, 60); // 0..29500 inclusive, step 500
    expect(frames.last.timeMs, 29500);
  });

  test('skips frames the grabber cannot read', () async {
    final frame = _png(64, 64);
    final grabber = FakeFrameGrabber(
      duration: 2000,
      framesByTime: {0: frame, 500: null, 1000: frame, 1500: null},
    );
    final frames = await ThumbnailVideoFrameExtractor(
      grabber: grabber,
    ).frames(video).toList();

    expect(frames.map((f) => f.timeMs), [0, 1000]);
  });

  test('respects a custom fps', () async {
    final frame = _png(32, 32);
    final grabber = FakeFrameGrabber(
      duration: 2000,
      framesByTime: {for (var t = 0; t < 2000; t += 1000) t: frame},
    );
    final frames = await ThumbnailVideoFrameExtractor(
      grabber: grabber,
    ).frames(video, fps: 1).toList();

    expect(frames.map((f) => f.timeMs), [0, 1000]);
  });
}
