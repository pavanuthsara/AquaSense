import 'decoded_frame.dart';
import 'fish_box.dart';

/// Finds every fish in a video frame and returns boxes in video pixels.
///
/// The real version runs the YOLO11n `fish_detector.tflite` on the phone.
/// Tests use a fake, because they cannot load the native TFLite library.
abstract interface class FishDetector {
  Future<List<FishBox>> detect(DecodedFrame frame);

  /// Frees the model's memory.
  Future<void> dispose();
}
