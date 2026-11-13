import 'dart:typed_data';

import 'disease_prediction.dart';

/// Runs the disease model on one photo.
///
/// The real version runs the bundled TFLite model on the phone. Tests use a
/// fake, because widget tests cannot load the native TFLite library.
abstract interface class DiseaseClassifier {
  /// Classifies an encoded image (JPEG or PNG bytes).
  Future<DiseasePrediction> classify(Uint8List imageBytes);

  /// Frees the model's memory.
  Future<void> dispose();
}

class DiseaseClassifierException implements Exception {
  const DiseaseClassifierException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
