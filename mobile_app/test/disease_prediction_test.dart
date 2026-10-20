import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/disease_check/domain/disease_info.dart';
import 'package:mobile_app/features/disease_check/domain/disease_prediction.dart';

DiseasePrediction predict(List<double> scores) {
  return DiseasePrediction.fromScores(
    labels: const ['healthy', 'white_spot'],
    scores: scores,
    modelVersion: bundledModelVersion,
    inferenceTime: const Duration(milliseconds: 40),
    checkedAt: DateTime.utc(2026, 10, 20),
  );
}

void main() {
  test('highest score becomes the answer', () {
    final prediction = predict([0.03, 0.97]);

    expect(prediction.topLabel, 'white_spot');
    expect(prediction.confidence, closeTo(0.97, 1e-9));
    expect(prediction.isUncertain, isFalse);
    expect(prediction.scores.map((s) => s.label), ['white_spot', 'healthy']);
  });

  test('a top score below 0.6 is not sure', () {
    expect(predict([0.55, 0.45]).isUncertain, isTrue);
    expect(predict([0.6, 0.4]).isUncertain, isFalse);
  });

  test('mismatched labels and scores are rejected', () {
    expect(
      () => DiseasePrediction.fromScores(
        labels: const ['healthy'],
        scores: const [0.5, 0.5],
        modelVersion: bundledModelVersion,
        inferenceTime: Duration.zero,
        checkedAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });

  test('unknown labels get readable fallback information', () {
    expect(DiseaseInfo.forLabel('white_spot').displayName, 'White spot');
    expect(DiseaseInfo.forLabel('fin_rot').displayName, 'Fin rot');
    expect(DiseaseInfo.forLabel('healthy').isDisease, isFalse);
  });
}
