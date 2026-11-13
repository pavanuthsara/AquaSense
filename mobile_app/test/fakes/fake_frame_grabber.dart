import 'dart:typed_data';

import 'package:mobile_app/features/disease_check/data/video_frame_grabber.dart';

/// A [FrameGrabber] that returns preset bytes per time, for extractor tests.
class FakeFrameGrabber implements FrameGrabber {
  FakeFrameGrabber({required this.duration, required this.framesByTime});

  final int duration;
  final Map<int, Uint8List?> framesByTime;
  final List<int> requested = [];

  @override
  Future<int> durationMs(String path) async => duration;

  @override
  Future<Uint8List?> frameBytesAt(String path, int timeMs) async {
    requested.add(timeMs);
    return framesByTime[timeMs];
  }
}
