import 'picked_video.dart';

/// Records or picks a video of fish to check.
///
/// The real version uses the camera and gallery. Tests use a fake.
abstract interface class FishVideoSource {
  /// Records a new video with the camera, or null if cancelled.
  Future<PickedVideo?> recordVideo();

  /// Picks an existing video from the gallery, or null if cancelled.
  Future<PickedVideo?> pickVideo();
}
