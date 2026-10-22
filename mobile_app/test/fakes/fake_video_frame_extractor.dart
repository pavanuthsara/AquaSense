import 'package:mobile_app/features/disease_check/domain/decoded_frame.dart';
import 'package:mobile_app/features/disease_check/domain/picked_video.dart';
import 'package:mobile_app/features/disease_check/domain/video_frame_extractor.dart';

/// A [VideoFrameExtractor] that emits preset frames, for UI/orchestration tests.
class FakeVideoFrameExtractor implements VideoFrameExtractor {
  FakeVideoFrameExtractor(this.framesToEmit);

  final List<DecodedFrame> framesToEmit;

  @override
  Stream<DecodedFrame> frames(PickedVideo video, {double fps = 2.0}) =>
      Stream.fromIterable(framesToEmit);

  @override
  Future<int> frameCount(PickedVideo video, {double fps = 2.0}) async =>
      framesToEmit.length;
}
