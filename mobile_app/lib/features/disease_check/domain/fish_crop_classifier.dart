import 'decoded_frame.dart';

/// What the white-spot model says about one fish crop.
class FishCropResult {
  const FishCropResult({
    required this.whiteSpotScore,
    required this.isNotFish,
    required this.probs,
  });

  /// White-spot probability renormalised over the two fish classes only, so it
  /// stays 0..1. Matches `spot` in `SpotModel.__call__` in check_video.py.
  final double whiteSpotScore;

  /// True when the 3-class model's top answer is `not_fish` (a plant, logo,
  /// hand or filter). These boxes are dropped, except in close-up mode.
  final bool isNotFish;

  /// Raw model probabilities, in label order.
  final List<double> probs;
}

/// Scores one fish crop with the white-spot model.
///
/// The real version runs `guppy_video_model.tflite` on the phone. Tests use a
/// fake, because they cannot load the native TFLite library.
abstract interface class FishCropClassifier {
  Future<FishCropResult> classify(DecodedFrame crop);

  /// Frees the model's memory.
  Future<void> dispose();
}
