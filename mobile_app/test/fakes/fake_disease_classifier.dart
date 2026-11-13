import 'dart:typed_data';

import 'package:mobile_app/features/disease_check/domain/disease_classifier.dart';
import 'package:mobile_app/features/disease_check/domain/disease_prediction.dart';

/// Answers with fixed scores for `healthy` and `white_spot`.
class FakeDiseaseClassifier implements DiseaseClassifier {
  FakeDiseaseClassifier({this.healthy = 0.02, this.whiteSpot = 0.98});

  double healthy;
  double whiteSpot;
  Object? error;
  int calls = 0;
  bool disposed = false;

  @override
  Future<DiseasePrediction> classify(Uint8List imageBytes) async {
    calls += 1;
    if (error != null) {
      throw error!;
    }
    return DiseasePrediction.fromScores(
      labels: const ['healthy', 'white_spot'],
      scores: [healthy, whiteSpot],
      modelVersion: bundledModelVersion,
      inferenceTime: const Duration(milliseconds: 35),
      checkedAt: DateTime.utc(2026, 10, 20, 9, 30),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
