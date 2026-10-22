import 'package:mobile_app/features/disease_check/domain/fish_video_source.dart';
import 'package:mobile_app/features/disease_check/domain/picked_video.dart';

/// A [FishVideoSource] that returns a preset video (or null for cancelled).
class FakeFishVideoSource implements FishVideoSource {
  FakeFishVideoSource({this.recorded, this.picked});

  PickedVideo? recorded;
  PickedVideo? picked;

  @override
  Future<PickedVideo?> recordVideo() async => recorded;

  @override
  Future<PickedVideo?> pickVideo() async => picked;
}
